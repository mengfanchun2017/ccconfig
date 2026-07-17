#!/usr/bin/env python3
"""option-llmswitch proxy — time-based Anthropic API router for Claude Code.

Reads llmswitch.json for routing rules, llm.json for provider credentials.
Proxies Anthropic API calls, rewriting model based on time/mode.

Usage: python3 proxy.py [--config llmswitch.json] [--llm-config llm.json]
"""

import argparse
import json
import os
import re
from contextlib import asynccontextmanager
from datetime import datetime, time as dt_time
from pathlib import Path

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import StreamingResponse

CCCONFIG = Path(os.environ.get("CCCONFIG_HOME", Path.home() / "git" / "ccconfig"))


def load_json(path):
    with open(path) as f:
        return json.load(f)


def is_peak(peak_hours):
    now = datetime.now()
    wd = now.weekday()
    t = now.time()
    for block in peak_hours:
        if wd in block["days"]:
            start = dt_time.fromisoformat(block["start"])
            end = dt_time.fromisoformat(block["end"])
            if start <= t < end:
                return True
    return False


def build_provider_registry(llm_config):
    """Build {provider_key: {base_url, key, model, small_model}}."""
    providers = {}
    for key, cfg in llm_config.get("llms", {}).items():
        if not cfg.get("key"):
            continue
        providers[key] = {
            "base_url": cfg["base_url"],
            "key": cfg["key"],
            "model": cfg.get("model", ""),
            "small_model": cfg.get("small_model", cfg.get("model", "")),
        }
    return providers


class ProxyState:
    def __init__(self):
        self.config = None
        self.llm_config = None
        self.providers = {}
        self.config_mtime = 0
        self.current_route = "?"

    def reload_if_changed(self, config_path, llm_config_path):
        try:
            mtime = os.path.getmtime(config_path)
            if mtime > self.config_mtime:
                self.config = load_json(config_path)
                self.llm_config = load_json(llm_config_path)
                self.providers = build_provider_registry(self.llm_config)
                self.config_mtime = mtime
                return True
        except Exception:
            pass
        if self.config is None:
            self.config = {}
        if self.llm_config is None:
            self.llm_config = {}
        if not self.providers:
            try:
                self.llm_config = load_json(llm_config_path)
                self.providers = build_provider_registry(self.llm_config)
            except Exception:
                pass
        return False

    def route(self, model_name):
        """Return (provider_key, target_model) or (None, None) for passthrough."""
        mode = self.config.get("mode", "off")

        if mode == "off":
            current = self.llm_config.get("current", "")
            if current in self.providers:
                return current, model_name
            return None, None

        if mode == "manual":
            target = self.config.get("manual_provider", "")
            if target in self.providers:
                return target, self.providers[target]["model"]
            return None, None

        # auto mode — look up model name in routes config
        routes = self.config.get("routes", {})
        rule = routes.get(model_name)

        if rule is None:
            # Unknown model — apply fallback routing
            fallback = self.config.get("fallback_routing", "main")
            if fallback == "main":
                fallback = self.config.get("model_name", "llmswitch")
            elif fallback == "small":
                fallback = self.config.get("small_model_name", "llmswitch-s")
            rule = routes.get(fallback, {})
            if not rule:
                current = self.llm_config.get("current", "")
                if current in self.providers:
                    return current, model_name
                return None, None

        # String value: always route to this provider
        if isinstance(rule, str):
            target = rule
        else:
            # Dict value: route based on peak/off_peak
            peak = is_peak(self.config.get("peak_hours", []))
            target = rule.get("peak" if peak else "off_peak", "")

        if target in self.providers:
            return target, self.providers[target]["model"]
        return None, None

    def status(self):
        mode = self.config.get("mode", "off")
        peak = is_peak(self.config.get("peak_hours", []))
        if mode == "auto":
            routes = self.config.get("routes", {})
            top = next(
                (r for r in routes.values() if isinstance(r, dict) and "off_peak" in r),
                next(iter(routes.values()), {})
            )
            if isinstance(top, str):
                target = top
            else:
                target = top.get("peak" if peak else "off_peak", "?")
            self.current_route = target
        elif mode == "manual":
            self.current_route = self.config.get("manual_provider", "?")
        else:
            self.current_route = "off"
        return {
            "status": "ok",
            "mode": mode,
            "peak": peak,
            "current_route": self.current_route,
        }


state = ProxyState()
http_client = None


# ========== Provider-specific 请求体转换 ==========
# 解决不同 provider 对 Anthropic API 字段支持的差异，避免 4xx 错误。
# 配置可热重载（通过 llmswitch.json 的 "provider_rules" 字段），无配置时使用 PROVIDER_RULES 默认值。
def _default_provider_rules():
    return {
        # MiniMax Anthropic 端点：忽略 OpenAI-origin 字段；非 thinking 模型不支持 budget_tokens > 0
        # MiniMax 文档说明 presence_penalty / frequency_penalty / logit_bias 被忽略但实测常抛 400，保守剥离
        # Claude Code 在会话恢复时会回放 thinking blocks 到 messages 中，MiniMax 不识别
        "minimax": {
            "strip_top_level": ["presence_penalty", "frequency_penalty", "logit_bias", "logprobs", "top_logprobs"],
            "thinking": "clamp_budget",  # 若 budget_tokens >= max_tokens - safety，把 budget 削到 max_tokens * 0.6
            "strip_thinking_blocks": False,  # MiniMax 实测不报错，保留以维持会话连贯
        },
        # DeepSeek Anthropic 端点：基本全兼容，但 thinking 模式下 strip 一些采样参数（reasoning mode 忽略）
        "deepseek": {
            "strip_top_level": ["logit_bias", "top_logprobs"],
            "thinking": "passthrough",  # 不做处理
            "strip_thinking_blocks": False,
        },
    }


def _load_provider_rules(config):
    """从 llmswitch.json 读 provider_rules，没配就用默认。"""
    return config.get("provider_rules", _default_provider_rules())


def _strip_thinking_blocks(body):
    """从 messages[].content[] 中剥离 type=='thinking' 的块。
    返回 (new_body, changed)。"""
    try:
        data = json.loads(body)
    except Exception:
        return body, False
    if not isinstance(data, dict) or "messages" not in data:
        return body, False
    changed = False
    for msg in data["messages"]:
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        new_content = [b for b in content if not (isinstance(b, dict) and b.get("type") in ("thinking", "redacted_thinking"))]
        if len(new_content) != len(content):
            msg["content"] = new_content
            changed = True
    if changed:
        return json.dumps(data, ensure_ascii=False).encode("utf-8"), True
    return body, False


def _strip_top_level(body, fields):
    """从请求体顶层剥离字段。返回 (new_body, changed)。"""
    if not fields:
        return body, False
    try:
        data = json.loads(body)
    except Exception:
        return body, False
    if not isinstance(data, dict):
        return body, False
    changed = False
    for f in fields:
        if f in data:
            del data[f]
            changed = True
    if changed:
        return json.dumps(data, ensure_ascii=False).encode("utf-8"), True
    return body, False


def _clamp_thinking_budget(body):
    """若 thinking.budget_tokens >= max_tokens（MiniMax 硬性要求 budget < max），
    把它削到 max_tokens * 0.6。解决 Claude Code 已知 bug：adaptive thinking 把 max_tokens
    砍 1/3 但 budget 不变，导致 'max_tokens must be greater than thinking.budget_tokens' 错误。
    返回 (new_body, changed)。"""
    try:
        data = json.loads(body)
    except Exception:
        return body, False
    if not isinstance(data, dict):
        return body, False
    thinking = data.get("thinking")
    if not isinstance(thinking, dict):
        return body, False
    if thinking.get("type") not in ("enabled", "adaptive"):
        return body, False
    budget = thinking.get("budget_tokens")
    max_tokens = data.get("max_tokens")
    if not isinstance(budget, int) or not isinstance(max_tokens, int):
        return body, False
    if budget >= max_tokens:
        # 留 1024 给实际输出
        new_budget = max(1024, max_tokens - 1024)
        thinking["budget_tokens"] = new_budget
        return json.dumps(data, ensure_ascii=False).encode("utf-8"), True
    return body, False


def transform_body_for_provider(body_bytes, provider_key, rules):
    """按 provider 规则转换请求体。返回 (new_body, transformations_applied)。"""
    if not rules:
        return body_bytes, []
    rule = rules.get(provider_key, {})
    if not rule:
        return body_bytes, []
    applied = []
    body = body_bytes
    body, changed = _strip_top_level(body, rule.get("strip_top_level", []))
    if changed:
        applied.append("strip_top_level")
    if rule.get("thinking") == "clamp_budget":
        body, changed = _clamp_thinking_budget(body)
        if changed:
            applied.append("clamp_budget")
    if rule.get("strip_thinking_blocks"):
        body, changed = _strip_thinking_blocks(body)
        if changed:
            applied.append("strip_thinking_blocks")
    return body, applied


@asynccontextmanager
async def lifespan(app: FastAPI):
    global http_client
    llm_config_path = CCCONFIG / "conf" / "llm.json"
    config_path = CCCONFIG / "option-llmswitch" / "conf" / "llmswitch.json"
    state.reload_if_changed(str(config_path), str(llm_config_path))
    http_client = httpx.AsyncClient(timeout=httpx.Timeout(300.0, connect=10.0))
    yield
    await http_client.aclose()


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def health():
    llm_config_path = CCCONFIG / "conf" / "llm.json"
    config_path = CCCONFIG / "option-llmswitch" / "conf" / "llmswitch.json"
    state.reload_if_changed(str(config_path), str(llm_config_path))
    return state.status()


@app.post("/admin/mode")
async def admin_mode(request: Request):
    body = await request.json()
    mode = body.get("mode", "")
    if mode not in ("auto", "manual", "off"):
        return {"error": "invalid mode"}
    config_path = CCCONFIG / "option-llmswitch" / "conf" / "llmswitch.json"
    config = load_json(str(config_path))
    config["mode"] = mode
    if mode == "manual" and "provider" in body:
        config["manual_provider"] = body["provider"]
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    return {"ok": True, "mode": mode}


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"])
async def proxy(path: str, request: Request):
    llm_config_path = CCCONFIG / "conf" / "llm.json"
    config_path = CCCONFIG / "option-llmswitch" / "conf" / "llmswitch.json"
    state.reload_if_changed(str(config_path), str(llm_config_path))

    # Read request body
    body = await request.body()
    content_type = request.headers.get("content-type", "")

    # Only intercept /v1/messages for model routing
    is_messages = path.rstrip("/") in ("v1/messages", "v1/messages/count_tokens")

    provider_key = None
    target_model = None
    model_name = ""

    if is_messages and body and "application/json" in content_type:
        m = re.search(rb'"model"\s*:\s*"([^"]*)"', body)
        if m:
            model_name = m.group(1).decode("utf-8")
            provider_key, target_model = state.route(model_name)
            if provider_key and target_model and target_model != model_name:
                body = body[: m.start(1)] + target_model.encode() + body[m.end(1) :]


    if provider_key is None:
        current = state.llm_config.get("current", "")
        if current in state.providers:
            provider_key = current
        else:
            provider_key = next(iter(state.providers), None)

    if provider_key is None:
        return Response(content=b'{"error":"no provider configured"}', status_code=502,
                        media_type="application/json")

    provider = state.providers[provider_key]
    target_url = f"{provider['base_url'].rstrip('/')}/{path.lstrip('/')}"
    if request.url.query:
        target_url += f"?{request.url.query}"

    # Provider-specific 请求体转换（参数剥离 / thinking 处理）
    rules = _load_provider_rules(state.config or {})
    body, transforms = transform_body_for_provider(body, provider_key, rules)
    if transforms:
        print(f"[llmswitch] {provider_key} transforms={transforms} model={target_model or model_name}", flush=True)

    headers = dict(request.headers)
    headers.pop("host", None)
    headers.pop("authorization", None)
    headers["authorization"] = f"Bearer {provider['key']}"
    headers.pop("content-length", None)

    client = http_client

    try:
        r = await client.request(
            method=request.method,
            url=target_url,
            headers=headers,
            content=body,
        )

        response_headers = dict(r.headers)
        response_headers.pop("transfer-encoding", None)
        response_headers.pop("content-encoding", None)
        response_headers.pop("content-length", None)

        if "text/event-stream" in r.headers.get("content-type", ""):
            async def stream():
                async for chunk in r.aiter_bytes():
                    yield chunk

            return StreamingResponse(
                stream(),
                status_code=r.status_code,
                headers=response_headers,
                media_type="text/event-stream",
            )
        else:
            return Response(
                content=r.content,
                status_code=r.status_code,
                headers=response_headers,
                media_type=r.headers.get("content-type", "application/json"),
            )
    except httpx.ConnectError:
        return Response(
            content=json.dumps({"error": f"cannot connect to {provider_key}"}).encode(),
            status_code=502,
            media_type="application/json",
        )
    except Exception as e:
        return Response(
            content=json.dumps({"error": str(e)}).encode(),
            status_code=502,
            media_type="application/json",
        )


def main():
    parser = argparse.ArgumentParser(description="LLM Switch Proxy")
    parser.add_argument("--host", default="127.0.0.1", help="Listen host")
    parser.add_argument("--port", type=int, default=8899, help="Listen port")
    args = parser.parse_args()

    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()

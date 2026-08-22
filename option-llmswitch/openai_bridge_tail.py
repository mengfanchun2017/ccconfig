#!/usr/bin/env python3
"""Tailscale 隧道版 OpenAI bridge — 专用 altllm_tail。

SSH 隧道场景，bridge 连接本地隧道端口（127.0.0.1:8890）。
与原版差别：默认端口 8895，不与其他 bridge 冲突。

Usage:
    python3 openai_bridge_tail.py --port 8895 --upstream http://127.0.0.1:8890/v1 \
        --upstream-key sk-xxx --upstream-model deepseek-v4-flash
"""
import argparse
import json
import os
import socket
import urllib.parse
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

CCCONFIG = Path(os.environ.get("CCCONFIG_HOME", Path.home() / "git" / "ccconfig"))


def load_json(p):
    with open(p) as f:
        return json.load(f)


def load_upstream_config():
    """从 llmswitch.json 读 openai_bridge 配置；CLI 参数覆盖。"""
    cfg_path = CCCONFIG / "option-llmswitch" / "conf" / "llmswitch.json"
    try:
        cfg = load_json(cfg_path)
    except Exception:
        cfg = {}
    return cfg.get("openai_bridge", {})


def _resolve_upstream(url: str) -> str:
    """解析 upstream URL 中的域名→IP，绕过 Clash fake-ip DNS 干扰。

    用 socket.getaddrinfo 解析域名，再用 IP 替换 URL 中的域名，
    同时返回 (resolved_url, host_header) 供 httpx 使用。
    返回 None 表示解析失败（保持原 URL）。
    """
    parsed = urllib.parse.urlparse(url)
    if not parsed.hostname:
        return None, None
    # 已经是 IP 的不处理
    try:
        socket.inet_aton(parsed.hostname)
        return None, None  # 已经是 IP
    except OSError:
        pass
    try:
        ips = socket.getaddrinfo(parsed.hostname, parsed.port or 443)
        if ips:
            ip = ips[0][4][0]
            resolved = parsed._replace(netloc=f"{ip}:{parsed.port}" if parsed.port else ip)
            return resolved.geturl(), parsed.hostname
    except Exception:
        pass
    return None, None


def anthropic_to_openai_req(anth_body: dict, target_model: str) -> dict:
    """Anthropic Messages API body → OpenAI Chat Completions body."""
    messages = []
    system_blocks = anth_body.get("system")
    if isinstance(system_blocks, list):
        for blk in system_blocks:
            if isinstance(blk, dict) and blk.get("type") == "text":
                messages.append({"role": "system", "content": blk.get("text", "")})
            elif isinstance(blk, str):
                messages.append({"role": "system", "content": blk})
    elif isinstance(system_blocks, str):
        messages.append({"role": "system", "content": system_blocks})

    for msg in anth_body.get("messages", []):
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue
        content = msg.get("content")
        if isinstance(content, str):
            messages.append({"role": role, "content": content})
        elif isinstance(content, list):
            text_parts = []
            tool_calls = []
            for blk in content:
                if not isinstance(blk, dict):
                    continue
                t = blk.get("type")
                if t == "text":
                    text_parts.append(blk.get("text", ""))
                elif t == "image" or t == "image_url":
                    if t == "image":
                        src = blk.get("source", {})
                        if src.get("type") == "base64":
                            text_parts.append({
                                "type": "image_url",
                                "image_url": {"url": f"data:{src.get('media_type')};base64,{src.get('data','')}"},
                            })
                    else:
                        text_parts.append(blk)
                elif t == "tool_use":
                    tool_calls.append({
                        "id": blk.get("id", ""),
                        "type": "function",
                        "function": {
                            "name": blk.get("name", ""),
                            "arguments": json.dumps(blk.get("input", {})),
                        },
                    })
                elif t == "tool_result":
                    tool_id = blk.get("tool_use_id", "")
                    out = blk.get("content")
                    if isinstance(out, list):
                        out = next((b.get("text", "") for b in out if isinstance(b, dict) and b.get("type") == "text"), "")
                    messages.append({"role": "tool", "tool_call_id": tool_id, "content": out or ""})
                elif t in ("thinking", "redacted_thinking"):
                    continue
            if text_parts or tool_calls:
                m = {"role": role, "content": "".join(p for p in text_parts if isinstance(p, str)) or None}
                if tool_calls:
                    m["tool_calls"] = tool_calls
                messages.append(m)

    max_tokens_val = anth_body.get("max_tokens", 4096)
    openai_body = {
        "model": target_model,
        "messages": messages,
        "stream": bool(anth_body.get("stream")),
        "max_tokens": max_tokens_val,
    }
    for k in ("temperature", "top_p", "stop", "frequency_penalty", "presence_penalty", "n"):
        if k in anth_body:
            openai_body[k] = anth_body[k]

    tools = anth_body.get("tools")
    if tools:
        openai_body["tools"] = [
            {
                "type": "function",
                "function": {
                    "name": t.get("name", ""),
                    "description": t.get("description", ""),
                    "parameters": t.get("input_schema", {"type": "object", "properties": {}}),
                },
            }
            for t in tools
        ]
        tool_choice = anth_body.get("tool_choice")
        if tool_choice:
            if tool_choice.get("type") == "tool":
                openai_body["tool_choice"] = {"type": "function", "function": {"name": tool_choice.get("name", "")}}
            else:
                openai_body["tool_choice"] = tool_choice.get("type", "auto")

    return openai_body


def _ensure_started(state, out, msg_id, model):
    if not state.get("started"):
        state["started"] = True
        msg_start = {
            "type": "message_start",
            "message": {
                "id": msg_id, "type": "message", "role": "assistant",
                "model": model, "content": [],
                "stop_reason": None, "stop_sequence": None,
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        }
        out.append(f"event: message_start\ndata: {json.dumps(msg_start, separators=(',', ':'))}\n\n")
        out.append('event: ping\ndata: {"type":"ping"}\n\n')


def _close_text_block(state, out, idx):
    if state.get(f"text_open_{idx}"):
        out.append(f'event: content_block_stop\ndata: {{"type":"content_block_stop","index":{idx}}}\n\n')
        state[f"text_open_{idx}"] = False


def _close_tool_blocks(state, out):
    for key in list(state.keys()):
        if key.endswith("_open") and state.get(key):
            tc_idx = key.replace("_open", "").replace("tool_", "", 1)
            tc_info = state.get(f"tool_{tc_idx}")
            if isinstance(tc_info, dict):
                out.append(f'event: content_block_stop\ndata: {{"type":"content_block_stop","index":{tc_info["index"]}}}\n\n')
            state[key] = False


def openai_chunk_to_anthropic_sse(chunk_text: str, msg_id: str, model: str, state=None):
    """OpenAI stream chunk -> Anthropic SSE 事件集。

    跨 chunk 累积 finish_reason / usage 到 state，在 [DONE] 统一收尾为单个
    message_delta(stop_reason + usage) -> message_stop。md_sent 防护保证
    message_delta 只发一次；收尾关闭所有未关 block，杜绝漏 content_block_stop。
    兼容 provider 各种结尾: finish 在 content chunk、独立空 choices usage chunk、
    裸 [DONE]、length 截断。
    """
    if state is None:
        state = {"started": False, "finished": False, "block_idx": 0,
                 "finish_reason": None, "usage": None, "md_sent": False}
    if not chunk_text:
        return None

    out = []

    def _emit_final():
        # 流结束统一收尾，md_sent 防护保证只发一次 message_delta
        if state.get("md_sent"):
            return
        _close_text_block(state, out, 0)
        _close_tool_blocks(state, out)
        _fr_map = {"stop": "end_turn", "tool_calls": "tool_use",
                   "length": "max_tokens", "content_filter": "content_filtered"}
        anth_reason = _fr_map.get(state.get("finish_reason"), "end_turn")
        delta = {"stop_reason": anth_reason, "stop_sequence": None,
                 "stop_details": {"type": "stop", "reason": anth_reason}}
        msg_delta = {"type": "message_delta", "delta": delta}
        if state.get("usage"):
            msg_delta["usage"] = {"output_tokens": state["usage"].get("completion_tokens", 0)}
        out.append(f"event: message_delta\ndata: {json.dumps(msg_delta, separators=(',', ':'))}\n\n")
        out.append('event: message_stop\ndata: {"type":"message_stop"}\n\n')
        state["md_sent"] = True
        state["finished"] = True

    for line in chunk_text.split("\n"):
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[len("data:"):].strip()
        if not payload:
            continue
        if payload == "[DONE]":
            _emit_final()
            continue
        try:
            obj = json.loads(payload)
        except Exception:
            continue

        if "error" in obj:
            err = obj["error"]
            err_obj = {"type": "error", "error": {"type": "api_error", "message": err.get("message", "unknown")}}
            out.append(f"event: error\ndata: {json.dumps(err_obj, separators=(',', ':'))}\n\n")
            continue

        _ensure_started(state, out, msg_id, model)

        # 累积 finish_reason / usage（choices 可能为空 -> 就地写 state，无 UnboundLocalError）
        if obj.get("usage"):
            state["usage"] = obj["usage"]
        for choice in obj.get("choices", []):
            _fr = choice.get("finish_reason")
            if _fr:
                state["finish_reason"] = _fr
            _usage = choice.get("usage") or obj.get("usage")
            if _usage:
                state["usage"] = _usage

        for choice in obj.get("choices", []):
            delta = choice.get("delta", {})
            content = delta.get("content")
            if content:
                if not state.get("text_open_0"):
                    out.append(
                        'event: content_block_start\n'
                        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
                    )
                    state["text_open_0"] = True
                block_delta = {
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": {"type": "text_delta", "text": content},
                }
                out.append(f"event: content_block_delta\ndata: {json.dumps(block_delta, separators=(',', ':'))}\n\n")

            for tc in delta.get("tool_calls", []):
                tc_idx = tc.get("index", 0)
                tc_key = f"tool_{tc_idx}"

                if tc_key not in state:
                    state[tc_key] = {
                        "index": state.get("block_idx", 0),
                        "id": tc.get("id", ""),
                        "name": "",
                        "args": "",
                    }
                    state["block_idx"] = state.get("block_idx", 0) + 1

                tc_info = state[tc_key]
                if "id" in tc and tc["id"]:
                    tc_info["id"] = tc["id"]
                fn = tc.get("function", {})
                if "name" in fn and fn["name"]:
                    tc_info["name"] = fn["name"]
                if "arguments" in fn:
                    tc_info["args"] += fn["arguments"]

                if not state.get(f"{tc_key}_open"):
                    state[f"{tc_key}_open"] = True
                    block_start = {
                        "type": "content_block_start",
                        "index": tc_info["index"],
                        "content_block": {"type": "tool_use", "id": tc_info["id"], "name": tc_info["name"], "input": {}},
                    }
                    out.append(f"event: content_block_start\ndata: {json.dumps(block_start, separators=(',', ':'))}\n\n")

                if fn.get("arguments"):
                    args_delta = {
                        "type": "content_block_delta",
                        "index": tc_info["index"],
                        "delta": {"type": "input_json_delta", "partial_json": fn["arguments"]},
                    }
                    out.append(f"event: content_block_delta\ndata: {json.dumps(args_delta, separators=(',', ':'))}\n\n")

    return "".join(out) if out else None


def openai_to_anthropic_resp(openai_body: dict, msg_id: str = "msg_bridge") -> dict:
    """非流式：OpenAI Chat Completions response → Anthropic message。"""
    choices = openai_body.get("choices", [])
    content = []
    for ch in choices:
        msg = ch.get("message", {})
        text = msg.get("content")
        if isinstance(text, str) and text:
            content.append({"type": "text", "text": text})
        for tc in (msg.get("tool_calls") or []):
            fn = tc.get("function", {})
            content.append({
                "type": "tool_use",
                "id": tc.get("id", ""),
                "name": fn.get("name", ""),
                "input": json.loads(fn.get("arguments", "{}")) if fn.get("arguments") else {},
            })
    usage = openai_body.get("usage", {})
    finish = None
    if choices:
        fr = choices[0].get("finish_reason", "")
        if fr == "stop":
            finish = "end_turn"
        elif fr == "tool_calls":
            finish = "tool_use"
    return {
        "id": openai_body.get("id", msg_id),
        "type": "message",
        "role": "assistant",
        "model": openai_body.get("model", ""),
        "content": content,
        "stop_reason": finish,
        "stop_sequence": None,
        "usage": {
            "input_tokens": usage.get("prompt_tokens", 0),
            "output_tokens": usage.get("completion_tokens", 0),
        },
    }


app = FastAPI()
state = {"upstream": "", "upstream_key": "", "upstream_model": ""}
http_client = None


@app.on_event("startup")
async def on_startup():
    global http_client
    verify = not state.get("skip_tls_verify", False)
    http_client = httpx.AsyncClient(timeout=httpx.Timeout(300.0, connect=30.0, pool=None), trust_env=False, verify=verify, limits=httpx.Limits(max_connections=10, max_keepalive_connections=2))


# 当 upstream URL 用 IP 代替了域名（DNS 预解析后），ssl 握手的 SNI 仍要用域名
# 否则服务端证书验证失败: certificate is not valid for IP
# httpx 0.27+ 支持在 request 的 extensions 里指定 sni_hostname
_SNI_KEY = "sni_hostname"


def _inject_sni(headers: dict, host: str) -> dict:
    """添加 Host header（IP 直连场景下保 SNI/路由）。"""
    if host:
        headers["Host"] = host
    return headers


# ========== Windows 侧 curl.exe 转发（WSL 网络受限场景） ==========
# WSL2 网络栈与 Windows 分离，VPN 在 Windows 上分配的 IP 路由在 WSL 看不到。
# 让 curl.exe（Windows 子系统）转发 HTTP 请求，由 Windows 走 VPN 网络栈。
# curl.exe 的 -k 跳过 cert verify（IP 直连场景下证书主体不匹配 IP），配合 --resolve 解决 SNI

async def _post_via_win_curl(url: str, headers: dict, body: dict, host_header: str) -> tuple:
    """通过 Windows 侧 curl.exe 发起 POST 请求，返回 (status, text)。

    关键设计：body 通过 stdin pipe 喂给 curl.exe（不是 argv），避免 ARG_MAX 128KB 限制
    （Claude 实际请求可达几百 KB，含 tools / system prompt / skills）。
    """
    import asyncio

    cmd = ["curl.exe", "-s", "-k", "--max-time", "300", "-X", "POST", url]
    for hk, hv in headers.items():
        cmd += ["-H", f"{hk}: {hv}"]
    if host_header:
        # curl.exe 没有 --resolve，但 -H "Host:" 保上游路由
        cmd += ["-H", f"Host: {host_header}"]
    cmd += ["-d", "@-", "-w", "\n__HTTP_STATUS__:%{http_code}"]

    body_bytes = json.dumps(body, ensure_ascii=False).encode("utf-8")
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate(input=body_bytes)
        text = stdout.decode("utf-8", errors="replace")
        # 解析 status (最后一行 __HTTP_STATUS__:xxx)
        status = 0
        if "__HTTP_STATUS__:" in text:
            parts = text.rsplit("__HTTP_STATUS__:", 1)
            text = parts[0].rstrip("\n")
            try:
                status = int(parts[1].strip())
            except ValueError:
                status = 0
        return status, text
    except Exception as e:
        return 0, f"curl.exe failed: {e}"


async def _stream_via_win_curl(url: str, headers: dict, body: dict, host_header: str):
    """通过 Windows 侧 curl.exe 流式 POST，逐 chunk yield 原始文本。

    关键：body 通过 stdin pipe 喂（不是 argv），避免 ARG_MAX 限制。
    curl.exe -N 关闭缓冲，stdout 流式可读。
    """
    import asyncio

    cmd = ["curl.exe", "-s", "-k", "-N", "--max-time", "300", "-X", "POST", url]
    for hk, hv in headers.items():
        cmd += ["-H", f"{hk}: {hv}"]
    if host_header:
        cmd += ["-H", f"Host: {host_header}"]
    cmd += ["-d", "@-"]

    body_bytes = json.dumps(body, ensure_ascii=False).encode("utf-8")
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    # 喂 body 后关闭 stdin（curl.exe 收到 EOF 即开始 send）
    try:
        proc.stdin.write(body_bytes)
        await proc.stdin.drain()
        proc.stdin.close()
    except Exception:
        pass

    try:
        while True:
            chunk = await proc.stdout.read(4096)
            if not chunk:
                break
            yield chunk.decode("utf-8", errors="replace")
    finally:
        if proc.returncode is None:
            try:
                proc.kill()
            except Exception:
                pass
        await proc.wait()


@app.on_event("shutdown")
async def on_shutdown():
    global http_client
    if http_client:
        await http_client.aclose()


@app.post("/v1/messages")
async def messages(request: Request):
    body = await request.json()
    stream = bool(body.get("stream"))
    upstream_body = anthropic_to_openai_req(body, state["upstream_model"])

    headers = {
        "Authorization": f"Bearer {state['upstream_key']}",
        "Content-Type": "application/json",
    }
    upstream_base = state["upstream"].rstrip("/")
    if upstream_base.endswith("/v1"):
        target_url = upstream_base + "/chat/completions"
    else:
        target_url = upstream_base + "/v1/chat/completions"

    # 如果 upstream 用 IP 代替了域名，加 Host header 保 SNI 和路由
    host_header = state.get("upstream_host")
    extra_ext = {}
    if host_header:
        headers["Host"] = host_header
        # SSL 握手时 SNI 用域名（让服务端证书验证通过）
        extra_ext["sni_hostname"] = host_header

    client = http_client
    use_win_curl = state.get("use_win_curl", False)

    if stream:
        sse_state = {"started": False, "block_open": False, "finished": False}

        async def gen():
            try:
                if use_win_curl:
                    async for chunk in _stream_via_win_curl(target_url, headers, upstream_body, host_header):
                        sse_out = openai_chunk_to_anthropic_sse(chunk, "msg_bridge", state["upstream_model"], sse_state)
                        if sse_out:
                            yield sse_out
                else:
                    async with client.stream(
                        "POST",
                        target_url,
                        headers=headers,
                        json=upstream_body,
                        extensions=extra_ext or None,
                    ) as r:
                        async for chunk in r.aiter_text():
                            sse_out = openai_chunk_to_anthropic_sse(chunk, "msg_bridge", state["upstream_model"], sse_state)
                            if sse_out:
                                yield sse_out
            except Exception as exc:
                from traceback import format_exc
                print(f"[bridge tail] stream error: {exc}", flush=True)
                print(format_exc(), flush=True)
                yield ('event: message_delta\n'
                       'data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null}}\n\n')
                yield 'event: message_stop\ndata: {"type":"message_stop"}\n\n'
        return StreamingResponse(gen(), media_type="text/event-stream")
    else:
        if use_win_curl:
            r_status, r_text = await _post_via_win_curl(target_url, headers, upstream_body, host_header)
            if r_status >= 400:
                return JSONResponse({"error": "upstream error", "body": r_text[:500]}, status_code=r_status)
            try:
                openai_json = json.loads(r_text)
            except Exception:
                return JSONResponse({"error": "upstream non-json", "body": r_text[:500]}, status_code=502)
            anth = openai_to_anthropic_resp(openai_json)
            return JSONResponse(anth)
        r = await client.post(
            target_url,
            headers=headers,
            json=upstream_body,
            extensions=extra_ext or None,
        )
        try:
            openai_json = r.json()
        except Exception:
            return JSONResponse({"error": "upstream non-json", "body": r.text[:500]}, status_code=502)
        anth = openai_to_anthropic_resp(openai_json)
        return JSONResponse(anth)


@app.post("/admin/reload")
async def reload(request: Request):
    data = await request.json()
    if "upstream" in data:
        state["upstream"] = data["upstream"]
    if "upstream_key" in data:
        state["upstream_key"] = data["upstream_key"]
    if "upstream_model" in data:
        state["upstream_model"] = data["upstream_model"]
    if "upstream_host" in data:
        state["upstream_host"] = data["upstream_host"]
    return {"ok": True, "state": dict(state)}


@app.get("/health")
async def health():
    return {"status": "ok", **state}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8895)
    parser.add_argument("--upstream", default=os.environ.get("OPENAI_BRIDGE_UPSTREAM", ""))
    parser.add_argument("--upstream-key", default=os.environ.get("OPENAI_BRIDGE_KEY", ""))
    parser.add_argument("--upstream-model", default=os.environ.get("OPENAI_BRIDGE_MODEL", ""))
    parser.add_argument("--upstream-host", default=os.environ.get("OPENAI_BRIDGE_HOST", ""))
    parser.add_argument("--use-win-curl", action="store_true",
                        default=os.environ.get("OPENAI_BRIDGE_USE_WIN_CURL", "").lower() in ("1", "true", "yes"),
                        help="通过 Windows 侧 curl.exe 转发请求（WSL 网络受限场景）")
    parser.add_argument("--skip-tls-verify", action="store_true",
                        default=os.environ.get("OPENAI_BRIDGE_SKIP_TLS_VERIFY", "").lower() in ("1", "true", "yes"),
                        help="跳过 upstream TLS 证书验证（SSH 隧道场景，hostname 是 127.0.0.1 但证书签给域名）")
    args = parser.parse_args()

    if not args.upstream:
        cfg = load_upstream_config()
        args.upstream = cfg.get("upstream", "")
        args.upstream_key = cfg.get("upstream_key", "")
        args.upstream_model = cfg.get("upstream_model", "")

    state["upstream"] = args.upstream
    state["upstream_key"] = args.upstream_key
    state["upstream_model"] = args.upstream_model
    state["upstream_host"] = args.upstream_host or ""
    state["use_win_curl"] = args.use_win_curl
    # 原始 upstream URL（IP 预解析前的），便于 ensure_bridge 字符串匹配
    state["upstream_original"] = os.environ.get("OPENAI_BRIDGE_UPSTREAM_ORIGINAL", args.upstream)
    state["skip_tls_verify"] = args.skip_tls_verify

    print(f"[openai-bridge] upstream={args.upstream} model={args.upstream_model} host_header={args.upstream_host or '(none)'} win_curl={args.use_win_curl} skip_tls_verify={args.skip_tls_verify}", flush=True)
    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()

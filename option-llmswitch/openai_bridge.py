#!/usr/bin/env python3
"""option-llmswitch OpenAI bridge — Anthropic Messages API → OpenAI Chat Completions.

当目标 provider 只支持 OpenAI 格式（如国航 AI+ 网关 deepseek-v4-flash），
让 Claude Code 通过本 bridge 间接调用。

Usage:
    python3 openai_bridge.py --listen-port 8898 --upstream https://upstream/v1 \\
        --upstream-key sk-xxx --upstream-model deepseek-v4-flash
"""
import argparse
import json
import os
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
                    # OpenAI image_url form
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
                    # 合并进下一条 message 用 role=tool
                    tool_id = blk.get("tool_use_id", "")
                    out = blk.get("content")
                    if isinstance(out, list):
                        out = next((b.get("text", "") for b in out if isinstance(b, dict) and b.get("type") == "text"), "")
                    messages.append({"role": "tool", "tool_call_id": tool_id, "content": out or ""})
                elif t in ("thinking", "redacted_thinking"):
                    # OpenAI 没有 thinking content，跳过（deepseek 也已拿到 reasoning_content）
                    continue
            if text_parts or tool_calls:
                m = {"role": role, "content": "".join(p for p in text_parts if isinstance(p, str)) or None}
                if tool_calls:
                    m["tool_calls"] = tool_calls
                messages.append(m)

    openai_body = {
        "model": target_model,
        "messages": messages,
        "stream": bool(anth_body.get("stream")),
        "max_tokens": anth_body.get("max_tokens", 4096),
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


def openai_chunk_to_anthropic_sse(chunk_text: str, msg_id: str, model: str, state=None):
    """OpenAI stream chunk (可能含多行 data:...) → Anthropic SSE 事件集。

    state: dict 跟踪 message_start/content_block_start 是否已发出。"""
    if state is None:
        state = {"started": False, "block_open": False, "finished": False}
    if not chunk_text:
        return None

    out = []
    for line in chunk_text.split("\n"):
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[len("data:"):].strip()
        if not payload:
            continue
        if payload == "[DONE]":
            if state["finished"]:
                continue
            if state["block_open"]:
                out.append('event: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\n')
                state["block_open"] = False
            stop_delta = {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None}}
            out.append(f"event: message_delta\ndata: {json.dumps(stop_delta, separators=(',', ':'))}\n\n")
            out.append('event: message_stop\ndata: {"type":"message_stop"}\n\n')
            state["finished"] = True
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

        if not state["started"]:
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

        for choice in obj.get("choices", []):
            delta = choice.get("delta", {})
            content = delta.get("content")
            if content:
                if not state["block_open"]:
                    out.append(
                        'event: content_block_start\n'
                        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
                    )
                    state["block_open"] = True
                block_delta = {
                    "type": "content_block_delta",
                    "index": 0,
                    "delta": {"type": "text_delta", "text": content},
                }
                out.append(f"event: content_block_delta\ndata: {json.dumps(block_delta, separators=(',', ':'))}\n\n")
            if choice.get("finish_reason"):
                if state["block_open"]:
                    out.append('event: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\n')
                    state["block_open"] = False
                stop_delta = {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None}}
                out.append(f"event: message_delta\ndata: {json.dumps(stop_delta, separators=(',', ':'))}\n\n")

        usage = obj.get("usage")
        if usage:
            msg_delta_usage = {"type": "message_delta", "usage": {"output_tokens": usage.get("completion_tokens", 0)}}
            out.append(f"event: message_delta\ndata: {json.dumps(msg_delta_usage, separators=(',', ':'))}\n\n")

    return "".join(out) if out else None


def openai_to_anthropic_resp(openai_body: dict, msg_id: str = "msg_bridge") -> dict:
    """非流式：OpenAI Chat Completions response → Anthropic message。"""
    choices = openai_body.get("choices", [])
    text_parts = []
    for ch in choices:
        msg = ch.get("message", {})
        content = msg.get("content")
        if isinstance(content, str):
            text_parts.append({"type": "text", "text": content})
    usage = openai_body.get("usage", {})
    return {
        "id": openai_body.get("id", msg_id),
        "type": "message",
        "role": "assistant",
        "model": openai_body.get("model", ""),
        "content": text_parts,
        "stop_reason": "end_turn" if choices and choices[0].get("finish_reason") == "stop" else None,
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
    http_client = httpx.AsyncClient(timeout=httpx.Timeout(300.0, connect=10.0))


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

    client = http_client
    if stream:
        sse_state = {"started": False, "block_open": False, "finished": False}

        async def gen():
            async with client.stream("POST", target_url, headers=headers, json=upstream_body) as r:
                async for chunk in r.aiter_text():
                    sse_out = openai_chunk_to_anthropic_sse(chunk, "msg_bridge", state["upstream_model"], sse_state)
                    if sse_out:
                        yield sse_out
        return StreamingResponse(gen(), media_type="text/event-stream")
    else:
        r = await client.post(target_url, headers=headers, json=upstream_body)
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
    return {"ok": True, "state": dict(state)}


@app.get("/health")
async def health():
    return {"status": "ok", **state}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8898)
    parser.add_argument("--upstream", default=os.environ.get("OPENAI_BRIDGE_UPSTREAM", ""))
    parser.add_argument("--upstream-key", default=os.environ.get("OPENAI_BRIDGE_KEY", ""))
    parser.add_argument("--upstream-model", default=os.environ.get("OPENAI_BRIDGE_MODEL", ""))
    args = parser.parse_args()

    if not args.upstream:
        cfg = load_upstream_config()
        args.upstream = cfg.get("upstream", "")
        args.upstream_key = cfg.get("upstream_key", "")
        args.upstream_model = cfg.get("upstream_model", "")

    state["upstream"] = args.upstream
    state["upstream_key"] = args.upstream_key
    state["upstream_model"] = args.upstream_model

    print(f"[openai-bridge] upstream={args.upstream} model={args.upstream_model}", flush=True)
    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()

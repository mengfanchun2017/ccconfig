#!/usr/bin/env python3
"""option-llmswitch OpenAI bridge — Anthropic Messages API → OpenAI Chat Completions.

当目标 provider 只支持 OpenAI 格式（如国航 AI+ 网关 deepseek-v4-flash），
让 Claude Code 通过本 bridge 间接调用。

Usage:
    python3 openai_bridge.py --listen-port 8898 --upstream https://upstream/v1 \
        --upstream-key sk-xxx --upstream-model deepseek-v4-flash
"""
import argparse
import asyncio
import codecs
import json
import os
import re
import socket
import time
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

    # effort 透传：Claude Code 的 CLAUDE_EFFORT / modelSettings.effortLevel → Anth output_config
    # → OpenAI reasoning_effort。缺了它，bridge 侧收不到 high effort 指令，上游用默认档，
    # 表现"模型变傻"。映射三档（OpenAI 只认 low/medium/high）
    oc = anth_body.get("output_config") or {}
    if oc.get("effort") in ("low", "medium", "high"):
        openai_body["reasoning_effort"] = oc["effort"]

    # thinking 透传：Claude Code 在 Anth 协议里用 thinking: {type:"enabled", budget_tokens:N}
    # 启用 extended thinking。bridge 没把这条翻译给上游 → upstream 走默认档/不思考，
    # 表现"思考深度变浅 / 跳过思考"。OpenAI 系用 reasoning_effort 三档，
    # 按 budget_tokens 离散映射（缺省=高，<8k=低，<20k=中，>=20k=高）。
    # 优先级低于 output_config.effort：后者是用户显式设定，应保留。
    if "reasoning_effort" not in openai_body:
        th = anth_body.get("thinking") or {}
        if th.get("type") == "enabled":
            budget = th.get("budget_tokens")
            if budget is None:
                openai_body["reasoning_effort"] = "high"
            elif budget < 8000:
                openai_body["reasoning_effort"] = "low"
            elif budget < 20000:
                openai_body["reasoning_effort"] = "medium"
            else:
                openai_body["reasoning_effort"] = "high"

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
    """OpenAI stream chunk (可能含多行 data:...) → Anthropic SSE 事件集。"""
    if state is None:
        state = {"started": False, "finished": False, "block_idx": 0}
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
            if state.get("stopped"):
                continue
            if not state.get("finished"):
                _close_text_block(state, out, 0)
                _close_tool_blocks(state, out)
            anth_reason = state.get("stop_reason") or "end_turn"
            # why: 把 usage 并进收尾 delta 一起发——上游（DeepSeek 系）每个 chunk
            #      都带 usage，逐个转 message_delta 会放大成与 token 数相当的冗余事件流，
            #      CC 在慢速上游下易把海量 usage delta 当异常/超时，触发自动重试
            #      （表现"输出一半回退重新输出"）。只在 [DONE] 发一次，携带最新累计值。
            stop_delta = {"type": "message_delta", "delta": {"stop_reason": anth_reason, "stop_sequence": None, "stop_details": {"type": "stop", "reason": anth_reason}}}
            if state.get("output_tokens"):
                stop_delta["usage"] = {"output_tokens": state["output_tokens"]}
            out.append(f"event: message_delta\ndata: {json.dumps(stop_delta, separators=(',', ':'))}\n\n")
            out.append('event: message_stop\ndata: {"type":"message_stop"}\n\n')
            state["finished"] = True
            state["stopped"] = True
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

            _fr = choice.get("finish_reason")
            if _fr:
                _close_text_block(state, out, 0)
                _close_tool_blocks(state, out)
                _fr_map = {"stop": "end_turn", "tool_calls": "tool_use", "length": "max_tokens", "content_filter": "content_filtered"}
                # why: 不在此处发 message_delta —— 上游（DeepSeek 系）带 finish_reason 的
                #      chunk 后面还跟着 usage-only chunk，那个 delta 的 stop_reason 是 None，
                #      会把真实 stop_reason（max_tokens/tool_use）覆盖成 null/end_turn，
                #      导致 CC 收到被截断的输出时误判正常结束、不自动续写。
                #      记下来，等 [DONE] 时作为流内最后一个 message_delta 发出。
                state["stop_reason"] = _fr_map.get(_fr, "end_turn")
                state["finished"] = True

        usage = obj.get("usage")
        if usage:
            # 只在 state 记累计值，不再逐 chunk 发 message_delta：
            # 上游（DeepSeek 系）每个 chunk 都带 usage，逐个转 message_delta 会
            # 放大成与 token 数相当的冗余事件流（实测 200 字响应 302 事件里 154 个
            # 是 usage-only delta）。慢速上游 + 海量冗余事件，CC 易把慢/异常当超时，
            # 触发自动重试 → 表现"输出一半回退重输出"。最终 usage 合并进 [DONE] 的
            # message_delta 一次发完。
            state["output_tokens"] = usage.get("completion_tokens", 0)

    return "".join(out) if out else None


async def _iter_complete_lines(stream_iter):
    """把任意字节边界的分片重组为完整行后再向下游吐。

    why: curl.exe stdout / httpx aiter_text 的分片边界是随机的（实测长流每次有
    15-29 个切点落在行中间）。被切开的行不以 `data:` 开头 → openai_chunk_to_anthropic_sse
    整行 continue 丢弃：丢 usage 事小，切中 `data: [DONE]` 就把终止标记丢了 →
    误报 upstream_incomplete；切中正文行则内容静默缺失。
    行缓冲保证只有完整行才进解析器，不再依赖分片边界恰好落在换行上。
    """
    buf = ""
    async for chunk in stream_iter:
        if not chunk:
            continue
        buf += chunk
        start = 0
        while True:
            nl = buf.find("\n", start)
            if nl < 0:
                break
            yield buf[start:nl + 1]
            start = nl + 1
        buf = buf[start:]
        # 上游永不发换行（非 SSE 响应体）时不能无限攒内存
        if len(buf) > 1_048_576:
            yield buf
            buf = ""
    if buf:
        yield buf


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
    # write=120s: tailscale TCP 透传 + 内网 LLM 慢链路下大请求 (tool_use/长 prompt) 易撞 60s
    # retries=2: WriteTimeout/ConnectError 自动重试, 偶尔抖一下不致命
    # keepalive_expiry=10s: tailscale serve 端空闲可能 < 5s, 主动短一点避免撞对端 idle close
    limits = httpx.Limits(max_keepalive_connections=20, keepalive_expiry=10.0)
    # why: httpx 一旦传入自定义 transport，AsyncClient(verify=/limits=/trust_env=) 会被
    # 静默忽略 —— 必须把这些参数交给 transport 本身，否则 --skip-tls-verify 形同虚设
    transport = httpx.AsyncHTTPTransport(
        retries=2, verify=verify, limits=limits, trust_env=False,
    )
    http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(300.0, connect=30.0, read=180.0, write=120.0, pool=30.0),
        transport=transport,
    )


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


class _WinCurlUpstreamError(Exception):
    """curl.exe 退出码非 0 时带 stderr 文本抛出，让 caller 归因 upstream_error 而非 misleading 的 'stream interrupted'。"""
    def __init__(self, returncode: int, stderr_text: str):
        self.returncode = returncode
        self.stderr_text = stderr_text
        super().__init__(f"curl.exe exit {returncode}: {stderr_text[:200]}")


async def _post_via_win_curl(url: str, headers: dict, body: dict, host_header: str) -> tuple:
    """通过 Windows 侧 curl.exe 发起 POST 请求，返回 (status, text)。

    关键设计：body 通过 stdin pipe 喂给 curl.exe（不是 argv），避免 ARG_MAX 128KB 限制
    （Claude 实际请求可达几百 KB，含 tools / system prompt / skills）。
    """
    import asyncio

    # why -sS：-s silent（不打印进度），-S 强制显示错误。
    # 单 -s 时 curl 连接超时/证书错误/DNS 失败的 stderr 全被吞掉，stdout 空 → 上层
    # 误把"网络问题"归因为 upstream non-json body=""。stream 路径已用 -sS（0919 修），
    # 非流式路径同样覆盖。
    cmd = ["curl.exe", "-sS", "-k", "--connect-timeout", "15", "--max-time", "300", "-X", "POST", url]
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
        stderr_text = stderr.decode("utf-8", errors="replace").strip()
        # curl 退出码非 0 时 stdout 通常空 + status=0（__HTTP_STATUS__ 没机会打印），
        # 把 stderr 透传给上层，归因 upstream_error 而不是 misleading 的 upstream non-json body=""
        if proc.returncode != 0:
            return 0, f"curl.exe exit {proc.returncode}: {stderr_text[:500]}"
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

    # --connect-timeout：连不上就快报错（默认无限制会一直挂着）
    # --max-time 1800：长任务（整篇文档生成）常超 5 分钟，300s 会把正常流掐断成
    #                  "no [DONE]" → 误报 upstream_incomplete
    cmd = ["curl.exe", "-sS", "-k", "-N", "--connect-timeout", "15", "--max-time", "1800", "-X", "POST", url]
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

    # 增量解码：分片可能切在多字节 UTF-8 序列中间，逐片 decode(errors="replace")
    # 会把残字节变成 U+FFFD —— 中文每字 3 字节，4096 边界切中概率高，正文必现乱码
    dec = codecs.getincrementaldecoder("utf-8")("replace")
    try:
        while True:
            chunk = await proc.stdout.read(4096)
            if not chunk:
                break
            text = dec.decode(chunk)
            if text:
                yield text
        tail = dec.decode(b"", True)
        if tail:
            yield tail
    finally:
        if proc.returncode is None:
            try:
                proc.kill()
            except Exception:
                pass
        await proc.wait()
        # 一次性 drain stderr —— curl.exe 连不上/证书错时 stdout 空、stderr 有诊断信息
        # 不读就丢了，退出码非 0 时把 stderr 文本通过异常带出，让 caller 归因
        # upstream_error 而不是 misleading 的 upstream_incomplete（"流被截断"）。
        # why 不用并发 task：实测并发 drain 在 stdout 立即 EOF 场景下读不到 stderr
        # （被 cancel 时 buf 累积空），proc.wait 后直接 read 剩余 PIPE 数据更稳。
        stderr_data = b""
        try:
            stderr_data = await asyncio.wait_for(proc.stderr.read(), timeout=2)
        except (asyncio.TimeoutError, Exception):
            pass
        if proc.returncode not in (0, None):
            stderr_text = stderr_data.decode("utf-8", errors="replace").strip() if stderr_data else ""
            raise _WinCurlUpstreamError(proc.returncode, stderr_text)


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
    # URL 已含版本段（/v1, /v4, /paas/v4, /openai/v1 等）或完整路径 → 只追加 /chat/completions
    # why: 之前只检测 /v1，遇到智谱 paas/v4 类非标准路径会拼成 /v4/v1/chat/completions → 404
    if re.search(r"/v\d+(/|$)", upstream_base) or "/chat/completions" in upstream_base:
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

        async def _iter_with_idle_ping(stream_iter, idle=15.0):
            """upstream 静默 idle 秒后注入 SSE 注释心跳（`:` 开头，Anthropic SDK 忽略）。

            why: agent 等 tool call 时 upstream 可能 30-60s 不发 token，撞 tailscale 75s /
            AWS ALB 60s / Cloudflare 100s idle cap 会被中间设备断流。

            why queue+pump task：绝不能对 anext() 套 asyncio.wait_for —— 超时 cancel 会把
            async generator 直接弄死（剩余 chunk 全丢），且迭代结束的 StopAsyncIteration
            从 async generator 内冒出会被 CPython 转成 RuntimeError 掐断整条流。
            """
            q: asyncio.Queue = asyncio.Queue()
            _DONE = object()

            async def _pump():
                try:
                    async for chunk in stream_iter:
                        await q.put(chunk)
                except BaseException as e:  # 原样转交调用方（httpx.TransportError 等）
                    await q.put(e)
                finally:
                    await q.put(_DONE)

            pump = asyncio.create_task(_pump())
            try:
                while True:
                    try:
                        item = await asyncio.wait_for(q.get(), timeout=idle)
                    except asyncio.TimeoutError:
                        yield ": ping\n\n"
                        continue
                    if item is _DONE:
                        return
                    if isinstance(item, BaseException):
                        raise item
                    yield item
            finally:
                pump.cancel()

        def _error_frames(kind: str, msg: str) -> str:
            # 用 json.dumps 而非 % 拼接：msg 可能来自上游错误原文，含引号/反斜杠时
            # 直接插值会产出非法 JSON 帧，客户端解析失败就只剩"流断了"
            payload = json.dumps(
                {"type": "error", "error": {"type": kind, "message": msg}},
                ensure_ascii=False,
                separators=(",", ":"),
            )
            return f"event: error\ndata: {payload}\n\n" + 'event: message_stop\ndata: {"type":"message_stop"}\n\n'

        # 留一份原始响应头段，用于区分"真截断"和"上游回的根本不是 SSE"
        raw_buf = [""]

        def _render(chunk: str):
            # SSE 注释（idle 心跳，`:` 开头）必须原样透传：喂给
            # openai_chunk_to_anthropic_sse 会因不以 data: 开头被丢掉，
            # 心跳等于没发，tailscale 75s idle 断流照样发生
            if chunk.startswith(":"):
                return chunk
            if len(raw_buf[0]) < 4096:
                raw_buf[0] += chunk
            return openai_chunk_to_anthropic_sse(chunk, "msg_bridge", state["upstream_model"], sse_state)

        async def gen():
            # 捕获 upstream 间歇性超时/断连：log + 结束 stream，不让异常杀进程
            # Claude Code 收到不完整响应会自动重试，比 bridge 整个死掉强
            try:
                if use_win_curl:
                    src = _stream_via_win_curl(target_url, headers, upstream_body, host_header)
                    async for chunk in _iter_with_idle_ping(_iter_complete_lines(src)):
                        sse_out = _render(chunk)
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
                        async for chunk in _iter_with_idle_ping(_iter_complete_lines(r.aiter_text())):
                            sse_out = _render(chunk)
                            if sse_out:
                                yield sse_out
            except Exception as e:
                # why Exception 而非 httpx.TransportError：win_curl 路径抛的是
                # OSError/ConnectionResetError 之类，漏掉会让异常直接逃出 gen() ——
                # 客户端既拿不到 error 事件也等不到 message_stop，表现为永久卡死
                print(f"[bridge] upstream stream error: {type(e).__name__}: {e}", flush=True)
                # yield SSE error event 让 Claude Code 立刻看到错误（不等 4 分钟）
                sse_state["finished"] = True
                # 区分"curl.exe 启动失败/连不上"（stderr 有诊断信息）和"中途断连"：
                # 前者归因 upstream_error 带 stderr 原文，后者归因 upstream_disconnected
                if isinstance(e, _WinCurlUpstreamError):
                    yield _error_frames("upstream_error", e.stderr_text[:500])
                else:
                    yield _error_frames("upstream_disconnected", "stream interrupted")
                return
            # upstream 结束却没给终止标记（截断 / 空响应）→ 显式报错
            # why: 否则客户端只拿到半条流且无从判断，探测也只能靠"缺少 message_stop"
            #      间接推断；显式 error 让两边都能确定地识别失败
            if not sse_state.get("finished"):
                if "data:" not in raw_buf[0] and raw_buf[0].strip():
                    # 一整个 data: 行都没出现过 → upstream 回的不是 SSE。
                    # one-api 类网关对"模型无可用渠道/额度不足"就是 HTTP 200 + 裸 JSON
                    # error，报 upstream_incomplete 会把人引向查网络，其实是上游拒绝
                    detail = raw_buf[0].strip()[:500]
                    print(f"[bridge] upstream returned non-SSE body: {detail}", flush=True)
                    yield _error_frames("upstream_error", detail)
                else:
                    print("[bridge] upstream stream ended without [DONE] (truncated or empty)", flush=True)
                    yield _error_frames("upstream_incomplete", "upstream stream ended without completion marker")
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
            # 网关 HTTP 200 + {"error":...} 拒绝（无可用渠道/额度不足）时，
            # openai_to_anthropic_resp 会产出空消息，表现为"模型不说话"而非报错
            if isinstance(openai_json, dict) and "error" in openai_json:
                return JSONResponse({"error": "upstream_error", "body": r_text[:500]}, status_code=502)
            anth = openai_to_anthropic_resp(openai_json)
            return JSONResponse(anth)
        try:
            r = await client.post(
                target_url,
                headers=headers,
                json=upstream_body,
                extensions=extra_ext or None,
            )
        except httpx.TransportError as e:
            print(f"[bridge] upstream post error: {type(e).__name__}: {e}", flush=True)
            return JSONResponse({"error": "upstream timeout", "type": type(e).__name__}, status_code=529)
        try:
            openai_json = r.json()
        except Exception:
            return JSONResponse({"error": "upstream non-json", "body": r.text[:500]}, status_code=502)
        if isinstance(openai_json, dict) and "error" in openai_json:
            return JSONResponse({"error": "upstream_error", "body": r.text[:500]}, status_code=502)
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
    # 不回 upstream_key 明文（旧版直接 **state 把 API key 吐给任何能访问端口的人）
    return {
        "status": "ok",
        "upstream": state.get("upstream", ""),
        "upstream_model": state.get("upstream_model", ""),
        "upstream_host": state.get("upstream_host", ""),
        "upstream_original": state.get("upstream_original", ""),
        "upstream_key_set": bool(state.get("upstream_key")),
        "use_win_curl": state.get("use_win_curl", False),
        "skip_tls_verify": state.get("skip_tls_verify", False),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8898)
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

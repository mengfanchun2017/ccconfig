#!/usr/bin/env python3
"""option-llmswitch OpenAI bridge — Anthropic Messages API → OpenAI Chat Completions.

当目标 provider 只支持 OpenAI 格式（如内网 LLM 网关的 deepseek-v4-flash），
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
import time
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

CCCONFIG = Path(os.environ.get("CCCONFIG_HOME", Path.home() / "git" / "ccconfig"))

# 原始上游流存档目录（可选）。设了就把每个请求的上游原始 chunk 落盘，
# 下次出现"重复块/丢块"直接看存档，不用重跑现场
DUMP_DIR = os.environ.get("OPENAI_BRIDGE_DUMP", "")
# 单调递增请求号：给 message id 用（旧版所有响应 id 都是常量 "msg_bridge"，
# 客户端把两条独立响应看成同一条消息时无法区分）
_REQ_SEQ = [0]


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


def _is_websearch_tool(t) -> bool:
    """Anthropic 服务端搜索工具判定（type 以 web_search_ 开头，如 web_search_20250305）。

    与客户端工具（带 input_schema、由模型 tool_use 触发）不同，服务端工具由上游
    自己执行搜索。OpenAI-only 上游不支持，必须剔除，否则当 function 发过去 400。
    """
    return isinstance(t, dict) and str(t.get("type", "")).startswith("web_search_")


# OpenAI finish_reason → Anthropic stop_reason。**唯一来源**：流式与非流式共用，
# 旧版把这张表在流式/非流式各写一遍，改一处必漂移。
# 上游（one-api 类网关 + 各家模型）会发非标准值，必须显式覆盖：一律回落 end_turn
# 会把「输出被截断」误报成「正常结束」，CC 不再自动续写（表现为回答半截就停）。
_FINISH_REASON_MAP = {
    "stop": "end_turn",
    "eos": "end_turn",           # vLLM / 部分国内网关
    "abort": "end_turn",
    "tool_calls": "tool_use",
    "tool_call": "tool_use",     # 单数形
    "function_call": "tool_use",  # 旧 OpenAI 形
    "length": "max_tokens",
    "max_tokens": "max_tokens",
    "content_filter": "content_filtered",
    "stop_sequence": "stop_sequence",
}


def _map_finish_reason(fr):
    """映射 stop_reason；未知非空值打告警，便于发现上游新形态。"""
    if not fr:
        return None
    mapped = _FINISH_REASON_MAP.get(fr)
    if mapped is None:
        print(f"[bridge] WARN unknown finish_reason={fr!r} → 按 end_turn 处理", flush=True)
        return "end_turn"
    return mapped


def _image_part(blk: dict):
    """Anthropic 图片块 → OpenAI image_url 段；无等价物（file 引用）返回 None。

    两处调用（消息顶层、tool_result 内层）共用，避免 URL/base64 的构造逻辑各写一遍。
    """
    if blk.get("type") == "image_url":
        return blk if blk.get("image_url") else None
    src = blk.get("source", {}) or {}
    st = src.get("type")
    if st == "base64" and src.get("data"):
        return {
            "type": "image_url",
            "image_url": {"url": f"data:{src.get('media_type')};base64,{src.get('data')}"},
        }
    if st == "url" and src.get("url"):
        # Anthropic 也支持 url 型图片源，旧版只认 base64 → url 图整块丢弃
        return {"type": "image_url", "image_url": {"url": src["url"]}}
    # st == "file"（Files API 引用）无 OpenAI 等价物，只能丢
    return None


def anthropic_to_openai_req(anth_body: dict, target_model: str) -> dict:
    """Anthropic Messages API body → OpenAI Chat Completions body.

    服务端搜索工具（web_search_20250305）剔除——上游不支持，当普通 function
    发过去会被 400，转成假 function 会让模型反复空转。
    """
    messages = []
    system_blocks = anth_body.get("system")
    sys_texts = []
    if isinstance(system_blocks, list):
        for blk in system_blocks:
            if isinstance(blk, dict) and blk.get("type") == "text":
                sys_texts.append(blk.get("text", ""))
            elif isinstance(blk, str):
                sys_texts.append(blk)
    elif isinstance(system_blocks, str):
        sys_texts.append(system_blocks)
    # 多段 system 必须合并成一条：多数 chat template 只认第一条 system 消息，
    # 逐段发会让第二段之后的指令在上游静默失效（旧版行为）
    if sys_texts:
        messages.append({"role": "system", "content": "\n\n".join(sys_texts)})

    for msg in anth_body.get("messages", []):
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue
        content = msg.get("content")
        if isinstance(content, str):
            messages.append({"role": role, "content": content})
        elif isinstance(content, list):
            text_parts = []
            content_parts = []  # OpenAI content 数组：text 段 + image_url 段混排
            tool_calls = []
            hoisted_images = []  # tool_result 里的图片，见下方 tool_result 分支说明
            produced = 0  # 本条 Anthropic 消息已产出几条 OpenAI 消息（tool_result 即时 append）
            for blk in content:
                if not isinstance(blk, dict):
                    continue
                t = blk.get("type")
                if t == "text":
                    text_parts.append(blk.get("text", ""))
                elif t == "image" or t == "image_url":
                    part = _image_part(blk)
                    if part:
                        content_parts.append(part)
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
                    out_content = blk.get("content")
                    if isinstance(out_content, list):
                        # 旧版 next(...) 只取第一个 text 块，其余内容静默丢失
                        segs = []
                        for b in out_content:
                            if not isinstance(b, dict):
                                continue
                            if b.get("type") == "text":
                                segs.append(b.get("text", ""))
                            elif b.get("type") in ("image", "image_url"):
                                # OpenAI 的 role=tool 只吃字符串 content，塞数组会被上游当
                                # 无参数调用处理 → 模型看不到图，还会空转到 max_tokens。
                                # 只能先占位，把图挂到紧随其后的 user 消息上（见下方 hoisted）。
                                segs.append("[image]")
                                part = _image_part(b)
                                if part:
                                    hoisted_images.append(part)
                        out_content = "\n".join(segs)
                    out_content = out_content if isinstance(out_content, str) else ("" if out_content is None else str(out_content))
                    # is_error 必须让模型看见：旧版丢弃后模型无法得知工具失败，
                    # 会把错误结果当正常结果继续推理
                    if blk.get("is_error"):
                        out_content = f"[tool_error] {out_content}"
                    messages.append({"role": "tool", "tool_call_id": tool_id, "content": out_content})
                    produced += 1
                elif t in ("thinking", "redacted_thinking"):
                    continue
            if text_parts or content_parts or tool_calls:
                text = "".join(text_parts)
                if content_parts:
                    # 有图片：content 必须走数组（str join 会把 image_url dict 静默丢掉）
                    segs = []
                    if text:
                        segs.append({"type": "text", "text": text})
                    segs.extend(content_parts)
                    m = {"role": role, "content": segs}
                else:
                    m = {"role": role, "content": text or None}
                if tool_calls:
                    m["tool_calls"] = tool_calls
                messages.append(m)
                produced += 1
            if hoisted_images:
                # tool_result 的图补挂到本条消息末尾：必须在 tool 消息之后，否则
                # 上游会因「tool 未被响应」直接 400
                segs = [{"type": "text", "text": "Tool result image:"}]
                segs.extend(hoisted_images)
                messages.append({"role": "user", "content": segs})
                produced += 1
            if produced == 0 and role == "user":
                # 用户消息的块全被丢弃（不支持的块类型）→ 补占位。旧版直接不 append，
                # 这一轮在上游消失，后续对话轮次错位
                messages.append({"role": "user", "content": "[unsupported content]"})

    max_tokens_val = anth_body.get("max_tokens")
    if not isinstance(max_tokens_val, int) or max_tokens_val <= 0:
        # Anthropic 的 max_tokens 是必填；显式 null / 非法值时 get(k, 默认) 不生效
        # （缺键才生效），把 null 原样传上游会被 400
        max_tokens_val = 4096
    streaming = bool(anth_body.get("stream"))
    openai_body = {
        "model": target_model,
        "messages": messages,
        "stream": streaming,
        "max_tokens": max_tokens_val,
    }
    if streaming:
        # 主动索取 usage：不设它，遵循 OpenAI 规范的上游可能整场不发 usage，
        # input_tokens 恒 0 → CC 的上下文余量与自动压缩全部失灵
        openai_body["stream_options"] = {"include_usage": True}
    for k in ("temperature", "top_p", "frequency_penalty", "presence_penalty", "n"):
        if k in anth_body:
            openai_body[k] = anth_body[k]
    # Anthropic 的停止序列叫 stop_sequences，OpenAI 叫 stop —— 字段名不同。
    # 旧版按 "stop" 取，于是客户端设的停止序列从来没有透传上游。
    if anth_body.get("stop_sequences"):
        openai_body["stop"] = anth_body["stop_sequences"]

    # thinking 开关透传：CC 用 Anth 的 thinking 字段请求思考（2.1.274 发
    # {"type":"adaptive","display":"omitted"}，老版本发 enabled + budget_tokens）。
    # 上游 OpenAI 协议里开关叫 enable_thinking（vLLM/SGLang 系 chat template 认这个）。
    # 实测单位网关：只发 reasoning_effort 时 reasoning_tokens 恒为 0（模型不思考，
    # 反而把思路当正文吐出来 → "我现在执行。发送！"式空转循环）；带上本开关才有
    # 真实 reasoning。深度另由下面的 reasoning_effort 控制。
    th = anth_body.get("thinking") or {}
    if th.get("type") in ("enabled", "adaptive"):
        openai_body["enable_thinking"] = True

    # effort 透传：Claude Code 的 effort 设定（/effort、CLAUDE_EFFORT）→ Anth output_config
    # → OpenAI reasoning_effort。缺了它上游用默认档，表现"模型变傻"。
    # 优先级高于 thinking 推导值：output_config 是用户显式设定。
    oc = anth_body.get("output_config") or {}
    if oc.get("effort") in ("low", "medium", "high"):
        openai_body["reasoning_effort"] = oc["effort"]

    # thinking 预算兜底：老 CC 只用 thinking.budget_tokens 表达思考深度，
    # 没有 output_config 时按预算离散映射（缺省=高，<8k=低，<20k=中，>=20k=高）。
    if "reasoning_effort" not in openai_body and th.get("type") == "enabled":
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
        out_tools = []
        for t in tools:
            if _is_websearch_tool(t):
                continue
            out_tools.append({
                "type": "function",
                "function": {
                    "name": t.get("name", ""),
                    "description": t.get("description", ""),
                    "parameters": t.get("input_schema", {"type": "object", "properties": {}}),
                },
            })
        if out_tools:
            openai_body["tools"] = out_tools
            tool_choice = anth_body.get("tool_choice")
            # tool_choice 只在剩余 tools 存在时发：全部被剔除（如只剩服务端搜索
            # 工具）时带 tool_choice 无 tools，上游直接 400
            if tool_choice:
                if tool_choice.get("type") == "tool":
                    openai_body["tool_choice"] = {"type": "function", "function": {"name": tool_choice.get("name", "")}}
                elif tool_choice.get("type") == "any":
                    # Anthropic "any"（强制至少调一个工具）= OpenAI "required"，
                    # 原样透传 "any" 上游 400
                    openai_body["tool_choice"] = "required"
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
                # 上游 usage 出现时机不定：单位网关实测首 chunk 只有 reasoning_content，
                # prompt_tokens 要到**倒数第二个** chunk（带 finish_reason 那个）才有。
                # 所以 message_start 通常拿不到真值，恒 0 会让 CC 以为输入是空的
                # （上下文余量、自动压缩全失灵）。真值由收尾 message_delta 补发，见下。
                "usage": {"input_tokens": state.get("input_tokens", 0), "output_tokens": 0},
            },
        }
        out.append(f"event: message_start\ndata: {json.dumps(msg_start, separators=(',', ':'))}\n\n")
        out.append('event: ping\ndata: {"type":"ping"}\n\n')


def _block_start(state, out, idx, payload: str, kind: str):
    """发 content_block_start，并检测「同一 index 二次开启」。

    why: CC 按 index 组装消息、按 index 收尾时执行工具。上游在收尾后重发同 index
    内容（网关重试/重复投递）会让 bridge 再发一次 start → CC 把该块重放一遍：
    界面"输出一段文字后回退再输出"，tool_use 则被**执行两次**（真实副作用翻倍）。
    正常流每个 index 只开一次，这里留显式告警，便于定位是不是上游违约。
    """
    if idx in state.setdefault("_closed_idx", set()):
        state["dup_blocks"] = state.get("dup_blocks", 0) + 1
        print(f"[bridge] WARN duplicate content_block_start index={idx} kind={kind}"
              f" (该 index 已关闭后又重开，上游违约)", flush=True)
    state.setdefault("_open_idx", set()).add(idx)
    kind_key = "text_blocks" if kind == "text" else "tool_blocks"
    state[kind_key] = state.get(kind_key, 0) + 1
    out.append(payload)


def _mark_closed(state, idx):
    state.setdefault("_open_idx", set()).discard(idx)
    state.setdefault("_closed_idx", set()).add(idx)


def _alloc_idx(state) -> int:
    """分配下一个 content block index。

    why: 文本块与工具块曾各自算 index（文本硬编码 0、工具从 block_idx=0 起），
    一条"先说话再调工具"的响应里两者都拿到 index 0 —— 同一个 index 在一个 message
    里出现两个 content_block_start，Anthropic 协议不允许。CC 收到后按 index 收尾，
    把已发出的正文块**重放/丢弃**，tool_use 于是被**执行两次**（真实副作用翻倍）。
    现在统一用单调递增计数器，文本块和工具块永不撞号。
    """
    idx = state.get("block_idx", 0)
    state["block_idx"] = idx + 1
    return idx


def _open_text_block(state, out) -> int:
    idx = _alloc_idx(state)
    state["text_idx"] = idx
    state["text_open"] = True
    _block_start(
        state, out, idx,
        f'event: content_block_start\ndata: {{"type":"content_block_start","index":{idx},"content_block":{{"type":"text","text":""}}}}\n\n',
        "text",
    )
    return idx


def _close_text_block(state, out):
    if state.get("text_open"):
        idx = state.get("text_idx", 0)
        out.append(f'event: content_block_stop\ndata: {{"type":"content_block_stop","index":{idx}}}\n\n')
        state["text_open"] = False
        _mark_closed(state, idx)


def _close_tool_blocks(state, out):
    # 只认 tool_*_open：文本块的开关叫 text_open，末尾同样是 "_open"，
    # 不限定前缀会被误当成工具块把 text_open 置 False（块没关就再也关不上）
    for key in list(state.keys()):
        if key.startswith("tool_") and key.endswith("_open") and state.get(key):
            tc_idx = key.replace("_open", "").replace("tool_", "", 1)
            tc_info = state.get(f"tool_{tc_idx}")
            if isinstance(tc_info, dict):
                out.append(f'event: content_block_stop\ndata: {{"type":"content_block_stop","index":{tc_info["index"]}}}\n\n')
                _mark_closed(state, tc_info["index"])
            state[key] = False


def _finalize_sse(state) -> str:
    """流收尾事件：关块 + message_delta(stop+usage) + message_stop；已收尾返回空串。

    两个调用方：[DONE] 常规路径；gen() 兜底——上游发完 finish_reason 直接断连
    （无 [DONE]）时 finished=True 会跳过 error 分支，若不补收尾事件 CC 永远等
    不到 message_stop → 判流截断自动重试（正是"输出回退重输出"的成因之一）。
    """
    if state.get("stopped"):
        return ""
    out = []
    # 关块幂等（text_open/tool_*_open 不置位则无输出），未关先补关、已关无副作用
    _close_text_block(state, out)
    _close_tool_blocks(state, out)
    anth_reason = state.get("stop_reason") or "end_turn"
    # why: 把 usage 并进收尾 delta 一起发——上游（DeepSeek 系）每个 chunk
    #      都带 usage，逐个转 message_delta 会放大成与 token 数相当的冗余事件流，
    #      CC 在慢速上游下易把海量 usage delta 当异常/超时，触发自动重试
    #      （表现"输出一半回退重新输出"）。只发一次，携带最新累计值。
    stop_delta = {"type": "message_delta", "delta": {"stop_reason": anth_reason, "stop_sequence": None, "stop_details": {"type": "stop", "reason": anth_reason}}}
    _usage = {}
    if state.get("output_tokens"):
        _usage["output_tokens"] = state["output_tokens"]
    # 补真 input_tokens：上游 usage 通常只在收尾前一个 chunk 才出现（首 chunk
    # 只有 reasoning_content），message_start 已发出去 0，这里把它修正回真值，
    # 否则 CC 整个会话都以为输入是空的。
    if state.get("input_tokens"):
        _usage["input_tokens"] = state["input_tokens"]
    if _usage:
        stop_delta["usage"] = _usage
    out.append(f"event: message_delta\ndata: {json.dumps(stop_delta, separators=(',', ':'))}\n\n")
    out.append('event: message_stop\ndata: {"type":"message_stop"}\n\n')
    state["finished"] = True
    state["stopped"] = True
    return "".join(out)


def _close_open_blocks(state) -> str:
    """关掉所有仍开着的块，返回事件串（**不**补 message_delta/message_stop）。

    错误路径专用：上游断流/超时时若有块未闭合，CC 收到的是悬空的
    content_block_start 而没有对应 stop。先补关再报错，客户端拿到的半个
    响应至少结构完整。
    """
    out = []
    _close_text_block(state, out)
    _close_tool_blocks(state, out)
    return "".join(out)


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
            # 必须先补 message_start：整条流只有一个 [DONE]（空补全 / 网关空响应）时
            # 这里直接收尾，会发出没有 message_start 的 message_delta+message_stop，
            # 协议非法。_ensure_started 幂等，正常流已有 start 时无副作用。
            _ensure_started(state, out, msg_id, model)
            fin = _finalize_sse(state)
            if fin:
                out.append(fin)
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

        # usage 先记账再发事件：message_start 是首个 chunk 里发的，要带上真 input_tokens。
        # 上游（DeepSeek 系）每个 chunk 都带 usage，逐个转 message_delta 会放大成与
        # token 数同量级的冗余事件流（实测 200 字响应 302 事件里 154 个是 usage-only
        # delta）。慢速上游 + 海量冗余事件，CC 易把慢/异常当超时触发自动重试
        # → 表现"输出一半回退重输出"。因此 usage 只记账，收尾时合并成一次 message_delta。
        usage = obj.get("usage")
        if usage:
            # 取 max 而非覆盖：上游可能先发只带 prompt_tokens 的 chunk
            # （缺失的 completion_tokens 取默认 0），覆盖会把已累计的输出量清零，
            # 收尾时 output_tokens 直接消失
            _ct = usage.get("completion_tokens")
            if isinstance(_ct, int) and _ct > state.get("output_tokens", 0):
                state["output_tokens"] = _ct
            if usage.get("prompt_tokens"):
                state["input_tokens"] = usage["prompt_tokens"]

        _ensure_started(state, out, msg_id, model)

        # 已收尾（finish_reason 或 [DONE] 已发）后上游再吐正文/工具增量 → 一律丢弃。
        # why: 收尾后再发块 = 同 index 二次 start → CC 重放该块、tool_use 被再执行一次。
        #      usage 不丢（仍需累计 output_tokens），只丢内容。
        terminal = state.get("finished") or state.get("stopped")

        for choice in (obj.get("choices") or []):
            # 显式 null 容错：mimo 等 OpenAI 兼容端点会发 "delta":{... "tool_calls":null
            # "reasoning_content":null}，`.get(k, default)` 对"缺键"生效但对"显式 null"
            # 无效 → 迭代 None 抛 TypeError，整条流被自己的异常处理器判成 upstream 断连。
            delta = choice.get("delta") or {}
            content = delta.get("content")
            if content and terminal:
                state["dup_blocks"] = state.get("dup_blocks", 0) + 1
            elif content:
                if not state.get("text_open"):
                    # 同一时刻只允许一个块开着：正文与工具块交替时不先关对方，
                    # 两个块会交错收尾（Anthropic 要求块严格顺序 start→stop）
                    _close_tool_blocks(state, out)
                    _open_text_block(state, out)
                block_delta = {
                    "type": "content_block_delta",
                    "index": state["text_idx"],
                    "delta": {"type": "text_delta", "text": content},
                }
                state["text_chars"] = state.get("text_chars", 0) + len(content)
                out.append(f"event: content_block_delta\ndata: {json.dumps(block_delta, separators=(',', ':'))}\n\n")

            for tc in (delta.get("tool_calls") or []):
                raw_idx = tc.get("index")
                if raw_idx is None:
                    # 部分 OpenAI 兼容端点的流式响应不带 tool_calls[].index，只能靠
                    # 数组位置。旧版统一兜 0 → 多个并行工具全落到 tool_0，name 互相
                    # 覆盖、arguments 首尾拼接 → 工具参数 JSON 损坏或调错工具。
                    # 有 id 的按 id 首次出现分配槽位；无 id 的只能归到最后一个已知槽。
                    tid = tc.get("id")
                    slots = state.setdefault("_tool_ids", {})
                    if tid:
                        if tid not in slots:
                            slots[tid] = len(slots)
                        tc_idx = slots[tid]
                    else:
                        tc_idx = max(len(slots) - 1, 0)
                else:
                    tc_idx = raw_idx
                tc_key = f"tool_{tc_idx}"

                existing = state.get(tc_key)
                # 守卫必须在 _alloc_idx 之前：旧版先建条目（吃掉一个 index）再判
                # terminal/已关闭，被丢弃的调用仍占号 → 下游 index 出现空洞。
                # 该工具块已关闭/已收尾后又被投递 → 上游重复投递，再发一次 start 会让
                # CC 重放该工具块并**再执行一次**（副作用翻倍），直接丢。
                if terminal or (existing is not None and existing["index"] in state.get("_closed_idx", set())):
                    state["dup_blocks"] = state.get("dup_blocks", 0) + 1
                    continue

                if existing is None:
                    _close_text_block(state, out)  # 保块严格顺序，见上
                    existing = state[tc_key] = {
                        "index": _alloc_idx(state),
                        "id": tc.get("id") or "",
                        "name": "",
                        "args": "",
                    }
                tc_info = existing
                if "id" in tc and tc["id"]:
                    tc_info["id"] = tc["id"]
                # 显式 null 容错：部分端点发 "function":null，.get(k, {}) 对缺键生效
                # 但对 null 无效 → fn.get 抛 AttributeError，被 gen() 兜成
                # "stream interrupted"，真实原因被掩盖
                fn = tc.get("function") or {}
                if "name" in fn and fn["name"]:
                    tc_info["name"] = fn["name"]
                if "arguments" in fn and fn["arguments"]:
                    tc_info["args"] += fn["arguments"]

                if not state.get(f"{tc_key}_open"):
                    state[f"{tc_key}_open"] = True
                    block_start = {
                        "type": "content_block_start",
                        "index": tc_info["index"],
                        "content_block": {"type": "tool_use", "id": tc_info["id"], "name": tc_info["name"], "input": {}},
                    }
                    _block_start(state, out, tc_info["index"],
                                 f"event: content_block_start\ndata: {json.dumps(block_start, separators=(',', ':'))}\n\n",
                                 f"tool_use:{tc_info['name']}")

                if fn.get("arguments"):
                    args_delta = {
                        "type": "content_block_delta",
                        "index": tc_info["index"],
                        "delta": {"type": "input_json_delta", "partial_json": fn["arguments"]},
                    }
                    out.append(f"event: content_block_delta\ndata: {json.dumps(args_delta, separators=(',', ':'))}\n\n")

            _fr = choice.get("finish_reason")
            if _fr:
                _close_text_block(state, out)
                _close_tool_blocks(state, out)
                # why: 不在此处发 message_delta —— 上游（DeepSeek 系）带 finish_reason 的
                #      chunk 后面还跟着 usage-only chunk，那个 delta 的 stop_reason 是 None，
                #      会把真实 stop_reason（max_tokens/tool_use）覆盖成 null/end_turn，
                #      导致 CC 收到被截断的输出时误判正常结束、不自动续写。
                #      记下来，等 [DONE] 时作为流内最后一个 message_delta 发出。
                state["stop_reason"] = _map_finish_reason(_fr)
                state["finished"] = True

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
    choices = openai_body.get("choices") or []
    content = []
    for ch in choices:
        msg = ch.get("message") or {}
        text = msg.get("content")
        if isinstance(text, str) and text:
            content.append({"type": "text", "text": text})
        for tc in (msg.get("tool_calls") or []):
            fn = tc.get("function") or {}
            raw_args = fn.get("arguments") or "{}"
            try:
                parsed = json.loads(raw_args)
                if not isinstance(parsed, dict):
                    parsed = {"_raw": raw_args}
            except Exception:
                # 宽松代理回显非 JSON arguments 时不能让 JSONDecodeError 冒成 500
                parsed = {"_raw": str(raw_args)}
            content.append({
                "type": "tool_use",
                "id": tc.get("id", ""),
                "name": fn.get("name", ""),
                "input": parsed,
            })
    usage = openai_body.get("usage") or {}
    finish = None
    if choices:
        # 与流式路径共用 _FINISH_REASON_MAP（旧版各写一份，改一处必漂移）；
        # 缺 length/content_filter 会让 CC 对截断响应判成正常结束、不续写
        finish = _map_finish_reason(choices[0].get("finish_reason"))
    return {
        "id": openai_body.get("id", msg_id),
        "type": "message",
        "role": "assistant",
        "model": openai_body.get("model", ""),
        "content": content,
        "stop_reason": finish,
        "stop_sequence": None,
        "usage": {
            "input_tokens": usage.get("prompt_tokens", 0) or 0,
            "output_tokens": usage.get("completion_tokens", 0) or 0,
        },
    }


async def _non_stream_fallback(target_url, headers, upstream_body, host_header, extra_ext,
                               use_win_curl, req_no) -> str:
    """流式失败时回落非流式，返回等价 SSE 帧串；失败返回空串。

    两种触发场景（内网网关实测）：
    1. 空流：`deepseek-v4.1-flash-outside` 流式恒 HTTP 200 + 仅 `data: [DONE]`；
    2. 502 饱和：`ModelArts.81114 上游负载已饱和`，同一请求非流式重试常能成功。

    why 重试：502 是间歇的（10 次采样 7 次失败但成功那 3 次正常），
    让 CC 自己重试会重跑整个请求（含已完成的部分），在 bridge 里退避重试更省。
    """
    fb_body = dict(upstream_body)
    fb_body["stream"] = False
    fb_body.pop("stream_options", None)
    for attempt in range(3):
        try:
            fb_status, fb_text = await _upstream_post(
                target_url, headers, fb_body, host_header, extra_ext, use_win_curl
            )
            if fb_status == 200:
                try:
                    return anthropic_resp_to_sse(
                        openai_to_anthropic_resp(json.loads(fb_text), f"msg_bridge_{req_no}")
                    )
                except Exception as e:
                    print(f"[bridge] fallback JSON parse failed: {type(e).__name__}: {e}", flush=True)
                    return ""
            print(f"[bridge] non-stream fallback failed: status={fb_status} {fb_text[:200]}", flush=True)
            # 只对上游过载类错误重试；其他状态码重试无意义
            if fb_status not in (429, 502, 503, 504):
                return ""
        except Exception as e:
            print(f"[bridge] non-stream fallback error: {type(e).__name__}: {e}", flush=True)
        if attempt < 2:
            await asyncio.sleep(1.5 * (attempt + 1))
    return ""


def anthropic_resp_to_sse(resp: dict) -> str:
    """非流式 Anthropic message → 等价 SSE 帧序列。

    why: 部分上游（实测内网网关 deepseek-v4.1-flash-outside）流式恒回 HTTP 200 +
    仅 `data: [DONE]`（零 chunk），非流式却正常。此时报 upstream_incomplete 只会让
    CC 反复重试同一个必然失败的请求；把非流式结果转成 SSE 帧下发，功能可用且
    客户端无感（只是没有逐字流式效果）。
    """
    msg_id = resp.get("id", "msg_bridge")
    model = resp.get("model", "")
    usage = resp.get("usage") or {}
    events = []
    start_msg = dict(resp)
    start_msg["content"] = []
    start_msg["stop_reason"] = None
    start_msg["usage"] = {"input_tokens": usage.get("input_tokens", 0), "output_tokens": 0}
    events.append(f"event: message_start\ndata: {json.dumps({'type': 'message_start', 'message': start_msg}, ensure_ascii=False, separators=(',', ':'))}\n\n")
    events.append('event: ping\ndata: {"type":"ping"}\n\n')
    for idx, blk in enumerate(resp.get("content") or []):
        if blk.get("type") == "text":
            events.append(f"event: content_block_start\ndata: {json.dumps({'type': 'content_block_start', 'index': idx, 'content_block': {'type': 'text', 'text': ''}}, separators=(',', ':'))}\n\n")
            events.append(f"event: content_block_delta\ndata: {json.dumps({'type': 'content_block_delta', 'index': idx, 'delta': {'type': 'text_delta', 'text': blk.get('text', '')}}, ensure_ascii=False, separators=(',', ':'))}\n\n")
            events.append(f"event: content_block_stop\ndata: {json.dumps({'type': 'content_block_stop', 'index': idx}, separators=(',', ':'))}\n\n")
        elif blk.get("type") == "tool_use":
            events.append(f"event: content_block_start\ndata: {json.dumps({'type': 'content_block_start', 'index': idx, 'content_block': {'type': 'tool_use', 'id': blk.get('id', ''), 'name': blk.get('name', ''), 'input': {}}}, ensure_ascii=False, separators=(',', ':'))}\n\n")
            events.append(f"event: content_block_delta\ndata: {json.dumps({'type': 'content_block_delta', 'index': idx, 'delta': {'type': 'input_json_delta', 'partial_json': json.dumps(blk.get('input') or {}, ensure_ascii=False)}}, ensure_ascii=False, separators=(',', ':'))}\n\n")
            events.append(f"event: content_block_stop\ndata: {json.dumps({'type': 'content_block_stop', 'index': idx}, separators=(',', ':'))}\n\n")
    stop_reason = resp.get("stop_reason") or "end_turn"
    events.append(f"event: message_delta\ndata: {json.dumps({'type': 'message_delta', 'delta': {'stop_reason': stop_reason, 'stop_sequence': None, 'stop_details': {'type': 'stop', 'reason': stop_reason}}, 'usage': {'input_tokens': usage.get('input_tokens', 0), 'output_tokens': usage.get('output_tokens', 0)}}, ensure_ascii=False, separators=(',', ':'))}\n\n")
    events.append('event: message_stop\ndata: {"type":"message_stop"}\n\n')
    return "".join(events)


app = FastAPI()
state = {"upstream": "", "upstream_key": "", "upstream_model": ""}
http_client = None

# 并发闸（0 = 不限）。slow 链路（境外 DERP 中继等）在途字节一多就整体断流：
# 实测单路 120KB 稳定，2×100KB 双双失败。用排队换可靠性，闸值来自 preset 的
# max_concurrency，由 ensure-bridge.sh 经 env 传入。
_gate_obj = None
_gate_owner = -1


def _gate():
    n = int(state.get("max_concurrency") or 0)
    if n <= 0:
        return None
    global _gate_obj, _gate_owner
    if _gate_obj is None or _gate_owner != n:
        _gate_obj, _gate_owner = asyncio.Semaphore(n), n
    return _gate_obj


async def _gated(agen):
    """把流式响应包进闸门，闸门持有到**第一个回包**为止。

    why 不持有整条流：瓶颈是请求体上行（Claude 每轮几十~几百 KB），token 回流只有
    几 KB/s 量级。上传完成即释放，多路响应流可以重叠，排队成本最小。
    """
    gate = _gate()
    if gate is None:
        async for item in agen:
            yield item
        return
    await gate.acquire()
    held = True
    try:
        async for item in agen:
            if held:
                gate.release()
                held = False
            yield item
    finally:
        if held:
            gate.release()


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
        if hk.lower() == "host":
            # headers 里已带 Host（SNI 需要），下面 host_header 分支还会补一条——
            # 循环再带一遍就是双 Host（RFC 7230 下游可能 400/路由错）
            continue
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
        if hk.lower() == "host":
            # headers 里已带 Host（SNI 需要），下面 host_header 分支还会补一条——
            # 循环再带一遍就是双 Host（RFC 7230 下游可能 400/路由错）
            continue
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


# ========== 传输层统一入口 ==========
# why：win_curl / httpx 两种传输原本在 messages() 里按「流式 × 传输」展开成四个
# 分支，非流式的 JSON 解析与错误归因因此逐字重复了一份（改一处必漏另一处，历史上
# 就漏过状态码检查）。抽成下面两个函数后协议层只剩一条路径，传输退化为参数。


async def _upstream_stream(target_url, headers, body, host_header, extra_ext, use_win_curl):
    """流式：yield 上游原始文本 chunk（未解析）。"""
    if use_win_curl:
        async for chunk in _stream_via_win_curl(target_url, headers, body, host_header):
            yield chunk
        return
    async with http_client.stream(
        "POST", target_url, headers=headers, json=body, extensions=extra_ext or None,
    ) as r:
        async for chunk in r.aiter_text():
            yield chunk


async def _upstream_post(target_url, headers, body, host_header, extra_ext, use_win_curl) -> tuple:
    """非流式：返回 (status, text)。status=0 表示传输层失败，text 为诊断文本。"""
    if use_win_curl:
        return await _post_via_win_curl(target_url, headers, body, host_header)
    try:
        r = await http_client.post(
            target_url, headers=headers, json=body, extensions=extra_ext or None,
        )
    except httpx.TransportError as e:
        print(f"[bridge] upstream post error: {type(e).__name__}: {e}", flush=True)
        return 0, f"{type(e).__name__}: {e}"
    return r.status_code, r.text


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
    host_header = state.get("upstream_host")
    use_win_curl = state.get("use_win_curl", False)

    # URL 已含版本段（/v1, /v4, /paas/v4, /openai/v1 等）或完整路径 → 只追加 /chat/completions
    # why: 之前只检测 /v1，遇到智谱 paas/v4 类非标准路径会拼成 /v4/v1/chat/completions → 404
    if re.search(r"/v\d+(/|$)", upstream_base) or "/chat/completions" in upstream_base:
        target_url = upstream_base + "/chat/completions"
    else:
        target_url = upstream_base + "/v1/chat/completions"

    # 如果 upstream 用 IP 代替了域名，加 Host header 保 SNI 和路由
    extra_ext = {}
    if host_header:
        headers["Host"] = host_header
        # SSL 握手时 SNI 用域名（让服务端证书验证通过）
        extra_ext["sni_hostname"] = host_header

    if stream:
        _REQ_SEQ[0] += 1
        sse_state = {"started": False, "finished": False}

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
        # 逐请求原始流存档：OPENAI_BRIDGE_DUMP=<dir> 时落盘，用于复盘上游违约
        # （重复块/重复收尾）而不用重跑现场
        dump_chunks = []
        req_no = _REQ_SEQ[0]
        # 给下游发过东西的时刻：思考（reasoning）阶段的 chunk 被本 bridge 丢弃，
        # 上游有数据但 CC 侧一个字节都收不到，靠这个计时补心跳
        last_out = [time.monotonic()]
        QUIET_PING = 10.0

        def _render(chunk: str):
            # SSE 注释（idle 心跳，`:` 开头）必须原样透传：喂给
            # openai_chunk_to_anthropic_sse 会因不以 data: 开头被丢掉，
            # 心跳等于没发，tailscale 75s idle 断流照样发生
            if chunk.startswith(":"):
                last_out[0] = time.monotonic()
                return chunk
            if len(raw_buf[0]) < 4096:
                raw_buf[0] += chunk
            if DUMP_DIR:
                dump_chunks.append(chunk)
            out = openai_chunk_to_anthropic_sse(chunk, f"msg_bridge_{req_no}", state["upstream_model"], sse_state)
            if out:
                last_out[0] = time.monotonic()
                return out
            # 上游在思考（只有 reasoning_content 增量，本 bridge 不发这类块）时，
            # 队列一直有数据、_iter_with_idle_ping 的 idle 心跳永远不触发，但 CC
            # 侧是彻底静默的——长思考照样会被 tailscale(75s)/网关 idle cap 掐断。
            # 这里按"距上次真正输出"补注释心跳。
            if time.monotonic() - last_out[0] >= QUIET_PING:
                last_out[0] = time.monotonic()
                sse_state["quiet_pings"] = sse_state.get("quiet_pings", 0) + 1
                return ": ping\n\n"
            return None

        def _dump_and_summary(tag: str):
            # 一行摘要便于 grep：块数 / 重复块 / 工具数 / 收尾原因 / 输出 token
            print(
                f"[bridge] stream {tag} req={req_no} text_blocks={sse_state.get('text_blocks', 0)}"
                f" tool_blocks={sse_state.get('tool_blocks', 0)} dup_blocks={sse_state.get('dup_blocks', 0)}"
                f" stop={sse_state.get('stop_reason') or '-'} out_tok={sse_state.get('output_tokens', 0)}"
                f" text_chars={sse_state.get('text_chars', 0)} quiet_pings={sse_state.get('quiet_pings', 0)}",
                flush=True,
            )
            if DUMP_DIR:
                try:
                    with open(f"{DUMP_DIR}/{int(time.time() * 1000)}-{req_no}.raw", "w") as f:
                        f.write("".join(dump_chunks))
                except Exception as e:
                    print(f"[bridge] dump failed: {e}", flush=True)

        async def gen():
            # 捕获 upstream 间歇性超时/断连：log + 结束 stream，不让异常杀进程
            # Claude Code 收到不完整响应会自动重试，比 bridge 整个死掉强
            # 尚无内容块时暂存的帧：空流场景（上游只回 [DONE]）这些帧要整体丢弃，
            # 换成非流式兜底；一旦出现真内容就按序放行。
            pending = []
            try:
                src = _upstream_stream(target_url, headers, upstream_body, host_header, extra_ext, use_win_curl)
                async for chunk in _iter_with_idle_ping(_iter_complete_lines(src)):
                    sse_out = _render(chunk)
                    if not sse_out:
                        continue
                    if not (sse_state.get("text_blocks") or sse_state.get("tool_blocks")):
                        pending.append(sse_out)
                        continue
                    if pending:
                        yield "".join(pending)
                        pending.clear()
                    yield sse_out
            except Exception as e:
                # why Exception 而非 httpx.TransportError：win_curl 路径抛的是
                # OSError/ConnectionResetError 之类，漏掉会让异常直接逃出 gen() ——
                # 客户端既拿不到 error 事件也等不到 message_stop，表现为永久卡死
                print(f"[bridge] upstream stream error: {type(e).__name__}: {e}", flush=True)
                # yield SSE error event 让 Claude Code 立刻看到错误（不等 4 分钟）
                sse_state["finished"] = True
                # 先补关未闭合的块：错误事件之后不该再留悬空的 content_block_start
                tail = _close_open_blocks(sse_state)
                if tail:
                    yield tail
                # 区分"curl.exe 启动失败/连不上"（stderr 有诊断信息）和"中途断连"：
                # 前者归因 upstream_error 带 stderr 原文，后者归因 upstream_disconnected
                if isinstance(e, _WinCurlUpstreamError):
                    yield _error_frames("upstream_error", e.stderr_text[:500])
                else:
                    yield _error_frames("upstream_disconnected", "stream interrupted")
                _dump_and_summary("error")
                return
            # 空流兜底：上游回了合法 SSE 却零内容块（实测内网网关
            # deepseek-v4.1-flash-outside 恒为 HTTP 200 + 仅 data: [DONE]）。
            # 必须在 finished 判定**之前**——[DONE] 已把 finished 置 True，
            # 落到下面的 error 分支就永远进不来。该模型非流式正常，
            # 回落非流式取完整结果转成 SSE，客户端无感。
            if pending and not (sse_state.get("text_blocks") or sse_state.get("tool_blocks")):
                print("[bridge] upstream stream had zero content blocks, falling back to non-stream", flush=True)
                fallback = await _non_stream_fallback(
                    target_url, headers, upstream_body, host_header, extra_ext, use_win_curl, req_no
                )
                if fallback:
                    yield fallback
                    _dump_and_summary("fallback")
                    return
                # 兜底失败：放回暂存帧，让下面的既有逻辑照常报错/收尾
                for p in pending:
                    yield p
                pending = []
            # upstream 结束却没给终止标记（截断 / 空响应）→ 显式报错
            # why: 否则客户端只拿到半条流且无从判断，探测也只能靠"缺少 message_stop"
            #      间接推断；显式 error 让两边都能确定地识别失败
            if not sse_state.get("finished"):
                tail = _close_open_blocks(sse_state)  # 同上：报错前先闭块
                if tail:
                    yield tail
                if "data:" not in raw_buf[0] and raw_buf[0].strip():
                    # 一整个 data: 行都没出现过 → upstream 回的不是 SSE。
                    # one-api 类网关对"模型无可用渠道/额度不足"就是 HTTP 200 + 裸 JSON
                    # error，报 upstream_incomplete 会把人引向查网络，其实是上游拒绝
                    detail = raw_buf[0].strip()[:500]
                    print(f"[bridge] upstream returned non-SSE body: {detail}", flush=True)
                    # 该错误体是"上游过载"（ModelArts 负载饱和 / 502）→ 非流式重试
                    # 常能成功（网关侧间歇性），比把错误直接甩给 CC 让它整轮重跑强
                    if not (sse_state.get("text_blocks") or sse_state.get("tool_blocks")) and re.search(
                        r'负载已饱和|overload|service.?unavailable|bad_response_status_code', detail, re.I):
                        fb = await _non_stream_fallback(
                            target_url, headers, upstream_body, host_header, extra_ext, use_win_curl, req_no
                        )
                        if fb:
                            yield fb
                            _dump_and_summary("fallback")
                            return
                    yield _error_frames("upstream_error", detail)
                else:
                    print("[bridge] upstream stream ended without [DONE] (truncated or empty)", flush=True)
                    yield _error_frames("upstream_incomplete", "upstream stream ended without completion marker")
            elif not sse_state.get("stopped"):
                # finish_reason 已到但上游没发 [DONE] 就断连：finished=True 会让上面
                # 的 error 分支跳过，若不补收尾 CC 等不到 message_stop → 判截断自动
                # 重试（"输出回退重输出"成因之一）。补发与 [DONE] 常规收尾同形的事件。
                print("[bridge] upstream closed after finish_reason without [DONE] (finalize fallback)", flush=True)
                fin = _finalize_sse(sse_state)
                if fin:
                    yield fin
            _dump_and_summary("done" if sse_state.get("finished") else "unfinished")
        return StreamingResponse(_gated(gen()), media_type="text/event-stream")
    else:
        gate = _gate()
        if gate is not None:
            await gate.acquire()
        try:
            r_status, r_text = await _upstream_post(
                target_url, headers, upstream_body, host_header, extra_ext, use_win_curl
            )
        finally:
            if gate is not None:
                gate.release()
        # status=0 是传输层失败（连不上/超时），与"上游明确回了个 4xx/5xx"要分开归因
        if r_status == 0:
            return JSONResponse({"error": "upstream timeout", "body": r_text[:300]}, status_code=529)
        # 旧版 httpx 分支不查状态码（win_curl 分支查），上游 5xx 若返回合法
        # ChatCompletion 形状（无 "error" 键）会被一路转成 HTTP 200 + 空 content，
        # CC 表现为"模型不说话"而不是报错，无从归因
        if r_status >= 400:
            print(f"[bridge] upstream http {r_status}: {r_text[:300]}", flush=True)
            return JSONResponse({"error": "upstream_error", "body": r_text[:500]}, status_code=r_status)
        try:
            openai_json = json.loads(r_text)
        except Exception:
            return JSONResponse({"error": "upstream non-json", "body": r_text[:500]}, status_code=502)
        # 网关 HTTP 200 + {"error":...} 拒绝（无可用渠道/额度不足）时，
        # openai_to_anthropic_resp 会产出空消息，表现为"模型不说话"而非报错
        if isinstance(openai_json, dict) and "error" in openai_json:
            return JSONResponse({"error": "upstream_error", "body": r_text[:500]}, status_code=502)
        return JSONResponse(openai_to_anthropic_resp(openai_json))


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
    safe_state = dict(state)
    if "upstream_key" in safe_state:
        safe_state["upstream_key"] = "***"
    return {"ok": True, "state": safe_state}


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
        "max_concurrency": int(state.get("max_concurrency") or 0),
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
    parser.add_argument("--max-concurrency", type=int,
                        default=int(os.environ.get("OPENAI_BRIDGE_MAX_CONCURRENCY", "0") or 0),
                        help="同时在途的上游请求上限（0=不限）；慢链路用排队换可靠性")
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
    state["max_concurrency"] = args.max_concurrency

    print(f"[openai-bridge] upstream={args.upstream} model={args.upstream_model} host_header={args.upstream_host or '(none)'} win_curl={args.use_win_curl} skip_tls_verify={args.skip_tls_verify} max_conc={args.max_concurrency}", flush=True)
    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()

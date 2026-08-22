#!/usr/bin/env python3
"""重写 openai_bridge_tail.py / openai_bridge_0731.py 的 openai_chunk_to_anthropic_sse
为 robust 单-message_delta-at-[DONE] 设计。两文件同一份逻辑。

依据真实 DeepSeek 上游流式格式（已抓包确认）:
    ... content chunks (finish_reason:null) ...
    最后一个 content chunk 带 finish_reason:"length"/"stop"/"tool_calls"
    data: {"choices":[],"usage":{completion_tokens:N}}   # 空 choices 独立 usage chunk
    data: [DONE]

修复 code-review 确认的两个 bug:
1. tail 版 `if _fr or _usage:` 在 for 循环外 -> 空 choices usage chunk 触发
   UnboundLocalError（实测崩溃）
2. 两 bridge 丢弃空 choices usage chunk 且 [DONE] 不关 block -> 漏 content_block_stop、
   usage 不报（实测 text_open_0 残留 True）

新设计: 跨 chunk 把 finish_reason/usage 累积进 state。在 [DONE] 统一收尾:
关未关 block -> 唯一一个 message_delta(stop_reason + usage) -> message_stop。
- _fr/_usage 在循环内累积到 state，不做外层 if -> 空 choices 不再 UnboundLocalError
- 统一在 [DONE] 收尾 -> finish_reason/usage 无论出现在哪个 chunk 都被捕获
- md_sent 防护 -> message_delta 只发一次，杜绝 double-delta
- [DONE] 关所有未关 block -> 杜绝漏 content_block_stop
"""
import py_compile
import importlib.util

NEW_FN = r'''def openai_chunk_to_anthropic_sse(chunk_text: str, msg_id: str, model: str, state=None):
    """OpenAI stream chunk -> 跨 chunk 累积 finish_reason/usage，在 [DONE]
    统一收尾为单个 message_delta(stop_reason + usage) -> message_stop。"""
    if state is None:
        state = {"started": False, "finished": False, "block_idx": 0,
                 "md_sent": False}
    if not chunk_text:
        return None

    out = []

    def finalize():
        # 关掉所有仍未关闭的 block
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

    for line in chunk_text.split("\n"):
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[len("data:"):].strip()
        if not payload:
            continue
        if payload == "[DONE]":
            if state.get("finished") or state.get("md_sent"):
                continue
            finalize()
            state["finished"] = True
            state["md_sent"] = True
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

        # 累积 finish_reason/usage（choices 可能为空 -> 靠 dict.get 兜底，不触发 UnboundLocalError）
        if obj.get("choices"):
            for choice in obj["choices"]:
                fr = choice.get("finish_reason")
                if fr:
                    state["finish_reason"] = fr
        if obj.get("usage"):
            state["usage"] = obj["usage"]

        # 内容/工具块 delta 实时转发
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
'''

for path in ("openai_bridge_tail.py", "openai_bridge_0731.py"):
    with open(path) as f:
        content = f.read()
    start = content.index("def openai_chunk_to_anthropic_sse(")
    end = content.index("def openai_to_anthropic_resp(")
    # 保留 openai_to_anthropic_resp 的 def 行，替换掉整个 stream 函数
    content = content[:start] + NEW_FN + content[end + content[end:].index("\n") + 1 :].lstrip("\n")
    with open(path, "w") as f:
        f.write(content)
    py_compile.compile(path, doraise=True)
    print(f"patched + syntax OK: {path}")

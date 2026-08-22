def openai_chunk_to_anthropic_sse(chunk_text: str, msg_id: str, model: str, state=None):
    """OpenAI stream chunk (可能含多行 data:...) -> Anthropic SSE 事件集。

    finish_reason / usage <DEL>跨 chunk 累积进 state</DEL>，在 [DONE] 统一收尾为单个
    message_delta(stop_reason + usage) -> message_stop。md_sent 防护保证
    message_delta 只发一次；收尾关闭所有未关 block，杜绝漏 content_block_stop。
    兼容 provider 各种结尾: finish 在 content chunk、独立空 choices usage chunk、裸 [DONE]。
    """
    if state is None:
        state = {"started": False, "finished": False, "block_idx": 0,
                 "finish_reason": None, "usage": None, "md_sent": False}
    if not chunk_text:
        return None

    out = []

    def _emit_final():
        """流结束统一收尾，md_sent 防护保证只发一次 message_delta。"""
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
            _emit_final()
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

        _ensure_started(state, out, msg_id, model)

        # 累积 finish_reason / usage（choices 可能为空 -> 就地写 state，无 UnboundLocalError）
        if obj.get("choices"):
            for _c in obj["choices"]:
                _fr = _c.get("finish_reason")
                if _fr:
                    state["finish_reason"] = _fr
        if obj.get("usage"):
            state["usage"] = obj["usage"]

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



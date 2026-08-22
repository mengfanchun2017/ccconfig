#!/usr/bin/env python3
"""将 openai_bridge_tail.py / openai_bridge_0731.py 的 openai_chunk_to_anthropic_sse
重写为 robust 单-message_delta 设计（两文件同一份逻辑）。

真实 DeepSeek upstream 流式结尾（实测抓包确认）:
    ... content chunk (finish_reason:null) ...
    data: {"choices":[{"delta":{...},"finish_reason":"length"}],...}   # 最后一个 content chunk 带 finish
    data: {"choices":[],"usage":{prompt_tokens,completion_tokens,total_tokens}}  # 空 choices 独立 usage chunk
    data: [DONE]

修复 code-review + 实测确认的两个 bug:
1. tail 版 `if _fr or _usage:` 在 for 循环外 -> 空 choices 的 usage chunk 触发
   UnboundLocalError（已复现崩溃）
2. 两个 bridge 丢弃空 choices 的 usage chunk 且 [DONE] 不关 block -> 漏
   content_block_stop、usage 不报（已复现 text_open_0 残留 True）

新设计: 跨 chunk 把 finish_reason / usage 累积进 state；在 [DONE] 统一收尾:
关未关 block -> 唯一一个 message_delta(stop_reason + usage) -> message_stop。
- _fr/_usage 只在循环内就地处理，无外层 if -> 空 choices 不再 UnboundLocalError
- 统一在 [DONE] 收尾 -> finish_reason/usage 无论出现在哪个 chunk 都被捕获
- md_sent 防护 -> message_delta 只发一次，杜绝 double-delta
- 关所有未关 block -> 杜绝漏 content_block_stop
"""
import py_compile
import importlib.util
import json

NEW_FN = r'''def openai_chunk_to_anthropic_sse(chunk_text: str, msg_id: str, model: str, state=None):
    """OpenAI stream chunk -> Anthropic SSE 事件集。

    跨 chunk 累积 finish_reason / usage 到 state；在 [DONE] 统一收尾为
    单个 message_delta(stop_reason + usage) -> message_stop。md_sent 防护
    保证 message_delta 只发一次，杜绝 double-delta / 漏 content_block_stop。
    """
    if state is None:
        state = {"started": False, "finished": False, "block_idx": 0,
                 "finish_reason": None, "usage": None, "md_sent": False}
    if not chunk_text:
        return None

    out = []

    def _emit_final():
        """流结束收尾（只在 [DONE] 或异常收尾调一次）。"""
        if state.get("md_sent"):
            return
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
        state["md_sent"] = True

    for line in chunk_text.split("\n"):
        line = line.strip()
        if not line.startswith("data:"):
            continue
        payload = line[len("data:"):].strip()
        if not payload:
            continue
        if payload == "[DONE]":
            if state.get("finished"):
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

        # 累积 finish_reason / usage（choices 可能为空 ->PASS' if ok else 'FAIL'}")
        return ok

    allok = True
    # 场景1: 真实 DeepSeek 结尾（finish:"length" + 空choices usage + [DONE]）
    allok &= run("deepseek-real",
        [
            'data: {"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}',
            'data: {"choices":[{"delta":{"content":"世界"},"finish_reason":"length"}]}',
            'data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":20,"total_tokens":27}}',
            'data: [DONE]',
        ], True, "length")
    # 场景2: finish="stop" + usage 同一 chunk
    allok &= run("finish-with-usage",
        [
            'data: {"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}',
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"completion_tokens":9}}',
            'data: [DONE]',
        ], True, "stop")
    # 场景3: tool_calls 结尾
    allok &= run("tool-calls",
        [
            'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"t1","function":{"name":"f","arguments":"{}"}}]},"finish_reason":null}]}',
            'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":1,"completion_tokens":2}}',
            'data: [DONE]',
        ], True, "tool_calls")
    # 场景4: 裸 [DONE]（无 finish / 无 usage）
    allok &= run("bare-done",
        ['data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}', 'data: [DONE]'],
        True, None)
    return allok


for path in ("openai_bridge_tail.py", "openai_bridge_0731.py"):
    patch(path)
    ok = scen_test(path)
    print(f"  -> {path}: 场景测试 {'全部通过' if ok else '有失败'}\n")

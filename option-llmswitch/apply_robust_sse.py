#!/usr/bin/env python3
"""将 openai_bridge_tail.py / openai_bridge_0731.py 的 openai_chunk_to_anthropic_sse
重写为 robust 单-message_delta 设计。

真实 DeepSeek 上游流式结尾（已抓包确认）:
    ... content chunks (finish_reason:null) ...
    最后一个 content chunk 带 finish_reason:"length"/"stop"/"tool_calls"
    {"choices":[],"usage":{completion_tokens:N}}    # 空 choices 独立 usage chunk
    [DONE]

设计: 跨 chunk 把 finish_reason/usage 累积进 state；在 [DONE] 处关闭所有未关
block，发唯一一个 message_delta(stop_reason + usage)，再 message_stop。
- _fr/_usage 在循环外初始化 -> 空 choices chunk 不触发 UnboundLocalError
- 统一在 [DONE] 收尾 -> finish_reason/usage 无论在哪出现都捕获
- 单个 message_delta -> 杜绝 double-delta
- 关闭所有未关 block -> 杜绝漏 content_block_stop
"""
import py_compile

STREAM_FN = r'''def openai_chunk_to_anthropic_sse(chunk_text: str, msg_id: str, model: str, state=None):
    """OpenAI stream chunk -> Anthropic SSE 事件集。

    跨 chunk 累积 finish_reason/usage，在 [DONE] 统一收尾为单个 message_delta。
    """
    if state is None:
        state = {"started": False, "finished": False, "block_idx": 0,
                 "finish_reason": None, "usage": None, "md_sent": False}
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
            if state.get("finished"):
                continue
            # 统一收尾：关未关 block -> 单个 message_delta(stop_reason + usage) -> message_stop

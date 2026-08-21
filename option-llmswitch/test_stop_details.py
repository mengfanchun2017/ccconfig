#!/usr/bin/env python3
"""验证 stop_details 补字段 — 用 Python dict 构造 chunk 避免转义问题。"""
import json
import sys
sys.path.insert(0, ".")
from openai_bridge import openai_chunk_to_anthropic_sse

MSG_ID = "msg_br_test"
MODEL = "deepseek-v4-flash-0731"


def make_chunk(choices):
    return f"data: {json.dumps({'id':'0','choices':choices}, ensure_ascii=False)}\n\n"


def run(title, chunks, expect_stop=True, expect_reason="end_turn"):
    print(f"=== {title} ===")
    state = {}
    merged = ""
    for c in chunks:
        out = openai_chunk_to_anthropic_sse(c, MSG_ID, MODEL, state)
        if out:
            merged += out

    has_stop_details = False
    reason = None
    for line in merged.split("\n"):
        if line.startswith("data:"):
            payload = line[len("data:"):].strip()
            try:
                obj = json.loads(payload)
            except Exception:
                continue
            if obj.get("type") == "message_delta":
                sd = obj.get("delta", {}).get("stop_details")
                if sd:
                    has_stop_details = True
                    reason = sd.get("reason")
                    break

    if expect_stop:
        assert has_stop_details, f"FAIL: 没找到 stop_details\n{merged[:800]}"
        assert reason == expect_reason, f"FAIL: reason={reason} 期望={expect_reason}"
        print(f"  ✅ stop_details 存在, reason={reason}")
    else:
        assert not has_stop_details, f"FAIL: 不该有 stop_details"
        print(f"  ✅ 确实没有 stop_details (符合预期)")


# 1: [DONE] 结束
run("[DONE] 结束", [
    make_chunk([{"index": 0, "delta": {"content": "Hello"}}]),
    "data: [DONE]\n\n",
], expect_stop=True, expect_reason="end_turn")

# 2: finish_reason=stop
run("finish_reason=stop", [
    make_chunk([{"index": 0, "delta": {"content": "hi"}, "finish_reason": "stop"}]),
], expect_stop=True, expect_reason="end_turn")

# 3: finish_reason=tool_calls
run("finish_reason=tool_calls", [
    make_chunk([{"index": 0,
                 "delta": {"tool_calls": [{"index": 0, "id": "call_1",
                                             "function": {"name": "get_weather", "arguments": '{"loc":"bj"}'}}]},
                 "finish_reason": "tool_calls"}]),
], expect_stop=True, expect_reason="tool_use")

# 4: finish_reason=length
run("finish_reason=length", [
    make_chunk([{"index": 0, "delta": {"content": "more"}, "finish_reason": "length"}]),
], expect_stop=True, expect_reason="max_tokens")

# 5: 正常流中间块
run("中间流块无 finish_reason", [
    make_chunk([{"index": 0, "delta": {"content": "work"}}]),
], expect_stop=False)

# 6: 空输入
out = openai_chunk_to_anthropic_sse("", MSG_ID, MODEL)
assert out is None, "FAIL: 空输入应返回 None"
print("=== 空输入: ✅ ===")

print("\n✅ 全部通过")

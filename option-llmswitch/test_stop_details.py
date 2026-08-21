#!/usr/bin/env python3
"""验证 stop_details 补字段 — 直接调 openai_chunk_to_anthropic_sse。"""
import json
import sys
sys.path.insert(0, ".")
from openai_bridge import openai_chunk_to_anthropic_sse

MSG_ID = "msg_br_test"
MODEL = "deepseek-v4-flash-0731"


def run(title, chunks, expect_stop=True, expect_reason="end_turn"):
    print(f"=== {title} ===")
    state = {}
    merged = ""
    for c in chunks:
        out = openai_chunk_to_anthropic_sse(c, MSG_ID, MODEL, state)
        if out:
            merged += out
    lines = merged.split("\n")
    found_stop_details = False
    found_reason = None
    for i, line in enumerate(lines):
        if line.startswith("data:") and '"message_delta"' in line:
            payload = line[len("data:"):].strip()
            obj = json.loads(payload)
            dd = obj.get("delta", {})
            sd = dd.get("stop_details")
            if sd:
                found_stop_details = True
                found_reason = sd.get("reason")
                break
    if expect_stop:
        assert found_stop_details, f"FAIL: 没找到 stop_details\n{merged[:500]}"
        assert found_reason == expect_reason, f"FAIL: stop_details.reason={found_reason} 期望={expect_reason}"
        print(f"  ✅ stop_details 存在, reason={found_reason}")
    else:
        assert not found_stop_details, f"FAIL: 不该有 stop_details 却找到了"
        print(f"  ✅ 确实没有 stop_details (符合预期)")
    return True


# 1. [DONE] 结束 — 最典型
run("[DONE] 结束", [
    'data: {"id":"0","choices":[{"index":0,"delta":{"content":"Hello"}}]}\n\n',
    'data: [DONE]\n\n',
], expect_stop=True, expect_reason="end_turn")

# 2. finish_reason=stop
run("finish_reason=stop", [
    'data: {"id":"0","choices":[{"index":0,"delta":{"content":"hi"},"finish_reason":"stop"}]}\n\n',
], expect_stop=True, expect_reason="end_turn")

# 3. finish_reason=tool_calls
run("finish_reason=tool_calls", [
    'data: {"id":"0","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_weather","arguments":"{\"loc\":\"bj\"}"}}]},"finish_reason":"tool_calls"}]}\n\n',
], expect_stop=True, expect_reason="tool_use")

# 4. finish_reason=length (max_tokens 截断)
run("finish_reason=length", [
    'data: {"id":"0","choices":[{"index":0,"delta":{"content":"more"},"finish_reason":"length"}]}\n\n',
], expect_stop=True, expect_reason="max_tokens")

# 5. 正常流中间块 — 不应该有 stop_details
run("中间流块无 finish_reason", [
    'data: {"id":"0","choices":[{"index":0,"delta":{"content":"work"}}]}\n\n',
], expect_stop=False)

# 6. 空输入
out = openai_chunk_to_anthropic_sse("", MSG_ID, MODEL)
assert out is None, "FAIL: 空输入应返回 None"
print("=== 空输入: ✅")

print("\n✅ 全部通过")

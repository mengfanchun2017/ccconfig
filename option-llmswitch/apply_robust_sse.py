#!/usr/bin/env python3
"""Rewrites openai_chunk_to_anthropic_sse in openai_bridge_tail.py and
openai_bridge_0731.py to a robust single-message_delta design, then tests.

Real DeepSeek upstream streaming tail (confirmed by capture):
    ... content chunks (finish_reason:null) ...
    last content chunk carries finish_reason:"length"/"stop"/"tool_calls"
    data: {"choices":[],"usage":{...completion_tokens:N}}   # empty-choices usage chunk
    data: [DONE]

Fixes two code-review confirmed bugs:
1. tail's `if _fr or _usage:` sits OUTSIDE the for-loop -> an empty-choices
   usage chunk raises UnboundLocalError (crash reproduced).
2. Both bridges drop the trailing empty-choices usage chunk and [DONE] no
   longer closes blocks -> missing content_block_stop, unreported usage,
   and (in tail) a duplicated message_delta.

New design: accumulate finish_reason/usage into state as chunks arrive;
at [DONE] close any open blocks and emit exactly ONE message_delta
(stop_reason + usage) then message_stop, guarded by md_sent so it can never
double-emit. Robust to every provider variant.
"""
import importlib.util
import json
import py_compile

NEW_FN = r'''def openai_chunk_to_anthropic_sse(chunk_text: str, msg_id: str, model: str, state=None):
    """OpenAI stream chunk -> Anthropic SSE 事件集。

    跨 chunk 把 finish_reason / usage 累积进 state，在 [DONE] 统一收尾为单个
    message_delta(stop_reason + usage) -> message_stop。md 1 and
              (not expect_usage or has_usage) and (not expect_fr or has_fr))
        print(f"  [{name}] md={md} ms={ms} cbs={cbs} usage={has_usage} stop_details={has_fr} "
              f"finished={state.get('finished')} -> {'PASS' if ok else 'FAIL'}")
        return ok

    allok = True
    allok &= test("deepseek-real",
        ['{"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}',
         '{"choices":[{"delta":{"content":"世界"},"finish_reason":"length"}]}',
         '{"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":20,"total_tokens":27}}',
         "[DONE]"], True, True)
    allok &= test("stop-with-usage",
        ['{"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}',
         '{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"completion_tokens":9}}',
         "[DONE]"], True, True)
    allok &= test("tool-calls",
        ['{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"t1","function":{"name":"f","arguments":"{}"}}]},"finish_reason":null}]}',
         '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
         '{"choices":[],"usage":{"completion_tokens":5}}',
         "[DONE]"], True, True)
    allok &= test("bare-done",
        ['{"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}', "[DONE]"], False, True)
    return allok


ok_all = True
for path in ("openai_bridge_tail.py", "openai_bridge_0731.py"):
    apply(path)
    ok_all &= run_scenario(path)
    print()

print(f"\n场景测试: {'全部通过' if ok_all else '有失败'}")

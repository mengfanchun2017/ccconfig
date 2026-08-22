#!/usr/bin/env python3
"""将 openai_bridge_tail.py 与 openai_bridge_0731.py 的 openai_chunk_to_anthropic_sse
统一重写为 robust 单-message_delta 设计（两文件同一份逻辑），并做 scenario 测试。

实测 DeepSeek upstream 流式结尾（抓包确认）:
    ... content chunks (finish_reason:null) ...
    最后一个 content chunk 带 finish_reason:"length"
    data: {"choices":[],"usage":{prompt_tokens,completion_tokens,total_tokens}}  # 空 choices 独立 usage chunk
    data: [DONE]

code-review 确认 + 复现的两个 bug:
1. tail 版 `if _fr or _usage:` 在 for 循环外 -> 空 choices 的 usage chunk 触发
   UnboundLocalError（已复现崩溃）
2. 两 bridge 丢弃空 choices 的 usage chunk 且 [DONE] 不再关 block -> 漏
   content_block_stop、usage 不报（已复现 text_open_0 残留 True）

新设计: 跨 chunk 把 finish_reason / usage 累积进 state；在 [DONE] 统一收尾:
关未关 block -> 唯一一个 message_delta(stop_reason + usage) -> message_stop。
md_sent 防护保证 message_delta 只发一次。对所有 provider 变体鲁棒。
"""
import importlib.util
import json
import py_compile

# ---------------------------------------------------------------------------
# 统一的新版 SSE 解析函数���注意: 字符串内的 \\n 是 Python 源码转义成 \n 换行符，
# 写入目标文件后 out.append(...) 会用真实换行，符合 .py 源码中“\n”的写法。
# ---------------------------------------------------------------------------
NEW_FN = (
    'def openai_chunk_to_anthropic_sse(chunk_text: str, msg_id: str, model: str, state=None):\n'
    "    \"\"\"OpenAI stream chunk -> Anthropic SSE 事件集。\n"
    "\n"
    "    跨 chunk 把 finish_reason / usage 累积进 state，在 [DONE] 统一收尾为单个\n"
    "    message_delta(stop_reason + usage) -> message if ok else 'FAIL'}")
        return ok

    allok = True
    # 真实 DeepSeek: content chunks -> finish:"length" -> 空choices usage -> [DONE]
    allok &= run("deepseek-real",
        ['{"choices":[{"delta":{"content":"你"},"finish_reason":null}]}',
         '{"choices":[{"delta":{"content":"好"},"finish_reason":"length"}]}',
         '{"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":20,"total_tokens":27}}',
         "[DONE]"], True, "length")
    # finish:"stop" + usage 同一 chunk
    allok &= run("stop-with-usage",
        ['{"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}',
         '{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"completion_tokens":9}}',
         "[DONE]"], True, "stop")
    # finish:"length" 不带 usage, 裸 [DONE]
    allok &= run("length-bare",
        ['{"choices":[{"delta":{"content":"x"},"finish_reason":null}]}',
         '{"choices":[{"delta":{},"finish_reason":"length"}]}',
         "[DONE]"], True, "length")
    # tool_calls 结尾
    allok &= run("tool-calls",
        ['{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"t1","function":{"name":"f","arguments":"{}"}}]},"finish_reason":null}]}',
         '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
         '{"choices":[],"usage":{"completion_tokens":5}}',
         "[DONE]"], True, "tool_calls")
    # 裸 [DONE]（无 finish / 无 usage）
    allok &= run("bare-done",
        ['{"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}', "[DONE]"], True, None)
    return allok


ok_all = True
for path in ("openai_bridge_tail.py", "openai_bridge_0731.py"):
    patch(path)
    ok_all &= scen_test(path)

print(f"\n场景测试: {'全部通过' if ok_all else '有失败'}")

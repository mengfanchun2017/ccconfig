#!/usr/bin/env python3
"""test-bridge-protocol.py — openai_bridge.py 协议转换层的单元回归。

为什么需要：`test-openai-bridge.sh` 用 mock upstream 跑端到端，但它只造
`delta.content + [DONE]` 这一种形态，因此**协议层的缺陷全都落在盲区外**：
[ DONE]-only 空流缺 message_start、工具块与文本块交错、tool_calls 无 index 导致
多工具塌成一个、usage 被覆盖清零、非标准 finish_reason 一律降级 end_turn、
stop_sequences 因字段名不匹配从未透传…… 这些都不会让端到端用例变红。

这个文件直接驱动转换函数，逐条钉住上述行为。纯本地、无网络、无进程。

用法: python3 ccconfig/tests/test-bridge-protocol.py
退出码: 0=全过, 1=有失败
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TARGET = os.environ.get("BRIDGE_PY", os.path.join(HERE, "..", "option-llmswitch", "openai_bridge.py"))

PASS = 0
FAIL = []


def ck(name, cond, detail=""):
    global PASS
    if cond:
        PASS += 1
        print(f"  ✅ {name}")
    else:
        FAIL.append(name)
        print(f"  ❌ {name}" + (f" — {detail}" if detail else ""))


def load():
    spec = importlib.util.spec_from_file_location("openai_bridge", TARGET)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def events(sse_text):
    return [ln.split(":", 1)[1].strip() for ln in (sse_text or "").splitlines() if ln.startswith("event:")]


def indexes(sse_text, evname):
    out = []
    for ln in (sse_text or "").splitlines():
        if ln.startswith("data:"):
            try:
                d = json.loads(ln[5:].strip())
            except Exception:
                continue
            if d.get("type") == evname:
                out.append(d.get("index"))
    return out


def main():
    ob = load()

    print("== finish_reason 映射（非标准值不得静默降级）==")
    for raw, want in [("stop", "end_turn"), ("tool_calls", "tool_use"), ("tool_call", "tool_use"),
                      ("eos", "end_turn"), ("length", "max_tokens"), ("content_filter", "content_filtered"),
                      ("stop_sequence", "stop_sequence"), ("wat", "end_turn")]:
        ck(f"{raw} → {want}", ob._map_finish_reason(raw) == want)
    ck("空 finish_reason → None", ob._map_finish_reason("") is None)

    print("== [DONE]-only 空流：必须有 message_start ==")
    st = {"started": False, "finished": False}
    e = events(ob.openai_chunk_to_anthropic_sse("data: [DONE]\n\n", "m1", "x", st))
    ck("含 message_start", "message_start" in e, str(e))
    ck("start 在 stop 之前", "message_start" in e and "message_stop" in e and e.index("message_start") < e.index("message_stop"), str(e))

    print("== 块交错：text → tool → text 必须严格顺序 ==")
    st = {"started": False, "finished": False}
    seq = ""
    for chunk in ['data: {"choices":[{"delta":{"content":"hello"}}]}\n\n',
                  'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"t1","function":{"name":"f","arguments":"{}"}}]}}]}\n\n',
                  'data: {"choices":[{"delta":{"content":"world"}}]}\n\n',
                  'data: [DONE]\n\n']:
        r = ob.openai_chunk_to_anthropic_sse(chunk, "m", "x", st)
        if r:
            seq += r
    starts = indexes(seq, "content_block_start")
    stops = indexes(seq, "content_block_stop")
    ck("start 与 stop 数量相等", len(starts) == len(stops), f"{starts} vs {stops}")
    ck("index 无重复", len(starts) == len(set(starts)), str(starts))
    ck("index 连续无空洞", starts == list(range(len(starts))), str(starts))

    print("== tool_calls 无 index：并行工具不得塌成一个 ==")
    st = {"started": False, "finished": False}
    seq = ""
    for chunk in ['data: {"choices":[{"delta":{"tool_calls":[{"id":"A","function":{"name":"fa","arguments":"{}"}}]}}]}\n\n',
                  'data: {"choices":[{"delta":{"tool_calls":[{"id":"B","function":{"name":"fb","arguments":"{}"}}]}}]}\n\n',
                  'data: [DONE]\n\n']:
        r = ob.openai_chunk_to_anthropic_sse(chunk, "m", "x", st)
        if r:
            seq += r
    names = [json.loads(ln[5:].strip()).get("content_block", {}).get("name")
             for ln in seq.splitlines()
             if ln.startswith("data:") and '"content_block_start"' in ln]
    ck("两个独立工具块", len(indexes(seq, "content_block_start")) == 2)
    ck("工具名未互相覆盖", sorted(n for n in names if n) == ["fa", "fb"], str(names))

    print("== usage 取 max，不被缺字段的 chunk 清零 ==")
    st = {"started": False, "finished": False}
    ob.openai_chunk_to_anthropic_sse(
        'data: {"choices":[{"delta":{"content":"x"}}],"usage":{"prompt_tokens":10,"completion_tokens":50}}\n\n', "m", "x", st)
    ob.openai_chunk_to_anthropic_sse(
        'data: {"choices":[{"delta":{}}],"usage":{"prompt_tokens":10}}\n\n', "m", "x", st)
    fin = ob.openai_chunk_to_anthropic_sse("data: [DONE]\n\n", "m", "x", st)
    ck("output_tokens 保持 50", '"output_tokens":50' in fin, fin[-160:])

    print("== 错误路径闭合已开块 ==")
    st = {"started": False, "finished": False}
    ob.openai_chunk_to_anthropic_sse('data: {"choices":[{"delta":{"content":"partial"}}]}\n\n', "m", "x", st)
    ck("补发 content_block_stop", "content_block_stop" in ob._close_open_blocks(st))

    print("== 请求转换：system 合并 / stop_sequences / is_error / 多块 tool_result / url 图 ==")
    body = {
        "system": [{"type": "text", "text": "S1"}, {"type": "text", "text": "S2"}],
        "stop_sequences": ["STOP"],
        "messages": [
            {"role": "user", "content": [
                {"type": "image", "source": {"type": "url", "url": "https://x/y.png"}},
                {"type": "text", "text": "看图"}]},
            {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "t1", "is_error": True,
                 "content": [{"type": "text", "text": "part1"}, {"type": "text", "text": "part2"}]}]},
        ],
    }
    r = ob.anthropic_to_openai_req(body, "m")
    sysm = [m for m in r["messages"] if m["role"] == "system"]
    ck("system 合并为一条", len(sysm) == 1 and "S1" in sysm[0]["content"] and "S2" in sysm[0]["content"], str(sysm))
    ck("stop_sequences → stop", r.get("stop") == ["STOP"], str(r.get("stop")))
    toolm = [m for m in r["messages"] if m["role"] == "tool"]
    ck("保留 is_error 标记", bool(toolm) and "tool_error" in toolm[0]["content"], str(toolm))
    ck("tool_result 多 text 块不丢", bool(toolm) and "part1" in toolm[0]["content"] and "part2" in toolm[0]["content"], str(toolm))
    urlmsgs = [m for m in r["messages"] if m["role"] == "user" and isinstance(m.get("content"), list)]
    ck("url 型图片不丢", any(s.get("image_url", {}).get("url") == "https://x/y.png"
                           for m in urlmsgs for s in m["content"]), str(urlmsgs))

    print("== stream_options 仅在流式时带 ==")
    ck("stream=True 带 include_usage",
       ob.anthropic_to_openai_req({"stream": True, "messages": []}, "m").get("stream_options") == {"include_usage": True})
    ck("stream=False 不带",
       "stream_options" not in ob.anthropic_to_openai_req({"stream": False, "messages": []}, "m"))
    ck("max_tokens=null 不原样透传",
       ob.anthropic_to_openai_req({"max_tokens": None, "messages": []}, "m")["max_tokens"] == 4096)

    print()
    print(f"通过 {PASS} 项" + (f"，失败 {len(FAIL)}：{FAIL}" if FAIL else "，全部通过"))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())

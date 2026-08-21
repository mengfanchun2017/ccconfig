#!/usr/bin/env python3
import json, sys; sys.path.insert(0, '.')

def _ensure_started(state, out, msg_id, model):
    if not state.get("started"):
        state["started"] = True
        msg_start = {
            "type": "message_start",
            "message": {
                "id": msg_id, "type": "message", "role": "assistant",
                "model": model, "content": [],
                "stop_reason": None, "stop_sequence": None,
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        }
        out.append(f"event: message_start\ndata: {json.dumps(msg_start, separators=(',', ':'))}\n\n")
        out.append('event: ping\ndata: {"type":"ping"}\n\n')

chunk_text = 'data: {"id":"0","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_weather","arguments":"{\"loc\":\"bj\"}"}}]},"finish_reason":"tool_calls"}]}\n\n'

state = {"started": False, "finished": False, "block_idx": 0}
out = []

for line in chunk_text.split("\n"):
    line = line.strip()
    print(f"  line='{line[:80]}'")
    if not line.startswith("data:"):
        print(f"    SKIP (not data:)")
        continue
    payload = line[len("data:"):].strip()
    if not payload:
        print(f"    SKIP (empty payload)")
        continue
    if payload == "[DONE]":
        print(f"    [DONE]")
        continue
    obj = json.loads(payload)
    for choice in obj.get("choices", []):
        print(f"    choice: {choice}")
        delta = choice.get("delta", {})
        _ensure_started(state, out, "msg", "model")
        for tc in delta.get("tool_calls", []):
            print(f"      tool_call: {tc}")
        if choice.get("finish_reason"):
            print(f"      finish_reason: {choice['finish_reason']}")

print("\nout:", out)
print("state:", state)

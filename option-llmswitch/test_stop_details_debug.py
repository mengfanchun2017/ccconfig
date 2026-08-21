#!/usr/bin/env python3
import json
import sys
sys.path.insert(0, ".")
from openai_bridge import openai_chunk_to_anthropic_sse

MSG_ID = "msg_br_test"
MODEL = "deepseek-v4-flash-0731"

chunk = 'data: {"id":"0","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"get_weather","arguments":"{\"loc\":\"bj\"}"}}]},"finish_reason":"tool_calls"}]}\n\n'
state = {}
out = openai_chunk_to_anthropic_sse(chunk, MSG_ID, MODEL, state)
print("=== OUTPUT ===")
print(out[:1000] if out else "None")
print("=== STATE ===")
print(state)

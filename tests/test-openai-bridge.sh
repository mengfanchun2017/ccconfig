#!/bin/bash
# test-openai-bridge.sh — openai_bridge.py 流式链路端到端回归测试
#
# 为什么需要：2026-09 一次"稳定性增强"给流式加 SSE 心跳包装时用了
# asyncio.wait_for(anext())，导致流正常结束时抛 RuntimeError 掐断整条流、
# 中途停顿时 cancel 掉 anext 把后续 chunk 全丢。非流式探测完全发现不了
# （照样返回 HTTP 200），于是"探测 OK 但实际挂"持续了很久。
# 这个测试专门盯住这条链路。
#
# 用法: bash ccconfig/tests/test-openai-bridge.sh [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_PORT=18899
BRIDGE_PORT=8897
# 可注入其它版本便于验证测试自身的有效性
BRIDGE_PY="${BRIDGE_PY:-$CCCONFIG_DIR/option-llmswitch/openai_bridge.py}"
VERBOSE=false
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=true

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0
_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}❌${NC} $1${2:+ — $2}"; }

WORKDIR=$(mktemp -d)
cleanup() {
    [[ -n "${BRIDGE_PID:-}" ]] && kill "$BRIDGE_PID" 2>/dev/null
    [[ -n "${MOCK_PID:-}" ]] && kill "$MOCK_PID" 2>/dev/null
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# ── mock upstream：按 URL 首段模拟 4 种 upstream 行为 ──
cat > "$WORKDIR/mock_up.py" <<'PYEOF'
import sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    disable_nagle_algorithm = True   # 关 Nagle，让小片真的以小片到达（复刻 curl.exe 分片）

    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0) or 0)
        body = self.rfile.read(n)
        mode = self.path.strip('/').split('/')[0]

        # 非流式请求（bridge 的兜底会改发 stream=false）：单独应答
        if b'"stream":false' in body.replace(b' ', b''):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            payload = ('{"id":"1","model":"test-model","choices":[{"index":0,'
                       '"message":{"role":"assistant","content":"Recovered"},'
                       '"finish_reason":"stop"}],"usage":{"prompt_tokens":3,"completion_tokens":2}}')
            self.wfile.write(payload.encode())
            self.wfile.flush()
            return

        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()

        def chunk(txt):
            payload = ('data: {"id":"1","choices":[{"delta":{"content":"%s"},"index":0}]}\n\n' % txt)
            self.wfile.write(payload.encode())
            self.wfile.flush()

        if mode == 'normal':
            chunk('He'); chunk('llo')
            self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
        elif mode == 'stall':
            chunk('A'); time.sleep(3); chunk('B')
            self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
        elif mode == 'truncate':
            chunk('partial')          # 故意不写 [DONE]：模拟流被中途掐断
        elif mode == 'drop':
            pass                      # 立即断开：模拟 upstream 连接失败
        elif mode == 'apierr':
            # 复刻 one-api 类网关的拒绝方式：HTTP 200 + 裸 JSON error（根本不是 SSE）
            self.wfile.write(b'{"error":{"message":"no available channel for model test-model","type":"one_api_error"}}')
            self.wfile.flush()
        elif mode == 'emptystream':
            # 复刻实测内网网关 deepseek-v4.1-flash-outside：流式恒 HTTP 200 + 仅 [DONE]
            self.wfile.write(b'data: [DONE]\n\n')
            self.wfile.flush()
        elif mode == 'sat502':
            # 复刻实测内网网关 502 饱和：HTTP 200 但 body 是裸 JSON 错误体
            #（code=bad_response_status_code），根本不是 SSE
            self.wfile.write(b'{"error":{"message":" (request id: 123)","type":"upstream_error","param":"502","code":"bad_response_status_code"}}')
            self.wfile.flush()
        elif mode == 'frag':
            # 每 7 字节 flush 一次：复刻 curl.exe stdout / httpx aiter_text 的
            # 随机分片边界（实测真实长流每次有 15-29 个切点落在行中间）。
            # 必须 sleep 拉开时间：发太快会被接收端缓冲成整片，跨界就不复现了。
            payload = b''
            for t in ('He', 'llo', 'Wo', 'rld'):
                payload += ('data: {"id":"1","choices":[{"delta":{"content":"%s"},"index":0}]}\n\n' % t).encode()
            payload += b'data: [DONE]\n\n'
            for i in range(0, len(payload), 7):
                self.wfile.write(payload[i:i+7])
                self.wfile.flush()
                time.sleep(0.01)

    def log_message(self, *a):
        pass

HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PYEOF

python3 "$WORKDIR/mock_up.py" "$MOCK_PORT" > /dev/null 2>&1 &
MOCK_PID=$!
sleep 1

start_bridge() {
    local base="$1"
    [[ -n "${BRIDGE_PID:-}" ]] && kill "$BRIDGE_PID" 2>/dev/null
    for p in $(lsof -ti :"$BRIDGE_PORT" 2>/dev/null); do kill "$p" 2>/dev/null; done
    sleep 0.5
    env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
        OPENAI_BRIDGE_UPSTREAM="$base" OPENAI_BRIDGE_KEY="test-key" OPENAI_BRIDGE_MODEL="test-model" \
        python3 "$BRIDGE_PY" --port "$BRIDGE_PORT" \
        > "$WORKDIR/bridge.log" 2>&1 &
    BRIDGE_PID=$!
    for _ in $(seq 1 12); do
        sleep 0.5
        curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" > /dev/null 2>&1 && return 0
    done
    return 1
}

# 发流式 Anthropic 请求，回显 SSE。
# 函数退出码即 curl 退出码：0=连接正常收完，18=传输被中途掐断。
# why 必须看退出码：流被异常终止时，已发出的帧仍可能被 curl 收下，
# 只查内容会漏判（这正是"探测 200 但实际挂"在测试层的翻版）。
request_stream() {
    curl -sN --max-time 45 --noproxy '*' -X POST "http://127.0.0.1:${BRIDGE_PORT}/v1/messages" \
        -H "Content-Type: application/json" -H "anthropic-version: 2023-06-01" \
        -H "Authorization: Bearer test-key" \
        -d '{"model":"test-model","max_tokens":32,"stream":true,"messages":[{"role":"user","content":"hi"}]}' 2>/dev/null
}

# 从 Anthropic SSE 里抽出拼接后的正文
extract_text() {
    grep '^data:' | python3 -c "
import sys, json
buf = ''
for line in sys.stdin:
    line = line[5:].strip()
    if not line or line == '[DONE]':
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get('type') == 'content_block_delta':
        buf += d.get('delta', {}).get('text', '')
print(buf)"
}

echo ""
echo "═══ openai_bridge 流式链路回归测试 ═══"
echo ""

# ── T1: 流正常结束必须完整收完（旧 bug：RuntimeError 掐断连接）──
echo "T1 流正常结束 → 连接正常收完 + 完整 SSE + message_stop"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/normal/v1"; then
    out=$(request_stream); rc=$?
    text=$(printf '%s' "$out" | extract_text)
    if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q 'message_stop' && [[ "$text" == "Hello" ]]; then
        _pass "连接干净收完（curl rc=0），text='$text' + message_stop"
    else
        _fail "流不完整或被掐断" "curl rc=$rc text='$text' message_stop=$(printf '%s' "$out" | grep -c message_stop)"
        $VERBOSE && printf '%s\n' "$out" | head -8 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败" "$(tail -3 "$WORKDIR/bridge.log")"
fi

# ── T2: 中途停顿后数据不能丢（旧 bug：wait_for 超时 cancel 掉 anext）──
echo "T2 upstream 停顿 3s → 前后 chunk 都要收到且连接完整"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/stall/v1"; then
    out=$(request_stream); rc=$?
    text=$(printf '%s' "$out" | extract_text)
    if [[ $rc -eq 0 ]] && [[ "$text" == "AB" ]]; then
        _pass "停顿前后数据无丢失（curl rc=0, text='$text'）"
    else
        _fail "数据丢失或连接异常" "curl rc=$rc 期望 'AB'，实得 '$text'"
        $VERBOSE && printf '%s\n' "$out" | head -10 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败"
fi

# ── T3: 截断流必须显式报错（不能只靠"缺少 message_stop"让人猜）──
echo "T3 upstream 截断（无 [DONE]）→ 显式 error 事件"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/truncate/v1"; then
    out=$(request_stream); rc=$?
    text=$(printf '%s' "$out" | extract_text)
    if printf '%s' "$out" | grep -q '"type":"error"'; then
        _pass "截断被显式报错（已收到 text='$text'）"
    else
        _fail "截断未报错" "test_llm 会漏报此类故障"
        $VERBOSE && printf '%s\n' "$out" | head -6 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败"
fi

# ── T4: upstream 空响应（200 但无 body）→ 快速返回 + 显式报错 ──
echo "T4 upstream 空响应 → 快速返回 + 显式 error，不挂死"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/drop/v1"; then
    start_ts=$(date +%s)
    out=$(request_stream); rc=$?
    elapsed=$(( $(date +%s) - start_ts ))
    if [[ $elapsed -lt 30 ]] && printf '%s' "$out" | grep -q '"type":"error"'; then
        _pass "快速返回（${elapsed}s）并显式报错"
    else
        _fail "未快速报错" "elapsed=${elapsed}s，输出 ${#out} 字节"
        $VERBOSE && printf '%s\n' "$out" | head -6 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败"
fi

# ── T5: /health 不得泄露 API key ──
echo "T5 /health 不得回明文 key"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/normal/v1"; then
    h=$(curl -s --max-time 3 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null)
    if printf '%s' "$h" | grep -q 'test-key'; then
        _fail "/health 泄露了 API key"
    else
        _pass "key 已脱敏（只回 upstream_key_set）"
    fi
else
    _fail "bridge 启动失败"
fi

# ── T6: 碎分片（data: 行被跨片切断）→ 正文与终止标记都不能丢 ──
# 旧 bug：解析器对每个分片独立 split("\n")，片边界落在行中间时，那行不以
# `data:` 开头 → 整行 continue 丢弃。丢 usage 事小，切中 `data: [DONE]` 就把
# 终止标记丢了 → 误报 upstream_incomplete；切中正文则内容静默缺失。
echo "T6 碎分片（7 字节一片）→ 正文完整 + message_stop"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/frag/v1"; then
    out=$(request_stream); rc=$?
    text=$(printf '%s' "$out" | extract_text)
    if [[ "$text" == "HelloWorld" ]] && printf '%s' "$out" | grep -q 'message_stop'; then
        _pass "跨片行已重组（text='$text' + message_stop）"
    else
        _fail "跨片行被丢弃" "期望 'HelloWorld'+message_stop，实得 text='$text' message_stop=$(printf '%s' "$out" | grep -c message_stop)"
        printf '%s' "$out" | grep -q '"type":"error"' && _fail "误报 error（upstream_incomplete 的翻版）"
        $VERBOSE && printf '%s\n' "$out" | head -8 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败"
fi

# ── T7: _iter_complete_lines 直接单测（确定性分片，不依赖 TCP 行为）──
echo "T7 _iter_complete_lines 跨片重组"
t7=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import asyncio, importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

async def main():
    async def gen(pieces):
        for p in pieces: yield p
    # 每行切成三片：断言缓冲能把残行拼回来
    pieces = ['data: {"a"', ':1}\n', 'data: [DO', 'NE]\n', 'data: {"b":2}\n']
    got = [c async for c in m._iter_complete_lines(gen(pieces))]
    want = ['data: {"a":1}\n', 'data: [DONE]\n', 'data: {"b":2}\n']
    if got != want:
        print(f"FAIL: {got!r} != {want!r}"); return 1
    # 无换行尾片不能吞掉
    got2 = [c async for c in m._iter_complete_lines(gen(['abc', 'def']))]
    if got2 != ['abcdef']:
        print(f"FAIL tail: {got2!r}"); return 1
    # 已是完整行时原样通过（不得多加/少加换行）
    got3 = [c async for c in m._iter_complete_lines(gen(['a\nb\n']))]
    if got3 != ['a\n', 'b\n']:
        print(f"FAIL passthrough: {got3!r}"); return 1
    print("OK"); return 0

sys.exit(asyncio.run(main()))
PYEOF
)
[[ "$t7" == "OK" ]] && _pass "跨片重组 / 尾片 / 原样透传 全通过" || _fail "_iter_complete_lines 行为不符" "$t7"

# ── T8: 真实 win_curl 路径（curl.exe stdout 的 read(4096) 边界）──
# T6 走 httpx，分片会被 http.client 对齐到 chunk 边界，跨界难复现；
# win_curl 路径的管道读边界才是真随机的（实测真实长流每次 15-29 个跨界点）。
echo "T8 win_curl 路径跨片重组"
if command -v curl.exe &>/dev/null; then
    t8=$(python3 - "$BRIDGE_PY" "$MOCK_PORT" <<'PYEOF'
import asyncio, importlib.util, json, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
URL = "http://127.0.0.1:%s/frag/v1/chat/completions" % sys.argv[2]
BODY = {"model": "t", "stream": True, "messages": [{"role": "user", "content": "hi"}]}

def scan(parts):
    done, buf = False, ""
    for p in parts:
        for line in p.split("\n"):
            s = line.strip()
            if not s.startswith("data:"):
                continue
            payload = s[5:].strip()
            if payload == "[DONE]":
                done = True
                continue
            try:
                d = json.loads(payload)
                buf += d["choices"][0]["delta"].get("content", "")
            except Exception:
                pass
    return done, buf

async def main():
    raw = []
    async for c in m._stream_via_win_curl(URL, {}, BODY, ""):
        raw.append(c)
    cross = sum(1 for c in raw if not c.endswith("\n"))
    async def gen():
        for c in raw: yield c
    lines = [l async for l in m._iter_complete_lines(gen())]
    r_done, r_text = scan(raw)
    b_done, b_text = scan(lines)
    print("SPLITS=%d CROSS=%d RAW_DONE=%s BUF_DONE=%s BUF_TEXT=%s"
          % (len(raw), cross, r_done, b_done, b_text))

asyncio.run(main())
PYEOF
)
    echo "  $t8"
    cross=$(printf '%s' "$t8" | sed -n 's/.*CROSS=\([0-9]*\).*/\1/p')
    if [[ -z "$t8" ]]; then
        _fail "win_curl 路径测试未产出结果" "模块无 _iter_complete_lines？"
    elif [[ "${cross:-0}" -eq 0 ]]; then
        _fail "未能构造跨界分片" "mock 发送间隔不够，测试无效（不是通过了）"
    elif printf '%s' "$t8" | grep -q 'BUF_DONE=True' && printf '%s' "$t8" | grep -q 'BUF_TEXT=HelloWorld'; then
        _pass "win_curl 跨界 $cross 处 → 缓冲后正文完整 + 终止标记齐全"
    else
        _fail "win_curl 路径跨片丢失" "$t8"
    fi
else
    echo -e "  ${YELLOW}⏭${NC} 跳过（无 curl.exe：非 WSL/Windows 环境）"
fi

# ── T9: 上游 200 + 裸 JSON error → 必须带出上游原文，不能报 upstream_incomplete ──
# one-api 类网关对"模型无可用渠道 / 额度不足"就是 HTTP 200 + 裸 JSON error。
# 旧代码把它当"流被截断"，报 upstream_incomplete → 把人引去查网络/DNS，
# 实际是上游拒绝。真实踩坑：deepseek-v4-pro 在 default 分组无渠道，
# 排查了很久才发现是模型名问题（正确名是 deepseek-v4-pro-outside）。
echo "T9 上游 200 + 裸 JSON error → 报出上游原文"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/apierr/v1"; then
    out=$(request_stream)
    if printf '%s' "$out" | grep -q 'upstream_error' && printf '%s' "$out" | grep -q 'no available channel'; then
        _pass "带出上游原文（upstream_error + message）"
    elif printf '%s' "$out" | grep -q 'upstream_incomplete'; then
        _fail "被误报成 upstream_incomplete" "表现为'网络截断'，实际是上游拒绝"
    else
        _fail "未识别非 SSE 响应" "输出：$(printf '%s' "$out" | head -3 | tr '\n' ' ')"
    fi
else
    _fail "bridge 启动失败"
fi

# ── T10: thinking 参数透传为 reasoning_effort（旧 bug：bridge 把 thinking 丢弃，上游走默认深度）──
# Claude Code 的 extended_thinking → OpenAI 端用 reasoning_effort 三档。
# 按 budget_tokens 离散映射：<8k=低，<20k=中，>=20k=高，缺省预算→高。
# output_config.effort 优先级更高（用户显式 effort 应保留）。
echo "T10 thinking 参数 → reasoning_effort 映射"
t10=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base = {"model": "t", "messages": [], "max_tokens": 100}
basic = [
    ({"type": "enabled", "budget_tokens": 4000},  "low"),
    ({"type": "enabled", "budget_tokens": 10000}, "medium"),
    ({"type": "enabled", "budget_tokens": 25000}, "high"),
    ({"type": "enabled"},                          "high"),
    ({"type": "disabled"},                         None),
    (None,                                         None),
]
fail = []
for thinking, want in basic:
    body = dict(base); body["thinking"] = thinking
    out = m.anthropic_to_openai_req(body, "t")
    got = out.get("reasoning_effort")
    if got != want:
        fail.append(f"thinking={thinking} -> got {got!r}, want {want!r}")
# 优先级: output_config.effort=medium 覆盖 thinking(budget=4000)=low
prio_body = dict(base)
prio_body["thinking"] = {"type": "enabled", "budget_tokens": 4000}
prio_body["output_config"] = {"effort": "medium"}
if m.anthropic_to_openai_req(prio_body, "t").get("reasoning_effort") != "medium":
    fail.append("output_config.effort 没覆盖 thinking 推导值")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t10" == "OK" ]] && _pass "thinking 透传为 reasoning_effort + output_config 优先级" || _fail "thinking 映射不符合预期" "$t10"

# ── T11: thinking 开关（enable_thinking）──
# 别的问题: 只发 reasoning_effort 时单位网关 reasoning_tokens 恒 0（不思考），
# 模型把思路当正文吐出来 → CC 里出现"我现在执行。发送！"式空转。开关另发。
echo "T11 thinking 开关 → enable_thinking"
t11=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fail = []
cases = [
    ({"type": "adaptive", "display": "omitted"}, True),   # CC 2.1.274 实际发的
    ({"type": "enabled", "budget_tokens": 4000}, True),
    ({"type": "disabled"}, False),
    (None, False),
]
for thinking, want in cases:
    body = {"model": "t", "messages": [], "max_tokens": 100, "thinking": thinking}
    got = m.anthropic_to_openai_req(body, "t").get("enable_thinking", False)
    if bool(got) != want:
        fail.append(f"thinking={thinking} -> enable_thinking={got!r}, want {want}")
# adaptive 时也不能丢 effort
body = {"model": "t", "messages": [], "max_tokens": 100,
        "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}
o = m.anthropic_to_openai_req(body, "t")
if o.get("enable_thinking") is not True or o.get("reasoning_effort") != "high":
    fail.append(f"adaptive + effort=high -> {o.get('enable_thinking')!r}/{o.get('reasoning_effort')!r}")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t11" == "OK" ]] && _pass "enable_thinking 随 thinking 开关下发 + effort 并存" || _fail "enable_thinking 映射不符合预期" "$t11"

# ── T12: 同一条响应里文本块与工具块 index 必须不同 ──
# 旧 bug: 文本块硬编码 index 0、工具块也从 block_idx=0 起算 → 一条"先说话再调工具"
# 的响应里两个 content_block_start 都是 index 0。CC 按 index 收尾，把正文块重放/丢弃，
# tool_use 被**执行两次**（界面"输出一段文字后回退再输出"）。
echo "T12 文本块与工具块 index 不撞号"
t12=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, json, re, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
lines = [
    {"id": "1", "choices": [{"index": 0, "delta": {"role": "assistant", "content": "先说一句"}, "finish_reason": None}], "usage": {"prompt_tokens": 42, "completion_tokens": 3}},
    {"id": "1", "choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "id": "call_a", "function": {"name": "Bash", "arguments": '{"command":"ls"}'}}]}, "finish_reason": None}], "usage": {"prompt_tokens": 42, "completion_tokens": 9}},
    {"id": "1", "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}], "usage": {"prompt_tokens": 42, "completion_tokens": 9}},
]
st = {"started": False, "finished": False, "block_idx": 0}
out = ""
for o in lines:
    out += m.openai_chunk_to_anthropic_sse("data: " + json.dumps(o) + "\n", "msg_t", "t", st) or ""
out += m.openai_chunk_to_anthropic_sse("data: [DONE]\n", "msg_t", "t", st) or ""
fail = []
starts = [int(x) for x in re.findall(r'"type":"content_block_start","index":(\d+)', out)]
stops = [int(x) for x in re.findall(r'"type":"content_block_stop","index":(\d+)', out)]
if starts != [0, 1]:
    fail.append(f"block_start 索引序列 {starts} != [0, 1]")
if len(set(starts)) != len(starts):
    fail.append(f"索引重复: {starts}")
if sorted(stops) != [0, 1]:
    fail.append(f"block_stop 索引 {stops} != [0, 1]")
if '"stop_reason":"tool_use"' not in out:
    fail.append("stop_reason 不是 tool_use")
if '"input_tokens":42' not in out:
    fail.append("message_start 未带真 input_tokens")
if st.get("text_idx") != 0:
    fail.append(f"text_idx={st.get('text_idx')} != 0")
if st.get("dup_blocks"):
    fail.append(f"干净流不该有 dup_blocks={st.get('dup_blocks')}")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t12" == "OK" ]] && _pass "文本 index 0 / 工具 index 1，stop 与 input_tokens 正确" || _fail "block index 分配不符合预期" "$t12"

# ── T13: 收尾后重复投递必须丢弃（否则工具再执行一次）──
echo "T13 收尾后重复投递被丢弃"
t13=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, json, re, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
tool = {"id": "1", "choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "id": "call_a", "function": {"name": "Bash", "arguments": '{"command":"ls"}'}}]}, "finish_reason": None}], "usage": {"prompt_tokens": 42, "completion_tokens": 9}}
fin = {"id": "1", "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}], "usage": {"prompt_tokens": 42, "completion_tokens": 9}}
st = {"started": False, "finished": False, "block_idx": 0}
out = ""
for o in (tool, fin):
    out += m.openai_chunk_to_anthropic_sse("data: " + json.dumps(o) + "\n", "msg_t", "t", st) or ""
out += m.openai_chunk_to_anthropic_sse("data: [DONE]\n", "msg_t", "t", st) or ""
first = out
# 上游把整条响应又投递一遍（网关重试/重复投递）
for o in (tool, fin):
    out += m.openai_chunk_to_anthropic_sse("data: " + json.dumps(o) + "\n", "msg_t", "t", st) or ""
out += m.openai_chunk_to_anthropic_sse("data: [DONE]\n", "msg_t", "t", st) or ""
fail = []
if out != first:
    fail.append("重复投递产生了新事件（会重放块/重执行工具）")
if out.count('"type":"message_stop"') != 1:
    fail.append(f"message_stop 出现 {out.count('\"type\":\"message_stop\"')} 次")
if not st.get("dup_blocks"):
    fail.append("未计入 dup_blocks（静默丢弃无法观测）")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t13" == "OK" ]] && _pass "重复投递 0 新事件，仅计 dup_blocks" || _fail "重复投递未被丢弃" "$t13"

# ── T14: 上游显式 null 字段容错（mimo 会发 "tool_calls":null / "reasoning_content":null）──
echo "T14 上游显式 null 字段不崩"
t14=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# mimo 首个 chunk 特征：delta 里 tool_calls / reasoning_content 显式 null
chunks = [
    {"id": "1", "choices": [{"index": 0, "delta": {"content": "", "role": "assistant", "tool_calls": None, "reasoning_content": None}, "finish_reason": None}], "usage": None},
    {"id": "1", "choices": [{"index": 0, "delta": {"content": "你好", "tool_calls": None}, "finish_reason": None}]},
    {"id": "1", "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
]
st = {"started": False, "finished": False, "block_idx": 0}
out = ""
try:
    for c in chunks:
        out += m.openai_chunk_to_anthropic_sse("data: " + json.dumps(c) + "\n", "msg_n", "t", st) or ""
    out += m.openai_chunk_to_anthropic_sse("data: [DONE]\n", "msg_n", "t", st) or ""
except Exception as e:
    print(f"FAIL: 抛异常 {type(e).__name__}: {e}"); sys.exit(1)
fail = []
# 正文被 json.dumps 转义（\uXXXX），用转义形式匹配，别用原字面量
if json.dumps("你好")[1:-1] not in out:
    fail.append("正文丢失")
if out.count('"type":"message_stop"') != 1:
    fail.append("缺 message_stop")
if st.get("stop_reason") != "end_turn":
    fail.append(f"stop_reason={st.get('stop_reason')}")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t14" == "OK" ]] && _pass "null 字段容错，正文 + 收尾正常" || _fail "null 字段导致崩溃/丢内容" "$t14"

# ── T15: 服务端 web search 工具剔除（OpenAI 上游不支持，转 function 会 400）──
echo "T15 服务端 web search 工具剔除"
t15=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
body = {"model": "x", "max_tokens": 10, "messages": [{"role": "user", "content": "q"}],
        "tools": [{"type": "web_search_20250305", "name": "web_search", "max_uses": 8},
                  {"name": "Read", "input_schema": {"type": "object", "properties": {}}}],
        "tool_choice": {"type": "auto"}}
fail = []
if not m._is_websearch_tool(body["tools"][0]):
    fail.append("未识别服务端搜索工具")
out = m.anthropic_to_openai_req(body, "deepseek")
if any(t.get("type") == "web_search" for t in (out.get("tools") or [])):
    fail.append("未剔除搜索工具")
if not out.get("tool_choice"):
    fail.append("剩余为普通工具时应透传 tool_choice")
# 只剩搜索工具时，tools 键不应出现
only = {"model": "x", "max_tokens": 10, "messages": [{"role": "user", "content": "q"}],
        "tools": [{"type": "web_search_20250305", "name": "web_search"}]}
o_only = m.anthropic_to_openai_req(only, "m")
if "tools" in o_only:
    fail.append("仅搜索工具时仍带空 tools 键")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t15" == "OK" ]] && _pass "搜索工具剔除 / tool_choice 透传 / 空 tools 键" || _fail "web search 工具剔除错误" "$t15"

# ── T16: 图片消息转 OpenAI content 数组（str join 曾把 image_url dict 静默丢掉）──
echo "T16 图片消息 content 数组不丢"
t16=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
body = {"model": "x", "max_tokens": 10, "messages": [
    {"role": "user", "content": [
        {"type": "text", "text": "看图"},
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": "AAAA"}},
    ]}]}
fail = []
out = m.anthropic_to_openai_req(body, "m")
c = out["messages"][0]["content"]
if not (isinstance(c, list) and any(seg.get("type") == "image_url" for seg in c)):
    fail.append(f"image 段丢失: {c!r}")
if not any(seg.get("type") == "text" and "看图" in seg.get("text", "") for seg in c):
    fail.append("text 段丢失")
# 纯文本仍走 str
plain = {"model": "x", "max_tokens": 10, "messages": [
    {"role": "user", "content": [{"type": "text", "text": "hi"}]}]}
if out := m.anthropic_to_openai_req(plain, "m"):
    if not isinstance(out["messages"][0]["content"], str):
        fail.append("纯文本应保持 str content")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t16" == "OK" ]] && _pass "image 数组 / text 保留 / 纯文本 str" || _fail "image content 转换" "$t16"

# ── T17: tool_choice any→required；tools 全被剔除时不发 tool_choice ──
echo "T17 tool_choice 映射与空 tools 抑制"
t17=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fail = []
b1 = {"model": "x", "max_tokens": 10, "messages": [{"role": "user", "content": "q"}],
      "tools": [{"name": "Read", "input_schema": {"type": "object"}}],
      "tool_choice": {"type": "any"}}
o1 = m.anthropic_to_openai_req(b1, "m")
if o1.get("tool_choice") != "required":
    fail.append(f"any 未映射 required: {o1.get('tool_choice')!r}")
b2 = {"model": "x", "max_tokens": 10, "messages": [{"role": "user", "content": "q"}],
      "tools": [{"type": "web_search_20250305", "name": "web_search"}],
      "tool_choice": {"type": "any"}}
o2 = m.anthropic_to_openai_req(b2, "m")
if "tool_choice" in o2:
    fail.append("tools 全剔除后仍带 tool_choice")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t17" == "OK" ]] && _pass "any→required / 空 tools 抑制" || _fail "tool_choice 处理" "$t17"

# ── T18: 非流式 finish_reason 全映射 + 坏 arguments 不 500 ──
echo "T18 非流式 finish 映射 + 坏 arguments 守卫"
t18=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fail = []
r = m.openai_to_anthropic_resp({"choices": [{"finish_reason": "length", "message": {}}]})
if r["stop_reason"] != "max_tokens":
    fail.append(f"length→{r['stop_reason']!r} 应 max_tokens")
r = m.openai_to_anthropic_resp({"choices": [{"finish_reason": "content_filter", "message": {}}]})
if r["stop_reason"] != "content_filtered":
    fail.append(f"content_filter→{r['stop_reason']!r}")
try:
    r = m.openai_to_anthropic_resp({"choices": [{"finish_reason": "tool_calls", "message": {
        "tool_calls": [{"id": "t1", "function": {"name": "Read", "arguments": "not-json{"}}]}}]})
except Exception as e:
    fail.append(f"坏 arguments 抛异常: {e}")
else:
    if r["content"][0].get("input", {}).get("_raw") is None:
        fail.append(f"坏 arguments 未落 _raw: {r['content'][0]!r}")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t18" == "OK" ]] && _pass "finish 全映射 / 坏 arguments 落 _raw" || _fail "非流式转换" "$t18"

# ── T19: _finalize_sse —— finish_reason 后无 [DONE] 的收尾兜底 ──
echo "T19 缺 [DONE] 收尾兜底"
t19=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fail = []
# finish_reason 到达但流直接结束（无 [DONE]）→ finalize 补 message_delta+message_stop
st = {"started": False, "finished": False, "block_idx": 0, "stop_reason": "tool_use",
      "output_tokens": 7, "input_tokens": 31}
chunk = 'data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}\n'
m.openai_chunk_to_anthropic_sse(chunk, "id", "m", st)  # 触发 finished=True（块收尾）
if not st.get("stopped"):
    out = m._finalize_sse(st)
    if "message_delta" not in out or "message_stop" not in out:
        fail.append(f"finalize 输出缺事件: {out[:80]!r}")
    if '"input_tokens":31' not in out:
        fail.append("finalize 未带真 input_tokens")
if m._finalize_sse(st) != "":
    fail.append("重复 finalize 应返回空串")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t19" == "OK" ]] && _pass "补 message_delta+message_stop / 幂等 / input_tokens" || _fail "缺 [DONE] 收尾兜底" "$t19"

# ── T20: 上游空流（仅 [DONE]）→ 回落非流式兜底，不能把空回复甩给 CC ──
# 2026-10-30 实测：内网网关 deepseek-v4.1-flash-outside 流式恒 HTTP 200 + 仅
# data: [DONE]，零内容块；非流式正常返回完整正文。旧版 bridge 有「零内容块 →
# 回落非流式」兜底，10-30 10:53 的提交把它连同 pending 帧机制一起删了 →
# outside 预设直接空回复（CC 侧表现为「输入后即停」）。
echo "T20 上游空流（仅 [DONE]）→ 回落非流式，正文不为空"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/emptystream/v1"; then
    out=$(request_stream); rc=$?
    text=$(printf '%s' "$out" | extract_text)
    if [[ "$text" == "Recovered" ]] && printf '%s' "$out" | grep -q 'message_stop'; then
        _pass "空流已回落非流式（text='$text' + message_stop）"
    else
        _fail "空流未兜底" "期望 text='Recovered'，实得 '$text'（curl rc=$rc）"
        $VERBOSE && printf '%s\n' "$out" | head -8 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败"
fi

# ── T21: 上游 502 饱和（裸 JSON 错误体，非 SSE）→ 回落非流式重试 ──
# 2026-10-30 实测：内网网关 deepseek-v4.1-flash 走网关间歇回裸 JSON 错误体
# （code=bad_response_status_code，HTTP 200），bridge 按「非 SSE body」判为
# upstream_error 直接甩给 CC → 表现为随机失败/「输入后即停」。
# 兜底必须把它转成可用的非流式结果，而不是直接报错。
echo "T21 上游 502 饱和（裸 JSON 错误体）→ 回落非流式，不直接报错"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/sat502/v1"; then
    out=$(request_stream); rc=$?
    text=$(printf '%s' "$out" | extract_text)
    if [[ "$text" == "Recovered" ]] && ! printf '%s' "$out" | grep -q '"type":"error"'; then
        _pass "502 已回落非流式（text='$text'，无 error 事件）"
    else
        _fail "502 未兜底" "期望 text='Recovered' 无 error，实得 '$text'"
        $VERBOSE && printf '%s\n' "$out" | head -8 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败"
fi

# ── T22: preset 级 reasoning_effort 是「默认档」而非「强制覆盖」 ──
# 2026-10-30 实测：单位网关完全忽略 reasoning_effort（24 次配对采样，三组
# 思考率 95%/95%/95% 无差异）。旧实现取最高优先级 → 客户端 /effort 设定被
# 吃掉，「思考开/关两种情况都要能工作」被破坏。改为默认档后，客户端显式
# 设定优先，客户端没表态时才用 preset 值。
echo "T22 preset reasoning_effort = 默认档（客户端显式设定优先）"
t22=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fail = []
m.state["reasoning_effort_override"] = "none"
# 客户端显式 effort=high → 应保留 high（不被 preset 的 none 覆盖）
b = m.anthropic_to_openai_req(
    {"model": "x", "max_tokens": 100, "messages": [],
     "thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}}, "m")
if b.get("reasoning_effort") != "high":
    fail.append(f"客户端 effort=high 被 preset 覆盖成 {b.get('reasoning_effort')!r}")
# 客户端没表态 → 用 preset 默认档 none
b2 = m.anthropic_to_openai_req({"model": "x", "max_tokens": 100, "messages": []}, "m")
if b2.get("reasoning_effort") != "none":
    fail.append(f"客户端未表态时应取 preset 默认档，实际 {b2.get('reasoning_effort')!r}")
# 无 preset 覆盖 → 不注入该字段
m.state["reasoning_effort_override"] = ""
b3 = m.anthropic_to_openai_req({"model": "x", "max_tokens": 100, "messages": []}, "m")
if "reasoning_effort" in b3:
    fail.append("无 preset 覆盖时不应注入 reasoning_effort")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t22" == "OK" ]] && _pass "客户端设定优先 / preset 仅作默认档 / 无覆盖不注入" || _fail "preset 档位语义" "$t22"

# ── T23: 双路由 —— 客户端关思考时走不思考路由 ──
# 2026-10-30 实测：单位网关完全忽略 reasoning_effort / enable_thinking，发参数
# 关不掉思考；唯一有效的是换路由（xf-deepseek-v4-flash-waiwang 实测 rt 恒 0、
# 工具 3/3、12/12 稳定）。故 preset 配 model_no_think，bridge 按客户端 thinking
# 开关选路由：关思考 → 不思考路由（且不发思考参数）；要思考 → 主模型。
echo "T23 双路由：关思考走 no_think 路由 + 不发思考参数"
t23=$(python3 - "$BRIDGE_PY" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ob", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fail = []
m.state["upstream_model"] = "think-model"
m.state["upstream_model_no_think"] = "nothink-model"
# 客户端要思考 → allow_thinking=True，且模型是主模型
if not m._client_wants_thinking({"thinking": {"type": "adaptive"}}):
    fail.append("adaptive 应判为要思考")
if not m._client_wants_thinking({"thinking": {"type": "enabled", "budget_tokens": 100}}):
    fail.append("enabled 应判为要思考")
if m._client_wants_thinking({"thinking": {"type": "disabled"}}):
    fail.append("disabled 应判为不要思考")
if m._client_wants_thinking({}):
    fail.append("无 thinking 字段应判为不要思考")
# 不思考路由时一个思考参数都不发
b = m.anthropic_to_openai_req(
    {"model": "x", "max_tokens": 100, "messages": [],
     "thinking": {"type": "disabled"}}, "nothink-model", allow_thinking=False)
if "enable_thinking" in b or "reasoning_effort" in b:
    fail.append(f"不思考路由仍发了思考参数: {b.get('enable_thinking')}/{b.get('reasoning_effort')}")
# 不思考路由的模型名要落到请求体
if b.get("model") != "nothink-model":
    fail.append(f"model 未透传: {b.get('model')!r}")
print("OK" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(0 if not fail else 1)
PYEOF
)
[[ "$t23" == "OK" ]] && _pass "thinking 开关判定 / 不思考路由不发思考参数 / model 透传" || _fail "双路由选择" "$t23"

echo ""
echo "───────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}全部通过${NC} ($PASS)"
else
    echo -e "${RED}$FAIL 项失败${NC} / $PASS 项通过"
fi
echo ""
exit $(( FAIL > 0 ? 1 : 0 ))

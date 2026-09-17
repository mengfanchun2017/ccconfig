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
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0) or 0)
        self.rfile.read(n)
        mode = self.path.strip('/').split('/')[0]
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
        python3 "$CCCONFIG_DIR/option-llmswitch/openai_bridge.py" --port "$BRIDGE_PORT" \
        > "$WORKDIR/bridge.log" 2>&1 &
    BRIDGE_PID=$!
    for _ in $(seq 1 12); do
        sleep 0.5
        curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" > /dev/null 2>&1 && return 0
    done
    return 1
}

# 发一个流式 Anthropic 请求，回显 SSE
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

# ── T1: 流正常结束必须发 message_stop（旧 bug：RuntimeError 掐断整条流）──
echo "T1 流正常结束 → 完整 SSE + message_stop"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/normal/v1"; then
    out=$(request_stream)
    text=$(printf '%s' "$out" | extract_text)
    if printf '%s' "$out" | grep -q 'message_stop' && [[ "$text" == "Hello" ]]; then
        _pass "收到完整流（text='$text' + message_stop）"
    else
        _fail "流不完整" "text='$text' message_stop=$(printf '%s' "$out" | grep -c message_stop)"
        $VERBOSE && printf '%s\n' "$out" | head -8 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败" "$(tail -3 "$WORKDIR/bridge.log")"
fi

# ── T2: 中途停顿后数据不能丢（旧 bug：wait_for 超时 cancel 掉 anext）──
echo "T2 upstream 停顿 3s → 前后 chunk 都要收到"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/stall/v1"; then
    out=$(request_stream)
    text=$(printf '%s' "$out" | extract_text)
    if [[ "$text" == "AB" ]]; then
        _pass "停顿前后数据无丢失（text='$text'）"
    else
        _fail "数据丢失" "期望 'AB'，实得 '$text'"
        $VERBOSE && printf '%s\n' "$out" | head -10 | sed 's/^/      /'
    fi
else
    _fail "bridge 启动失败"
fi

# ── T3: 截断流必须显式报错（不能只靠"缺少 message_stop"让人猜）──
echo "T3 upstream 截断（无 [DONE]）→ 显式 error 事件"
if start_bridge "http://127.0.0.1:${MOCK_PORT}/truncate/v1"; then
    out=$(request_stream)
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
    out=$(request_stream)
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

echo ""
echo "───────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}全部通过${NC} ($PASS)"
else
    echo -e "${RED}$FAIL 项失败${NC} / $PASS 项通过"
fi
echo ""
exit $(( FAIL > 0 ? 1 : 0 ))

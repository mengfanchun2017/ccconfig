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

echo ""
echo "───────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}全部通过${NC} ($PASS)"
else
    echo -e "${RED}$FAIL 项失败${NC} / $PASS 项通过"
fi
echo ""
exit $(( FAIL > 0 ? 1 : 0 ))

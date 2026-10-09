#!/bin/bash
# test-init-llm-switch.sh — switch_llm 写出 settings.json 的端到端回归测试
#
# 防的是什么：test_llm 里 `IFS='|' read -r base_url ...` 漏了 local，bash 动态
# 作用域下会改写调用者 switch_llm 的同名变量，把已设好的 bridge 地址
# (127.0.0.1:PORT) 覆盖回上游地址 → settings.json 写成 OpenAI 端点直连 →
# Claude Code 拿它当 Anthropic 端点用，报 SSL hostname mismatch / 直接挂。
#
# 三层配置（ADR-LLM3L）：llmnormal(内置定义) + llmprivate(自定义定义) + llm.json(纯 key)
# 本测试用隔离目录模拟三层文件，source init-llm.sh 后验证：
#   - 三个文件路径都指向测试隔离位置（不碰真实配置）
#   - switch_llm 正确合并读取三层 + 只写纯 key 文件 + settings.json BASE_URL
#
# 用法: bash ccconfig/tests/test-init-llm-switch.sh [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_PORT=18897
TEST_BRIDGE_PORT=8896
VERBOSE=false
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=true

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}❌${NC} $1${2:+ — $2}"; }

WORKDIR=$(mktemp -d)
cleanup() {
    [[ -n "${MOCK_PID:-}" ]] && kill "$MOCK_PID" 2>/dev/null
    for p in $(lsof -ti :"$TEST_BRIDGE_PORT" 2>/dev/null); do kill "$p" 2>/dev/null; done
    # pattern 用 [g] 避开 pgrep -f 匹配到执行本脚本的 shell 自身
    for p in $(pgrep -f "bridge-watchdog[^ ]*$WORKDIR" 2>/dev/null); do [[ "$p" == "$$" ]] && continue; kill "$p" 2>/dev/null; done
    rm -rf "$WORKDIR" "$TEST_HOME/.cache" 2>/dev/null
}
trap cleanup EXIT

# ── mock upstream：返回标准 OpenAI SSE（含 [DONE]）──
cat > "$WORKDIR/mock_up.py" <<'PYEOF'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0) or 0))
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        if '/messages' in self.path:
            # Anthropic 格式（直连 preset 探测用）
            self.wfile.write(b'event: message_start\ndata: {"type":"message_start","message":{"id":"m","content":[],"usage":{"input_tokens":1,"output_tokens":1}}}\n\n')
            self.wfile.write(b'event: message_stop\ndata: {"type":"message_stop"}\n\n')
        else:
            # OpenAI 格式（bridge upstream 用）
            self.wfile.write(b'data: {"id":"1","choices":[{"delta":{"content":"ok"},"index":0}]}\n\n')
            self.wfile.write(b'data: [DONE]\n\n')
        self.wfile.flush()

    def log_message(self, *a):
        pass

HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PYEOF

# 清掉上次异常退出残留、占着同端口的 mock —— 否则新 mock 绑不上端口，
# 请求会落到旧进程上（行为不同），表现为莫名其妙的失败
for p in $(lsof -ti :"$MOCK_PORT" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
for p in $(lsof -ti :"$TEST_BRIDGE_PORT" 2>/dev/null); do kill "$p" 2>/dev/null; done
sleep 0.5

python3 "$WORKDIR/mock_up.py" "$MOCK_PORT" > /dev/null 2>&1 &
MOCK_PID=$!
sleep 1

# 自检：mock 必须两个路径都按预期返回，否则后续断言全无意义
if ! curl -s --max-time 3 -X POST "http://localhost:${MOCK_PORT}/anthropic/v1/messages" -d '{}' 2>/dev/null | grep -q 'message_stop'; then
    _fail "mock upstream 未按预期响应（Anthropic 路径）" "端口 $MOCK_PORT 可能被占用"
    exit 1
fi

# ── 隔离环境（HOME + CCPRIVATE_DIR 都在临时目录，绝不碰真实的）──
TEST_HOME="$WORKDIR/home"
mkdir -p "$TEST_HOME/.claude" "$WORKDIR/conf"

# 三层配置：llmnormal（ccconfig 内置，模拟）/ llmprivate（自定义）/ llm.json（纯 key）
# direct = 内置 Anthropic 直连；bridge-preset = 自定义走 bridge
cat > "$WORKDIR/conf/llmnormal.json" <<JSON
{
  "llms": {
    "direct": {
      "name": "Direct",
      "base_url": "http://localhost:${MOCK_PORT}/anthropic",
      "model": "model-d1",
      "small_model": "model-d1"
    }
  }
}
JSON

cat > "$WORKDIR/conf/llmprivate.json" <<JSON
{
  "llms": {
    "bridge-preset": {
      "name": "Bridge",
      "base_url": "http://localhost:${MOCK_PORT}/v1",
      "model": "model-b1",
      "small_model": "model-b1",
      "use_bridge": true
    },
    "ctx-preset": {
      "name": "Ctx",
      "base_url": "http://localhost:${MOCK_PORT}/anthropic",
      "model": "model-c1",
      "small_model": "model-c1",
      "max_context_tokens": 262144
    }
  }
}
JSON

# 纯 key：不写 current（ADR-0020 归本机 llm-current），定义字段绝不混入
cat > "$WORKDIR/conf/llm.json" <<JSON
{
  "llms": {
    "direct": { "key": "sk-test-direct" },
    "bridge-preset": { "key": "sk-test-bridge" },
    "ctx-preset": { "key": "sk-test-ctx" }
  }
}
JSON

cat > "$TEST_HOME/.claude/settings.json" <<'JSON'
{"env": {}, "model": ""}
JSON

echo ""
echo "═══ switch_llm 写出 settings.json 回归测试（三层 LLM 配置）═══"
echo "  mock upstream: localhost:$MOCK_PORT   测试 bridge 端口: $TEST_BRIDGE_PORT"
echo "  隔离 HOME: $TEST_HOME"
echo ""

# ── source init-llm.sh（TEST_MODE=1 跳过 main）──
# 换 HOME 前保存真实 user site：openai_bridge.py 依赖 httpx，它装在真实
# HOME 的 ~/.local/lib 下，只换 HOME 会让 bridge 因 ModuleNotFoundError 起不来
REAL_HOME="${HOME}"
REAL_USER_SITE="$(python3 -c 'import site; print(site.getusersitepackages())' 2>/dev/null \
    || echo "$REAL_HOME/.local/lib/python3.12/site-packages")"

export HOME="$TEST_HOME"
export PYTHONPATH="${REAL_USER_SITE}${PYTHONPATH:+:$PYTHONPATH}"
# 注意：resolve_conf 会自行拼 /conf/，所以这里给 ccprivate 根目录而非 conf 目录
export CCPRIVATE_DIR="$WORKDIR"
export LLM_NORMAL_FILE="$WORKDIR/conf/llmnormal.json"
export LLM_PRIVATE_FILE="$WORKDIR/conf/llmprivate.json"
export LLM_KEYS_FILE="$WORKDIR/conf/llm.json"
export LLM_MERGED_CACHE="$WORKDIR/llm-merged.json"
export TEST_MODE=1
cd "$CCCONFIG_DIR" || exit 1

# shellcheck disable=SC1091
if ! source lib/init-llm.sh > "$WORKDIR/source.log" 2>&1; then
    _fail "source init-llm.sh 失败"
    sed 's/^/      /' "$WORKDIR/source.log" | tail -10
    exit 1
fi

# 覆盖为测试用端口/路径，确保不与生产 bridge 冲突
BRIDGE_PORT="$TEST_BRIDGE_PORT"
BRIDGE_WD_PID="$TEST_HOME/bridge-watchdog.pid"
BRIDGE_WD_LOG="$TEST_HOME/bridge-watchdog.log"

# ── T0: 三个文件路径都已隔离到测试目录 ──
echo "T0 三层文件路径必须指向隔离测试目录"
if [[ "$LLM_KEYS_FILE" == "$WORKDIR/conf/llm.json" && \
      "$LLM_NORMAL_FILE" == "$WORKDIR/conf/llmnormal.json" && \
      "$LLM_PRIVATE_FILE" == "$WORKDIR/conf/llmprivate.json" ]]; then
    _pass "三层文件隔离就绪 (KEYS=$LLM_KEYS_FILE)"
else
    _fail "三层文件未隔离" "got KEYS=$LLM_KEYS_FILE NORMAL=$LLM_NORMAL_FILE PRIV=$LLM_PRIVATE_FILE"
    exit 1
fi

# ── T1: bridge preset 切换 → BASE_URL 必须是 bridge 地址 ──
echo "T1 bridge preset → settings.json 的 BASE_URL 应是 http://127.0.0.1:$TEST_BRIDGE_PORT"
switch_llm "bridge-preset" > "$WORKDIR/switch.log" 2>&1
switch_rc=$?

if [[ $switch_rc -ne 0 ]]; then
    _fail "switch_llm 返回 $switch_rc" "见日志"
    $VERBOSE && sed 's/^/      /' "$WORKDIR/switch.log" | tail -20
else
    written=$(python3 -c "
import json
print(json.load(open('$TEST_HOME/.claude/settings.json')).get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
    expect="http://127.0.0.1:${TEST_BRIDGE_PORT}"
    if [[ "$written" == "$expect" ]]; then
        _pass "BASE_URL 正确 = $written"
    elif [[ "$written" == "http://localhost:${MOCK_PORT}/v1" ]]; then
        _fail "BASE_URL 被写成了上游地址（动态作用域污染 bug 复现）" "got=$written"
    else
        _fail "BASE_URL 不符合预期" "got='$written' expected='$expect'"
    fi
    $VERBOSE && sed 's/^/      /' "$WORKDIR/switch.log" | tail -15
fi

# ── T2: 直连 preset 切换 → BASE_URL 保持原始上游 URL（不得串成 bridge 地址）──
echo "T2 direct preset → settings.json 的 BASE_URL 应是原始上游 URL"
switch_llm "direct" > "$WORKDIR/switch2.log" 2>&1
switch2_rc=$?
written2=$(python3 -c "
import json
print(json.load(open('$TEST_HOME/.claude/settings.json')).get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
expect2="http://localhost:${MOCK_PORT}/anthropic"

if [[ "$written2" == "$expect2" ]]; then
    _pass "BASE_URL 正确 = $written2（直连未被误改成 bridge 地址）"
elif [[ "$written2" == "http://127.0.0.1:${TEST_BRIDGE_PORT}" ]]; then
    _fail "直连 preset 被误写成 bridge 地址" "got=$written2"
else
    _fail "BASE_URL 不符合预期" "rc=$switch2_rc got='$written2' expected='$expect2'"
    $VERBOSE && sed 's/^/      /' "$WORKDIR/switch2.log" | tail -12
fi

# ── T3: llm-current 跟随 ──
echo "T3 llm-current 应记录切换结果"
cur=$(cat "$TEST_HOME/.claude/llm-current" 2>/dev/null || echo "")
if [[ -n "$cur" ]]; then
    _pass "llm-current = $cur"
else
    _fail "llm-current 未写入"
fi

# ── T4: 切换不应反复改写 llm.json（纯 key）──
# why mtime 而非内容：auto-sync 用 inotify 监听写事件，内容相同但重写文件照样
# 触发 30s debounce + pull/push 网络往返，且 A 机写出的内容会 push 给 B 机
echo "T4 切换不应反复改写 llm.json（防 auto-sync 频繁触发）"
switch_llm "bridge-preset" > /dev/null 2>&1   # 首次可能写 key（一次性）
before=$(stat -c %y "$LLM_KEYS_FILE")
switch_llm "direct" > /dev/null 2>&1
after=$(stat -c %y "$LLM_KEYS_FILE")
if [[ "$before" == "$after" ]]; then
    _pass "llm.json 未被改写（mtime 不变）"
else
    _fail "llm.json 被改写 → 触发 inotify → auto-sync 全仓同步" "before=$before after=$after"
fi

# ── T5: 本机选择不得留在共享 llm.json 里；定义文件不得被 key 污染 ──
echo "T5 三层分离：llm.json 无 current/无定义字段；llmnormal/llmprivate 无 key"
if python3 -c "
import json
for p, bad in [('$LLM_KEYS_FILE','current'),('$LLM_NORMAL_FILE','key'),('$LLM_PRIVATE_FILE','key')]:
    d = json.load(open(p))
    if bad == 'current':
        assert 'current' not in d, 'llm.json 含 current'
    else:
        for n, c in d.get('llms', {}).items():
            assert 'key' not in c, f'{n} 含 key'
print('ok')" 2>/dev/null; then
    _pass "三层未互相污染"
else
    _fail "三层结构被破坏（key/current/定义混入）"
fi

# ── T6: 内置预设（llmnormal，_src=normal）删除必须被拒绝 ──
echo "T6 内置预设不可删：delete_preset 拒绝 direct 且文件未变"
before_files="$(md5sum "$LLM_NORMAL_FILE" "$LLM_PRIVATE_FILE" "$LLM_KEYS_FILE")"
if delete_preset "direct" >/dev/null 2>&1; then
    _fail "内置预设 'direct' 被删除（应拒绝）"
else
    after_files="$(md5sum "$LLM_NORMAL_FILE" "$LLM_PRIVATE_FILE" "$LLM_KEYS_FILE")"
    if [[ "$before_files" == "$after_files" ]]; then
        _pass "内置预设删除被拒绝，且三文件未动"
    else
        _fail "拒绝时仍改写了文件"
    fi
fi

# ── T7: list_llms 输出列契约（8 列）──
# why：菜单渲染、删除过滤、key 更新菜单全靠按列位 read。少一个变量时 read 会把
# 多余字段并进最后一个变量（is_builtin 拿到 "1|1"），过滤静默失效 —— 内置预设
# 会混进「可删除的模型」。列数变了必须同步所有 read 端，用本测试兜住。
echo "T7 list_llms 每行 8 列，is_builtin/has_key 均为 0/1"
python3 - "$LLM_KEYS_FILE" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d.setdefault('llms', {})['direct'] = {'key': '请填入你的测试 Key'}
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
PYEOF
t7_res=$(list_llms | python3 -c "
import sys
rows = 0; bad = []; builtin_seen = False; nokey_seen = False
for ln in sys.stdin.read().splitlines():
    if not ln or ln.startswith('TOTAL:') or ln.startswith('CURRENT:'): continue
    f = ln.split('|')
    if len(f) != 8: bad.append('cols=%d' % len(f)); continue
    rows += 1
    if f[6] not in ('0', '1'): bad.append('is_builtin=' + f[6])
    if f[7] not in ('0', '1'): bad.append('has_key=' + f[7])
    if f[6] == '1': builtin_seen = True
    if f[7] == '0': nokey_seen = True
print('ROWS=%d BUILTIN=%s NOKEY=%s BAD=%s' % (rows, builtin_seen, nokey_seen, bad[:3]))
")
if [[ "$t7_res" == *"BAD=[]"* && "$t7_res" == *"BUILTIN=True"* && "$t7_res" == *"NOKEY=True"* ]]; then
    _pass "list_llms 列契约成立（$t7_res）"
else
    _fail "list_llms 列契约被破坏" "got: $t7_res"
fi

# ── T8: max_context_tokens → CLAUDE_CODE_MAX_CONTEXT_TOKENS（按预设写入/移除）──
# why：窗口 env 全局生效。声明了窗口的 preset 切换后必须写入；切到未声明的 preset
# 必须移除，否则把上一个 preset 的窗口假设带过来。
echo "T8 max_context_tokens 按预设写入/移除 CLAUDE_CODE_MAX_CONTEXT_TOKENS"
switch_llm "ctx-preset" > /dev/null 2>&1
ctx_written=$(python3 -c "
import json
print(json.load(open('$TEST_HOME/.claude/settings.json')).get('env',{}).get('CLAUDE_CODE_MAX_CONTEXT_TOKENS',''))" 2>/dev/null)
switch_llm "direct" > /dev/null 2>&1
ctx_after=$(python3 -c "
import json
print(json.load(open('$TEST_HOME/.claude/settings.json')).get('env',{}).get('CLAUDE_CODE_MAX_CONTEXT_TOKENS','<missing>'))" 2>/dev/null)
if [[ "$ctx_written" == "262144" && "$ctx_after" == "<missing>" ]]; then
    _pass "窗口按预设写入(262144)并在切走后移除"
else
    _fail "窗口 env 写入/移除不符合预期" "written='$ctx_written' after='$ctx_after'"
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
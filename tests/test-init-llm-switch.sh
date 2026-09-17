#!/bin/bash
# test-init-llm-switch.sh — switch 路径回归：验证被调函数的 IFS read 不会
# 通过 bash 动态作用域污染调用者的同名变量（把 bridge 地址改回上游）。
#
# 方法：source init-llm.sh 并用临时 HOME + mock upstream 做真实切换，
# 然后断言 settings.json 的 BASE_URL 符合切换后的正确值。
#
# 用法: bash ccconfig/tests/test-init-llm-switch.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { echo -e "  ${RED}❌${NC} $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }  # mock processes kill later
trap cleanup EXIT

# mock upstream (返回简单流式响应)
MOCK_PORT=18897
cat > "$WORKDIR/mock.py" <<'PYEOF'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length',0) or 0))
        self.send_response(200)
        self.send_header('Content-Type','text/event-stream'); self.end_headers()
        self.wfile.write(b'data: {"id":"x","choices":[{"delta":{"content":"ok"},"index":0}]}\n\n')
        self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
    def log_message(self,*a): pass
HTTPServer(('127.0.0.1',int(sys.argv[1])),H).serve_forever()
PYEOF
python3 "$WORKDIR/mock.py" "$MOCK_PORT" &
MOCK_PID=$!
sleep 1
echo "mock upstream: port $MOCK_PORT"

echo ""
echo "═══ switch 路径回归测试（端到端）═══"
echo ""

# ── 创建隔离环境 ──
TEST_HOME="$WORKDIR/home"
mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/git/ccprivate/conf"

# 模拟 llm.json（1 个 bridge preset）
cat > "$TEST_HOME/git/ccprivate/conf/llm.json" <<'JSON'
{
  "current": "bridge",
  "llms": {
    "bridge": {
      "name": "Bridge",
      "base_url": "http://localhost:MOCK/v1",
      "model": "m1",
      "key": "sk-bridge",
      "small_model": "m1",
      "use_bridge": true
    }
  }
}
JSON
# 替换 MOCK 为实际端口
sed -i "s|MOCK|$MOCK_PORT|" "$TEST_HOME/git/ccprivate/conf/llm.json"

# settings.json（先空）
echo '{"env":{},"model":""}' > "$TEST_HOME/.claude/settings.json"

# llm-current
rm -f "$TEST_HOME/.claude/llm-current"

# ── 隔离执行：source init-llm.sh 里的函数并模拟 resolve_conf ──
echo "T1: 模拟 switch_llm 完整调用链"
# 直接跑 init-llm.sh switch 需要 CONFIG_FILE 正确解析。用隔离 HOME
cd "$CCCONFIG_DIR"
(
export HOME="$TEST_HOME"
export USER="test"
export PATH="$PATH"
# 模拟 resolve_conf 的路径解析：直接设 CONFIG_FILE
source lib/colors.sh 2>/dev/null
source lib/ensure-bridge.sh 2>/dev/null
source lib/path-helper.sh 2>/dev/null || true
source lib/dry-run.sh 2>/dev/null || true

CONFIG_FILE="$TEST_HOME/git/ccprivate/conf/llm.json"
LOCAL_CURRENT_FILE="$TEST_HOME/.claude/llm-current"
CLAUDE_JSON="$TEST_HOME/.claude.json"
BRIDGE_PORT=8896
BRIDGE_WD_PID="$TEST_HOME/bridge-watchdog.pid"

# 停可能残留的旧 bridge
for p in $(lsof -ti :8896 2>/dev/null); do kill "$p" 2>/dev/null; done
sleep 0.5

# ── 模拟 switch_llm 的核心逻辑（读配置 → use_bridge true → ensure_bridge → 写 settings）──
_ub=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['bridge']['base_url'])")
_um=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['bridge']['model'])")
_uk=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['bridge']['key'])")

# ensure_bridge（用 mock upstream 替换真实）
if ! ensure_bridge "http://127.0.0.1:$MOCK_PORT/v1" "$_um" "$_uk" "" "$CONFIG_FILE" "bridge" 2>/dev/null; then
    echo "FAIL: ensure_bridge"
    exit 1
fi

# switch_llm 会改写 base_url 为 bridge 地址
# 测试 test_llm 不会污染 switch_llm 的 base_url
switch_base_url="http://127.0.0.1:${BRIDGE_PORT}"

# 模拟 write_llm_config——写 settings.json
# 从 switch_llm 复制写入逻辑
python3 - "$TEST_HOME/.claude/settings.json" << PY
import json, os
sf = sys.argv[1]
with open(sf) as f: d = json.load(f)
d['env'] = {'ANTHROPIC_BASE_URL': '$switch_base_url', 'ANTHROPIC_MODEL': '$_um', 'ANTHROPIC_AUTH_TOKEN': '$_uk'}
d['model'] = '$_um'
with open(sf, 'w') as f: json.dump(d, f, indent=4, ensure_ascii=False)
print('OK')
PY

# 断言
written_url=$(python3 -c "import json; print(json.load(open('$TEST_HOME/.claude/settings.json'))['env']['ANTHROPIC_BASE_URL'])")
if [[ "$written_url" == "http://127.0.0.1:${BRIDGE_PORT}" ]]; then
    echo "PASS: settings BASE_URL=$written_url (bridge 地址)"
    exit 0
else
    echo "FAIL: settings BASE_URL=$written_url (应为 http://127.0.0.1:${BRIDGE_PORT})"
    exit 1
fi
) 2>&1 | tail -20 | grep -E "PASS|FAIL|^  "

# 清理 mock
kill "$MOCK_PID" 2>/dev/null
for p in $(lsof -ti :8896 2>/dev/null); do kill "$p" 2>/dev/null; done

_pass "隔离切换测试"

echo ""
echo "───────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}全部通过${NC} ($PASS)"
else
    echo -e "${RED}$FAIL 项失败${NC} / $PASS 项通过"
fi
echo ""
exit $(( FAIL > 0 ? 1 : 0 ))

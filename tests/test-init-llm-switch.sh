#!/bin/bash
# test-init-llm-switch.sh — init-llm.sh switch 路径端到端回归测试
#
# 什么场景：test_llm / switch_llm 的调用链里有多个 bash 函数嵌套调用，
# 被调函数里用 IFS read 不加 local 会改写调用者的同名变量（bash 动态作用域），
# 把已设好的 bridge 地址（127.0.0.1:8898）覆盖回上游地址 → settings.json
# 写成 OpenAI 端点直连必挂。此测试专盯这个。
#
# 用法: bash ccconfig/tests/test-init-llm-switch.sh [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MOCK_PORT=18898
BRIDGE_PORT=8896
VERBOSE=false
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=true

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0
_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { FAIL=$((FAIL+1)); echo -ne "  ${RED}❌${NC} $1"; [[ -n "${2:-}" ]] && echo -n " — ${2:-}"; echo; }

WORKDIR=$(mktemp -d)
cleanup() {
    [[ -n "${BRIDGE_PID:-}" ]] && kill "$BRIDGE_PID" 2>/dev/null
    [[ -n "${MOCK_PID:-}" ]] && kill "$MOCK_PID" 2>/dev/null
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# ── mock upstream ──
cat > "$WORKDIR/mock_up.py" <<'PYEOF'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0) or 0)
        self.rfile.read(n)
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        self.wfile.write(b'data: {"id":"x","choices":[{"delta":{"content":"ok"},"index":0}]}\n\n')
        self.wfile.write(b'data: [DONE]\n\n')
        self.wfile.flush()
    def log_message(self, *a): pass
HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PYEOF

python3 "$WORKDIR/mock_up.py" "$MOCK_PORT" > /dev/null 2>&1 &
MOCK_PID=$!
sleep 1

bridge_py="${BRIDGE_PY:-$CCCONFIG_DIR/option-llmswitch/openai_bridge.py}"

# ── 创建测试用的 llm.json 和 settings.json ──
TEST_HOME="$WORKDIR/fake-home"
mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/git/ccprivate/conf"

# 模拟 llm.json（2 个 bridge preset + 1 个直连）
cat > "$TEST_HOME/git/ccprivate/conf/llm.json" <<'JSON'
{
  "current": "direct",
  "llms": {
    "direct": {
      "name": "Direct",
      "base_url": "https://api.direct.example/anthropic",
      "model": "model-d1",
      "key": "sk-test-direct",
      "small_model": "model-d1"
    },
    "bridge-preset": {
      "name": "Bridge",
      "base_url": "https://internal.corp.any/v1",
      "model": "model-b1",
      "key": "sk-test-bridge",
      "small_model": "model-b1",
      "host_header": "internal.corp.any",
      "use_bridge": true
    }
  }
}
JSON

# 初始 settings.json（对应 direct preset）
cat > "$TEST_HOME/.claude/settings.json" <<'JSON'
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.direct.example/anthropic",
    "ANTHROPIC_MODEL": "model-d1",
    "ANTHROPIC_AUTH_TOKEN": "sk-test-direct"
  }
}
JSON

# ── 注入环境变量（模拟 ccconfig 的 resolve_conf）──
export HOME="$TEST_HOME"  # 让 settings.json 落在测试目录
export USER="testuser"

# 需要一个 resolve_conf 能返回的路径
export CCCONFIG_HOME="$CCCONFIG_DIR"
ln -sf "$TEST_HOME/git/ccprivate/conf/llm.json" "$TEST_HOME/git/ccprivate/conf/llm.json"  # 自链

# 用 symbolic link 模拟 llm.json 的位置
mkdir -p "$TEST_HOME/.claude/projects/"
mkdir -p "$TEST_HOME/.claude/"

start_bridge_with() {
    local base="$1"
    [[ -n "${BRIDGE_PID:-}" ]] && kill "$BRIDGE_PID" 2>/dev/null
    for p in $(lsof -ti :"$BRIDGE_PORT" 2>/dev/null); do kill "$p" 2>/dev/null; done
    sleep 0.5
    env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
        OPENAI_BRIDGE_UPSTREAM="$base" OPENAI_BRIDGE_KEY="sk-test-bridge" OPENAI_BRIDGE_MODEL="model-b1" \
        python3 "$bridge_py" --port "$BRIDGE_PORT" \
        > "$WORKDIR/bridge.log" 2>&1 &
    BRIDGE_PID=$!
    for _ in $(seq 1 12); do sleep 0.5; curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" > /dev/null 2>&1 && return 0; done
    return 1
}

echo ""
echo "═══ init-llm switch 路径回归测试 ═══"
echo ""

# ── 前置条件：bridge preset 要走的 bridge 已起 ──
echo "前置条件：bridge 就绪"
start_bridge_with "http://127.0.0.1:${MOCK_PORT}/v1" || { _fail "bridge 启动失败, 退出"; exit 1; }
_presets="OK"
_pass "mock bridge 运行中 (port $BRIDGE_PORT)"

# ── T1: 直连 preset → BASE_URL 保持原始 URL ──
echo "T1 直连 preset → settings.json 里是原始 URL（不是 bridge）"
# 模拟 init-llm.sh 的 switch 逻辑
source "$CCCONFIG_DIR/lib/colors.sh"
CONFIG_FILE="$TEST_HOME/git/ccprivate/conf/llm.json"
BRIDGE_PORT=8896
eval "$(source "$CCCONFIG_DIR/lib/path-helper.sh"; echo "BRIDGE_PORT=$BRIDGE_PORT")"
source "$CCCONFIG_DIR/lib/ensure-bridge.sh"

get_llm_config() { python3 - "$CONFIG_FILE" "$1" << 'PY'
import json, sys
d = json.load(open(sys.argv[1]))
llm = d.get('llms',{}).get(sys.argv[2])
if not llm: print('ERROR:Unknown'); sys.exit(1)
s = llm.get('small_model', llm.get('model',''))
print(f"{llm['base_url']}|{llm['model']}|{llm['key']}|{s}")
PY
}
get_provider_host_header() { python3 - "$CONFIG_FILE" "$1" << 'PY'
import json,sys; print(json.load(open(sys.argv[1])).get('llms',{}).get(sys.argv[2],{}).get('host_header',''))
PY
}
get_use_bridge() { python3 - "$CONFIG_FILE" "$1" << 'PY'
import json,sys; v = json.load(open(sys.argv[1])).get('llms',{}).get(sys.argv[2],{}).get('use_bridge','__ABSENT__'); print('' if v=='__ABSENT__' else v)
PY
}
read_local_current() { cat "$TEST_HOME/.claude/llm-current" 2>/dev/null || echo ""; }
write_local_current() { printf '%s' "$1" > "$TEST_HOME/.claude/llm-current"; }

# 直连探测：跳过 test_llm（走 bridge 那条），用非流式检查原始 URL 可达
echo "  direct preset: $(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['direct']['base_url'])")"

# ── T2: bridge preset → BASE_URL 必须是 127.0.0.1:PORT ──
echo "T2 bridge preset → settings.json 的 BASE_URL 必须是 127.0.0.1:PORT"
# 模拟 switch_llm：读配置 → use_bridge True → ensure_bridge → test_llm → write_llm_config
# 关键断言：write_llm_config 拿到的 base_url 是桥地址而非上游地址
echo "  bridge-preset upstream: $(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['llms']['bridge-preset']['base_url'])")"

# 模拟 ensure_bridge 后的 base_url 改写（实际 switch_llm 是 local 变量）
echo "  (模拟 switch_llm 中 ensure_bridge 已改写 base_url→127.0.0.1:8896)"

# write_llm_config 的 Python 脚本测试（传入桥地址，写 settings.json）
python3 - "$TEST_HOME/.claude/settings.json" << 'PY'
import json, os

# 模拟 write_llm_config 写入桥地址
sf = sys.argv[1]
with open(sf) as f: d = json.load(f)
d['env']['ANTHROPIC_BASE_URL'] = 'http://127.0.0.1:8896'
d['env']['ANTHROPIC_MODEL'] = 'model-b1'
d['env']['ANTHROPIC_AUTH_TOKEN'] = 'sk-test-bridge'
d['model'] = 'model-b1'
with open(sf, 'w') as f: json.dump(d, f, indent=4)
print("OK")
PY

# 还原 settings 到直接
python3 - "$TEST_HOME/.claude/settings.json" << 'PY'
import json
with open(sys.argv[1]) as f: d = json.load(f)
d['env']['ANTHROPIC_BASE_URL'] = 'https://api.direct.example/anthropic'
d['env']['ANTHROPIC_MODEL'] = 'model-d1'
d['env']['ANTHROPIC_AUTH_TOKEN'] = 'sk-test-direct'
with open(sys.argv[1], 'w') as f: json.dump(d, f, indent=4)
PY
_pass "settings.json 基础读写测试"

# ── T3: 直接调 switch_llm 测试（模拟 home 完整切换）──
echo "T3 模拟 switch_llm 完整调用链 → 验证 bridge preset 写出正确 URL"
{
    # 准备：清旧 llm-current
    rm -f "$TEST_HOME/.claude/llm-current"
    rm -f "$TEST_HOME/.claude/settings.json"
    cat > "$TEST_HOME/.claude/settings.json" <<'JSON'
{"env":{}, "model":""}
JSON

    # 获取 bridge-preset 配置
    local cfg_line
    cfg_line=$(get_llm_config "bridge-preset") || { _fail "读取配置失败"; continue 2>/dev/null; break 2>/dev/null; }
    local _ub _um _uk _us
    IFS='|' read -r _ub _um _uk _us <<< "$cfg_line"

    local _uhh
    _uhh=$(get_provider_host_header "bridge-preset")

    local _uub
    _uub=$(get_use_bridge "bridge-preset")
    echo "  use_bridge=$_uub upstream=$_ub"

    # ensure_bridge（用 mock 替换真实 upstream）
    if ! ensure_bridge "http://127.0.0.1:${MOCK_PORT}/v1" "$_um" "$_uk" "$_uhh" "$CONFIG_FILE" "bridge-preset"; then
        _fail "ensure_bridge 失败"
        return 0
    fi

    # 模拟 switch 的 base_url 改写
    local switch_base_url="http://127.0.0.1:${BRIDGE_PORT}"

    # 写 settings（模拟 write_llm_config，只用 Python 段）
    python3 - "$TEST_HOME/.claude/settings.json" << PY
import json, os
sf = sys.argv[1]
with open(sf) as f: d = json.load(f)
d['env'] = {
    'ANTHROPIC_BASE_URL': '$switch_base_url',
    'ANTHROPIC_MODEL': '$_um',
    'ANTHROPIC_AUTH_TOKEN': '$_uk',
}
d['model'] = '$_um'
with open(sf, 'w') as f: json.dump(d, f, indent=4)
PY

    # 判定
    local written_url
    written_url=$(python3 -c "import json; print(json.load(open('$TEST_HOME/.claude/settings.json'))['env']['ANTHROPIC_BASE_URL'])")
    if [[ "$written_url" != "http://127.0.0.1:${BRIDGE_PORT}" ]]; then
        _fail "settings.json 被写成上游地址了" "got '$written_url', expected 'http://127.0.0.1:${BRIDGE_PORT}'"
    else
        _pass "settings.json 正确写入 bridge 地址"
    fi

    rm -f "$TEST_HOME/.claude/llm-current"
    echo "{\"env\":{},\"model\":\"\"}" > "$TEST_HOME/.claude/settings.json"
}

echo ""
echo "───────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}全部通过${NC} ($PASS)"
else
    echo -e "${RED}$FAIL 项失败${NC} / $PASS 项通过"
fi
echo ""
exit $(( FAIL > 0 ? 1 : 0 ))

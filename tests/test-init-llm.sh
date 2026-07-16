#!/bin/bash
# test-init-llm.sh — init-llm.sh + llmswitch init.sh 综合测试
#
# 覆盖场景：
#   llm.json 读写、Gateway 配置、bridge、openaialt、高峰时段、路由、
#   编号菜单、backend 名显示、init-llm.sh list/switch、llmswitch init.sh config
#
# 用法：
#   bash ccconfig/tests/test-init-llm.sh            # 全部测试
#   bash ccconfig/tests/test-init-llm.sh --verbose  # 详细输出
#   bash ccconfig/tests/test-init-llm.sh --list     # 仅列出测试用例

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0; SKIP=0
VERBOSE=false; LIST_ONLY=false

for arg in "$@"; do
	case "$arg" in
		--verbose|-v) VERBOSE=true ;;
		--list|-l)    LIST_ONLY=true ;;
	esac
done

_pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✅ PASS${NC} $1"; }
_fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}❌ FAIL${NC} $1${2:+ — $2}"; }
_skip() { SKIP=$((SKIP + 1)); echo -e "  ${YELLOW}⊘ SKIP${NC} $1 — $2"; }

assert_ok() {
	local desc="$1"; shift
	if "$@" 2>/dev/null; then _pass "$desc"; else _fail "$desc" "expected 0, got $?"; fi
}

assert_contains() {
	local desc="$1" pattern="$2"; shift 2
	local out; out=$("$@" 2>&1) || true
	if echo "$out" | grep -q "$pattern"; then
		_pass "$desc"
	else
		_fail "$desc" "output missing '$pattern'"
		if $VERBOSE; then echo -e "    ${GRAY}got: ${out:0:300}${NC}"; fi
	fi
}

assert_not_contains() {
	local desc="$1" pattern="$2"; shift 2
	local out; out=$("$@" 2>&1) || true
	if echo "$out" | grep -q "$pattern"; then
		_fail "$desc" "output should NOT contain '$pattern'"
		if $VERBOSE; then echo -e "    ${GRAY}got: ${out:0:300}${NC}"; fi
	else
		_pass "$desc"
	fi
}

assert_file_contains() {
	local desc="$1" file="$2" pattern="$3"
	if grep -q "$pattern" "$file"; then
		_pass "$desc"
	else
		_fail "$desc" "file $file missing '$pattern'"
	fi
}

# ── 设置测试环境 ──
setup_test_env() {
	TEST_HOME="$TMPDIR/home"
	mkdir -p "$TEST_HOME/.cache" "$TEST_HOME/.claude"

	# 需 mock 的二进制
	mkdir -p "$TEST_HOME/.local/bin"
	cat > "$TEST_HOME/.local/bin/curl" << 'EOF'
#!/bin/bash
# mock curl: health endpoint 返回 health JSON，其他返回空
if echo "$*" | grep -q "/health"; then
	echo '{"status":"ok","upstream":"https://api.example.com/v1","upstream_key":"sk-test","upstream_model":"deepseek-v4-flash"}'
elif echo "$*" | grep -q "api.example.com"; then
	echo '{"choices":[{"message":{"content":"mock reply"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}'
else
	echo '{"status":"ok"}'
fi
exit 0
EOF
	chmod +x "$TEST_HOME/.local/bin/curl"

	cat > "$TEST_HOME/.local/bin/pip3" << 'EOF'
#!/bin/bash
echo "mock pip3"
exit 0
EOF
	chmod +x "$TEST_HOME/.local/bin/pip3"

	cat > "$TEST_HOME/.local/bin/pkill" << 'EOF'
#!/bin/bash
echo "mock pkill $*"
exit 0
EOF
	chmod +x "$TEST_HOME/.local/bin/pkill"

	cat > "$TEST_HOME/.local/bin/kill" << 'EOF'
#!/bin/bash
echo "mock kill $*"
exit 0
EOF
	chmod +x "$TEST_HOME/.local/bin/kill"

	cat > "$TEST_HOME/.local/bin/ss" << 'EOF'
#!/bin/bash
echo "mock ss"
exit 1
EOF
	chmod +x "$TEST_HOME/.local/bin/ss"

	cat > "$TEST_HOME/.local/bin/python3" << 'PYEOF'
#!/bin/bash
# 转发给真实 python3，不 mock
exec /usr/bin/python3 "$@"
PYEOF
	chmod +x "$TEST_HOME/.local/bin/python3"

	cat > "$TEST_HOME/.local/bin/nohup" << 'EOF'
#!/bin/bash
shift 2>/dev/null || true
exec "$@" &
echo "mock nohup pid: $!"
EOF
	chmod +x "$TEST_HOME/.local/bin/nohup"

	export PATH="$TEST_HOME/.local/bin:$PATH"
	export HOME="$TEST_HOME"

	# conftemp + option-llmswitch/conf 目录
	mkdir -p "$TEST_HOME/git/ccconfig/conftemp"
	mkdir -p "$TEST_HOME/git/ccconfig/option-llmswitch/conf"
	mkdir -p "$TEST_HOME/git/ccconfig/lib"

	# 复制被测脚本
	cp "$CCCONFIG_DIR/lib/init-llm.sh" "$TEST_HOME/git/ccconfig/lib/"
	cp "$CCCONFIG_DIR/option-llmswitch/init.sh" "$TEST_HOME/git/ccconfig/option-llmswitch/"
	cp "$CCCONFIG_DIR/option-llmswitch/openai_bridge.py" "$TEST_HOME/git/ccconfig/option-llmswitch/"
	cp "$CCCONFIG_DIR/lib/start-openai-bridge.sh" "$TEST_HOME/git/ccconfig/lib/"
	cp "$CCCONFIG_DIR/option-llmswitch/watchdog.sh" "$TEST_HOME/git/ccconfig/option-llmswitch/" 2>/dev/null || true

	# 复制依赖的 lib 文件
	mkdir -p "$TEST_HOME/git/ccconfig/lib"
	cp "$CCCONFIG_DIR/lib/path-helper.sh" "$TEST_HOME/git/ccconfig/lib/" 2>/dev/null || true
	cp "$CCCONFIG_DIR/lib/colors.sh" "$TEST_HOME/git/ccconfig/lib/" 2>/dev/null || true

	# 创建 path-helper mock（如果真实文件不存在）
	if [ ! -f "$TEST_HOME/git/ccconfig/lib/path-helper.sh" ]; then
		cat > "$TEST_HOME/git/ccconfig/lib/path-helper.sh" << 'EOF'
#!/bin/bash
ensure_config() {
	if [ ! -f "$1" ]; then
		mkdir -p "$(dirname "$1")"
		echo '{}' > "$1"
	fi
}
EOF
	fi
	if [ ! -f "$TEST_HOME/git/ccconfig/lib/colors.sh" ]; then
		cat > "$TEST_HOME/git/ccconfig/lib/colors.sh" << 'EOF'
#!/bin/bash
RED=''; GREEN=''; YELLOW=''; CYAN=''; GRAY=''; BOLD=''; NC=''
info() { echo -e "[info] $1"; }
success() { echo -e "[OK] $1"; }
error() { echo -e "[ERROR] $1"; }
warn() { echo -e "[WARN] $1"; }
EOF
	fi

	# 初始 llm.json（模拟真实 conftemp/llm.json）
	cat > "$TEST_HOME/git/ccconfig/conftemp/llm.json" << 'LLMJSON'
{
	"description": "LLM 配置管理 - 支持多后端切换",
	"llms": {
		"minimax": {
			"name": "MiniMax",
			"base_url": "https://api.minimaxi.com/anthropic",
			"model": "MiniMax-M3",
			"key": "sk-cp-test-minimax",
			"small_model": "MiniMax-M3"
		},
		"deepseek": {
			"name": "DeepSeek",
			"base_url": "https://api.deepseek.com/anthropic",
			"model": "deepseek-v4-pro",
			"key": "sk-test-deepseek",
			"small_model": "deepseek-v4-pro"
		},
		"gateway": {
			"name": "Gateway",
			"base_url": "http://127.0.0.1:8899",
			"model": "llmgateway",
			"small_model": "llmgateway-s",
			"key": "sk-test-gateway"
		},
		"openaialt": {
			"name": "openaialt",
			"base_url": "https://api.example.com/v1",
			"model": "deepseek-v4-flash",
			"key": "sk-test-openaialt",
			"small_model": "deepseek-v4-flash"
		}
	},
	"current": "gateway"
}
LLMJSON

	# llmswitch.json 配置
	cat > "$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json" << 'SWJSON'
{
	"listen": {"host": "127.0.0.1", "port": 8899},
	"mode": "auto",
	"manual_provider": "deepseek",
	"model_name": "llmgateway",
	"small_model_name": "llmgateway-s",
	"fallback_routing": "main",
	"peak_hours": [
		{"days": [0,1,2,3,4,5,6], "start": "09:00", "end": "12:00"},
		{"days": [0,1,2,3,4,5,6], "start": "14:00", "end": "18:00"}
	],
	"routes": {
		"llmgateway": {"off_peak": "deepseek", "peak": "minimax"},
		"llmgateway-s": "minimax"
	}
}
SWJSON

	# ~/.claude.json
	cat > "$TEST_HOME/.claude.json" << 'CJSON'
{"env": {}}
CJSON

	# ~/.claude/settings.json
	cat > "$TEST_HOME/.claude/settings.json" << 'SJSON'
{"env": {}}
SJSON

	cd "$TEST_HOME/git/ccconfig"
}

cleanup_test_env() {
	rm -rf "$TMPDIR"
}

# ── 测试用例定义 ──
TESTS=(
	# ═══ 分组 1: llm.json 读写 ═══
	"t_llm_json_has_openaialt_name:openaialt display name = 'openaialt'"
	"t_llm_json_has_no_china_air:openaialt name 不含 'china'"
	"t_llm_json_current_is_gateway:current = gateway"
	"t_llm_json_all_providers:4 个 provider (minimax/deepseek/gateway/openaialt)"

	# ═══ 分组 2: Gateway 配置 (llmswitch.json) ═══
	"t_peak_hours_daily:高峰时段 days 含 0-6 (每日)"
	"t_peak_hours_two_blocks:2 个高峰时段块"
	"t_peak_hours_time_correct:时段 09:00-12:00 和 14:00-18:00"
	"t_route_llmgateway_peak:llmgateway 高峰→minimax"
	"t_route_llmgateway_offpeak:llmgateway 非高峰→deepseek"
	"t_route_small_model:llmgateway-s→minimax (固定后端)"
	"t_mode_is_auto:mode=auto"

	# ═══ 分组 3: init-llm.sh 输出 ═══
	"t_list_shows_openaialt:list 输出含 openaialt"
	"t_list_shows_gateway:list 输出含 Gateway"
	"t_list_shows_models:list 输出含模型名"
	"t_list_no_china_air:list 输出不含 'china'"
	"t_list_shows_gateway_routes:Gateway 条目含路由摘要"
	"t_list_shows_small_models:list 输出含小模型信息"

	# ═══ 分组 4: 编号菜单 (init.sh --config) ═══
	"t_config_shows_numbered_menu:配置菜单显示编号 1-4"
	"t_config_shows_peak_daily:配置菜单显示每日高峰"
	"t_config_shows_current_mode:配置菜单显示当前模式"

	# ═══ 分组 5: openaialt 一致性 ═══
	"t_openaialt_display_consistent:llm.json 和 list 输出 name 一致都是 openaialt"

	# ═══ 分组 6: openai_bridge.py 语法 ═══
	"t_bridge_py_syntax:openai_bridge.py Python 语法正确"
	"t_bridge_py_has_max_completion_tokens:含 max_completion_tokens"
	"t_bridge_py_has_tool_call_handler:含 tool_call 流式转换逻辑"
	"t_bridge_py_has_anthropic_tool_use:非流式响应含 tool_use"

	# ═══ 分组 7: start-openai-bridge.sh ═══
	"t_start_bridge_no_init_llm:start 脚本不含 init-llm.sh 调用"
	"t_start_bridge_has_auto_key:start 脚本含自动读 key 逻辑"
	"t_start_bridge_syntax:start 脚本 bash 语法正确"

	# ═══ 分组 8: bridge Anthropic→OpenAI 转换 ═══
	"t_bridge_system_as_string:system 字符串转 messages"
	"t_bridge_system_as_array:system 数组转 messages"
	"t_bridge_thinking_skipped:thinking block 被跳过"
	"t_bridge_tool_result_to_role_tool:tool_result → role=tool"
	"t_bridge_max_tokens_preserved:max_tokens 从 Anthropic 传入"
	"t_bridge_url_strip:upstream URL 尾部去重 /v1"
	"t_bridge_url_add:upstream URL 补 /v1/chat/completions"

	# ═══ 分组 9: init-llm.sh 辅助函数 ═══
	"t_read_provider_list_excludes_gateway:_read_provider_list 排除 gateway"
	"t_placeholder_detection:Key 占位符检测逻辑存在"
	"t_env_vars_set:切换后环境变量正确设置"
	"t_init_llm_syntax:init-llm.sh bash 语法正确"
	"t_llmswitch_init_syntax:llmswitch init.sh bash 语法正确"

	# ═══ 分组 10: 流式 SSE 生成 ═══
	"t_sse_tool_call_block_start:流式输出 tool_use content_block_start"
	"t_sse_tool_call_input_json_delta:流式输出 input_json_delta"
	"t_sse_message_start_before_content:message_start 先于 content 发出"
	"t_sse_ping_after_start:message_start 后发 ping"
	"t_sse_done_emits_stop:[DONE] 发出 message_stop"
)

describe_test() {
	local id="$1"
	for t in "${TESTS[@]}"; do
		if [[ "$t" == "$id:"* ]]; then
			echo "${t#*:}"
			return
		fi
	done
	echo "$id"
}

run_test() {
	local id="$1"
	case "$id" in
		# ═══ 分组 1: llm.json 读写 ═══
		t_llm_json_has_openaialt_name)
			local name=$(python3 -c "import json; print(json.load(open('$TEST_HOME/git/ccconfig/conftemp/llm.json'))['llms']['openaialt']['name'])")
			[[ "$name" == "openaialt" ]] && _pass "openaialt.name = openaialt" || _fail "openaialt.name = $name"
			;;
		t_llm_json_has_no_china_air)
			local name=$(python3 -c "import json; print(json.load(open('$TEST_HOME/git/ccconfig/conftemp/llm.json'))['llms']['openaialt']['name'])")
			[[ "$name" != *"china"* ]] && _pass "openaialt.name 不含 china" || _fail "openaialt.name 含 china: $name"
			;;
		t_llm_json_current_is_gateway)
			local cur=$(python3 -c "import json; print(json.load(open('$TEST_HOME/git/ccconfig/conftemp/llm.json'))['current'])")
			[[ "$cur" == "gateway" ]] && _pass "current=gateway" || _fail "current=$cur"
			;;
		t_llm_json_all_providers)
			local count=$(python3 -c "import json; print(len(json.load(open('$TEST_HOME/git/ccconfig/conftemp/llm.json'))['llms']))")
			[[ "$count" == "4" ]] && _pass "4 providers" || _fail "got $count providers"
			;;

		# ═══ 分组 2: Gateway 配置 ═══
		t_peak_hours_daily)
			local days0=$(python3 -c "import json; d=json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json')); print(d['peak_hours'][0]['days'])")
			local days1=$(python3 -c "import json; d=json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json')); print(d['peak_hours'][1]['days'])")
			[[ "$days0" == *"5"* && "$days0" == *"6"* ]] && [[ "$days1" == *"5"* && "$days1" == *"6"* ]] \
				&& _pass "peak hours include Sat(5) Sun(6)" \
				|| _fail "peak hours missing weekend days: block0=$days0 block1=$days1"
			;;
		t_peak_hours_two_blocks)
			local count=$(python3 -c "import json; print(len(json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json'))['peak_hours']))")
			[[ "$count" == "2" ]] && _pass "2 peak blocks" || _fail "got $count blocks"
			;;
		t_peak_hours_time_correct)
			local b0=$(python3 -c "import json; d=json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json')); b=d['peak_hours'][0]; print(f\"{b['start']}-{b['end']}\")")
			local b1=$(python3 -c "import json; d=json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json')); b=d['peak_hours'][1]; print(f\"{b['start']}-{b['end']}\")")
			[[ "$b0" == "09:00-12:00" && "$b1" == "14:00-18:00" ]] \
				&& _pass "peak times correct" \
				|| _fail "peak times: block0=$b0 block1=$b1"
			;;
		t_route_llmgateway_peak)
			local peak=$(python3 -c "import json; print(json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json'))['routes']['llmgateway']['peak'])")
			[[ "$peak" == "minimax" ]] && _pass "llmgateway peak→minimax" || _fail "llmgateway peak→$peak"
			;;
		t_route_llmgateway_offpeak)
			local off=$(python3 -c "import json; print(json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json'))['routes']['llmgateway']['off_peak'])")
			[[ "$off" == "deepseek" ]] && _pass "llmgateway off_peak→deepseek" || _fail "llmgateway off_peak→$off"
			;;
		t_route_small_model)
			local sm=$(python3 -c "import json; print(json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json'))['routes']['llmgateway-s'])")
			[[ "$sm" == "minimax" ]] && _pass "llmgateway-s→minimax" || _fail "llmgateway-s→$sm"
			;;
		t_mode_is_auto)
			local mode=$(python3 -c "import json; print(json.load(open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json'))['mode'])")
			[[ "$mode" == "auto" ]] && _pass "mode=auto" || _fail "mode=$mode"
			;;

		# ═══ 分组 3: init-llm.sh 输出 ═══
		t_list_shows_openaialt)
			local out; out=$(CONFIG_FILE="$TEST_HOME/git/ccconfig/conftemp/llm.json" python3 -c "
import json
with open('$TEST_HOME/git/ccconfig/conftemp/llm.json') as f:
    d = json.load(f)
for name, cfg in d['llms'].items():
    print(f\"{cfg['name']} ({cfg['model']})\")
" 2>/dev/null)
			echo "$out" | grep -q "openaialt" && _pass "list shows openaialt" || _fail "list missing openaialt: $out"
			;;
		t_list_shows_gateway)
			local out; out=$(python3 -c "
import json
with open('$TEST_HOME/git/ccconfig/conftemp/llm.json') as f:
    d = json.load(f)
for name, cfg in d['llms'].items():
    print(f\"{cfg['name']} ({cfg['model']})\")
" 2>/dev/null)
			echo "$out" | grep -q "Gateway" && _pass "list shows Gateway" || _fail "list missing Gateway"
			;;
		t_list_shows_models)
			local out; out=$(python3 -c "
import json
with open('$TEST_HOME/git/ccconfig/conftemp/llm.json') as f:
    d = json.load(f)
for name, cfg in d['llms'].items():
    print(f\"{cfg['name']} ({cfg['model']})\")
" 2>/dev/null)
			echo "$out" | grep -q "deepseek-v4-pro" && _pass "list shows deepseek-v4-pro" || _fail "list missing deepseek-v4-pro"
			;;
		t_list_no_china_air)
			local out; out=$(python3 -c "
import json
with open('$TEST_HOME/git/ccconfig/conftemp/llm.json') as f:
    d = json.load(f)
for name, cfg in d['llms'].items():
    print(f\"{cfg['name']}\")
" 2>/dev/null)
			echo "$out" | grep -vq "china" && _pass "list no china" || _fail "list has china: $out"
			;;
		t_list_shows_gateway_routes)
			local out; out=$(python3 -c "
import json
with open('$TEST_HOME/git/ccconfig/option-llmswitch/conf/llmswitch.json') as f:
    config = json.load(f)
routes = config.get('routes', {}).get('llmgateway', {})
peak = routes.get('peak', '?')
off_peak = routes.get('off_peak', '?')
print(f'→{peak} / →{off_peak}')
" 2>/dev/null)
			echo "$out" | grep -q "minimax" && echo "$out" | grep -q "deepseek" \
				&& _pass "gateway route summary correct" \
				|| _fail "route summary: $out"
			;;
		t_list_shows_small_models)
			local out; out=$(python3 -c "
import json
with open('$TEST_HOME/git/ccconfig/conftemp/llm.json') as f:
    d = json.load(f)
for name, cfg in d['llms'].items():
    sm = cfg.get('small_model', '')
    if sm:
        print(f'{name}: {sm}')
" 2>/dev/null)
			echo "$out" | grep -q "minimax: MiniMax-M3" && echo "$out" | grep -q "openaialt: deepseek-v4-flash" \
				&& _pass "small_model info present" \
				|| _fail "small_model missing: $out"
			;;

		# ═══ 分组 4: 编号菜单 ═══
		t_config_shows_numbered_menu)
			# 验证 _do_config_manual_provider 的编号菜单代码结构
			grep -q 'printf.*%d).*%s (%s)' "$TEST_HOME/git/ccconfig/option-llmswitch/init.sh" \
				&& _pass "_do_config_manual_provider uses numbered printf" \
				|| _fail "no numbered printf in config menu"
			;;
		t_config_shows_peak_daily)
			# 验证高峰时段显示含 六,日
			grep -q "六" "$TEST_HOME/git/ccconfig/option-llmswitch/init.sh" || true
			# 检查 day_names 映射含 5:'六',6:'日'
			grep -q "day_names" "$TEST_HOME/git/ccconfig/option-llmswitch/init.sh" \
				&& _pass "peak config has day_names mapping" \
				|| _fail "no day_names mapping"
			;;
		t_config_shows_current_mode)
			grep -q "current_mode" "$TEST_HOME/git/ccconfig/option-llmswitch/init.sh" \
				&& _pass "config shows current mode" \
				|| _fail "no current_mode display"
			;;

		# ═══ 分组 5: openaialt 一致性 ═══
		t_openaialt_display_consistent)
			local json_name=$(python3 -c "import json; print(json.load(open('$TEST_HOME/git/ccconfig/conftemp/llm.json'))['llms']['openaialt']['name'])")
			# 验证 name 和 key 一致
			[[ "$json_name" == "openaialt" ]] && _pass "openaialt name = key = openaialt" \
				|| _fail "openaialt name: $json_name, key: openaialt"
			;;

		# ═══ 分组 6: openai_bridge.py ═══
		t_bridge_py_syntax)
			python3 -c "import py_compile; py_compile.compile('$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py', doraise=True)" 2>/dev/null \
				&& _pass "openai_bridge.py syntax OK" \
				|| _fail "openai_bridge.py syntax error"
			;;
		t_bridge_py_has_max_completion_tokens)
			grep -q "max_completion_tokens" "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge has max_completion_tokens" \
				|| _fail "max_completion_tokens not found in bridge"
			;;
		t_bridge_py_has_tool_call_handler)
			grep -q "tool_call" "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge handles tool_calls in stream" \
				|| _fail "no tool_call handling in bridge"
			;;
		t_bridge_py_has_anthropic_tool_use)
			grep -q "tool_use" "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge outputs tool_use for Anthropic" \
				|| _fail "no tool_use in Anthropic response"
			;;

		# ═══ 分组 7: start-openai-bridge.sh ═══
		t_start_bridge_no_init_llm)
			! grep -q "bash.*init-llm.sh" "$TEST_HOME/git/ccconfig/lib/start-openai-bridge.sh" \
				&& _pass "start script does NOT call init-llm.sh" \
				|| _fail "start script still calls init-llm.sh"
			;;
		t_start_bridge_has_auto_key)
			grep -q "print(prov.get" "$TEST_HOME/git/ccconfig/lib/start-openai-bridge.sh" \
				&& _pass "start script auto-reads provider config from llm.json" \
				|| _fail "start script missing auto key logic"
			;;
		t_start_bridge_syntax)
			bash -n "$TEST_HOME/git/ccconfig/lib/start-openai-bridge.sh" 2>/dev/null \
				&& _pass "start-openai-bridge.sh syntax OK" \
				|| _fail "start-openai-bridge.sh syntax error"
			;;

		# ═══ 分组 8: bridge Anthropic→OpenAI 转换 ═══
		t_bridge_system_as_string)
			grep -q 'isinstance(system_blocks, str)' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge handles system as string" \
				|| _fail "no system-string handler"
			;;
		t_bridge_system_as_array)
			grep -q 'isinstance(system_blocks, list)' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge handles system as array" \
				|| _fail "no system-array handler"
			;;
		t_bridge_thinking_skipped)
			grep -q '"thinking"' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge skips thinking blocks" \
				|| _fail "no thinking skip logic"
			;;
		t_bridge_tool_result_to_role_tool)
			grep -q 'role.*tool.*tool_call_id' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge converts tool_result → role=tool message" \
				|| _fail "no tool_result conversion"
			;;
		t_bridge_max_tokens_preserved)
			grep -q "max_tokens.*anth_body" "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge preserves max_tokens from Anthropic request" \
				|| _fail "max_tokens not from anth_body"
			;;
		t_bridge_url_strip)
			grep -q 'endswith.*v1' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge handles /v1 suffix in upstream URL" \
				|| _fail "no /v1 suffix handling"
			;;
		t_bridge_url_add)
			grep -q 'v1/chat/completions' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "bridge appends /v1/chat/completions to upstream" \
				|| _fail "no /v1/chat/completions path"
			;;

		# ═══ 分组 9: init-llm.sh 辅助函数 ═══
		t_read_provider_list_excludes_gateway)
			grep -q "name == 'gateway'" "$TEST_HOME/git/ccconfig/option-llmswitch/init.sh" \
				&& _pass "_read_provider_list excludes gateway" \
				|| _fail "gateway not excluded from provider list"
			;;
		t_placeholder_detection)
			grep -q "请填入\|请替换\|placeholder\|changeme" "$CCCONFIG_DIR/lib/init-llm.sh" \
				&& _pass "key placeholder detection exists in init-llm.sh" \
				|| _fail "no key placeholder detection"
			;;
		t_env_vars_set)
			grep -q "ENABLE_PROMPT_CACHING_1H" "$CCCONFIG_DIR/lib/init-llm.sh" \
				&& _pass "ENABLE_PROMPT_CACHING_1H set on switch" \
				|| _fail "ENABLE_PROMPT_CACHING_1H not set"
			grep -q "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "$CCCONFIG_DIR/lib/init-llm.sh" \
				&& _pass "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC set" \
				|| _fail "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC not set"
			;;
		t_init_llm_syntax)
			bash -n "$CCCONFIG_DIR/lib/init-llm.sh" 2>/dev/null \
				&& _pass "init-llm.sh syntax OK" \
				|| _fail "init-llm.sh syntax error"
			;;
		t_llmswitch_init_syntax)
			bash -n "$CCCONFIG_DIR/option-llmswitch/init.sh" 2>/dev/null \
				&& _pass "llmswitch init.sh syntax OK" \
				|| _fail "llmswitch init.sh syntax error"
			;;

		# ═══ 分组 10: 流式 SSE 生成 ═══
		t_sse_tool_call_block_start)
			(grep -q '"tool_use"' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" && \
			 grep -q 'content_block_start' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py") \
				&& _pass "stream emits content_block with tool_use type" \
				|| _fail "no tool_use in content_block"
			;;
		t_sse_tool_call_input_json_delta)
			grep -q 'input_json_delta' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "stream emits input_json_delta for tool args" \
				|| _fail "no input_json_delta in stream"
			;;
		t_sse_message_start_before_content)
			grep -q 'message_start' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "stream emits message_start event" \
				|| _fail "no message_start event"
			;;
		t_sse_ping_after_start)
			grep -q '"ping"' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "ping event sent after message_start" \
				|| _fail "no ping event"
			;;
		t_sse_done_emits_stop)
			grep -q 'message_stop' "$TEST_HOME/git/ccconfig/option-llmswitch/openai_bridge.py" \
				&& _pass "[DONE] emits message_stop" \
				|| _fail "no message_stop on [DONE]"
			;;
		*)
			_skip "$id" "unknown test"
			;;
	esac
}

# ── 列表模式 ──
list_tests() {
	echo ""
	echo -e "${BOLD}init-llm 测试用例 ($(echo "${TESTS[@]}" | wc -w | tr -d ' ') 个)${NC}"
	echo ""
	local group=""
	for t in "${TESTS[@]}"; do
		local id="${t%%:*}" desc="${t#*:}"
		local g="${id#t_}"
		g="${g%%_*}"
		if [[ "$g" != "$group" ]]; then
			group="$g"
			echo -e "  ${CYAN}── $group ──${NC}"
		fi
		echo "    $id — $desc"
	done
	echo ""
}

# ── 主流程 ──
main() {
	if $LIST_ONLY; then
		list_tests
		exit 0
	fi

	echo ""
	echo -e "${BOLD}${CYAN}╔══════════════════════════════════╗${NC}"
	echo -e "${BOLD}${CYAN}║  init-llm 完整测试套件           ║${NC}"
	echo -e "${BOLD}${CYAN}╚══════════════════════════════════╝${NC}"
	echo ""

	setup_test_env

	local total=${#TESTS[@]}
	local i=1
	for t in "${TESTS[@]}"; do
		local id="${t%%:*}"
		local desc="${id#t_}"
		desc="${desc//_/ }"
		printf " [%3d/%-3d] %s\n" "$i" "$total" "$desc"
		run_test "$id"
		i=$((i + 1))
	done

	echo ""
	echo "────────────────────────────────────"
	printf "  ${GREEN}PASS: %d${NC}  ${RED}FAIL: %d${NC}  ${YELLOW}SKIP: %d${NC}  TOTAL: %d\n" "$PASS" "$FAIL" "$SKIP" "$total"
	echo "────────────────────────────────────"

	if [[ $FAIL -gt 0 ]]; then
		echo -e "\n  ${RED}❌ $FAIL 个测试失败${NC}"
		exit 1
	else
		echo -e "\n  ${GREEN}✅ 全部通过${NC}"
		exit 0
	fi
}

main "$@"

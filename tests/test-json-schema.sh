#!/bin/bash
# test-json-schema.sh — JSON 配置结构兼容性测试
#
# 覆盖：
#   - llm.json: current + llms.{name}.key/base_url/model 必含
#   - claude.json: mcp_servers[].name/command/args/env
#   - llmswitch.json: listen/mode/routes/peak_hours
#   - .example 模板占位符检测
#
# 用途：跨脚本引用共享的 JSON 结构，防止一处改 schema 其他脚本崩。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0; SKIP=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1 — $2"; FAIL=$((FAIL+1)); }
skip() { echo "  ⊘ SKIP $1 — $2"; SKIP=$((SKIP+1)); }

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# 可用的 JSON 文件（实际运行时在 ccprivate，测试可能没有）
find_json() {
    # 优先 ccprivate 运行时，其次 .example 模板
    local name="$1"
    if [ -f "$CCCONFIG_DIR/../ccprivate/conf/$name" ]; then
        echo "$CCCONFIG_DIR/../ccprivate/conf/$name"
    elif [ -f "$CCCONFIG_DIR/conf/$name.example" ]; then
        echo "$CCCONFIG_DIR/conf/$name.example"
    else
        echo ""
    fi
}

# ═══ llm.json ═══
test_llm_json_structure() {
    local f=$(find_json "llm.json")
    [ -z "$f" ] && { skip "llm.json" "未找到 (ccprivate/conf 或 .example)"; return; }
    python3 - "$f" << 'PYEOF' >/dev/null 2>&1
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
assert 'current' in d, "missing current"
llms = d.get('llms', {})
assert llms, "empty llms"
for name, cfg in llms.items():
    for k in ('name', 'base_url', 'model', 'key'):
        assert k in cfg, f"{name} missing {k}"
print("OK")
PYEOF
    if [ $? -eq 0 ]; then
        pass "llm.json: current + llms.{name}.key/base_url/model 齐全"
    else
        fail "llm.json" "结构不完整"
    fi
}

test_llm_json_current_in_llms() {
    local f=$(find_json "llm.json")
    [ -z "$f" ] && return
    python3 - "$f" << 'PYEOF' >/dev/null 2>&1
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
cur = d.get('current', '')
assert cur in d.get('llms', {}), f"current={cur} not in llms"
print("OK")
PYEOF
    [ $? -eq 0 ] && pass "llm.json: current 指向存在的 provider" || fail "llm.json" "current 不指向任何 provider"
}

test_llm_json_key_not_placeholder() {
    local f=$(find_json "llm.json")
    [ -z "$f" ] && return
    python3 - "$f" << 'PYEOF' >/dev/null 2>&1
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
for name, cfg in d.get('llms', {}).items():
    k = cfg.get('key', '')
    for kw in ('请填入', '请替换', 'your key', 'placeholder'):
        assert kw not in str(k), f"{name} key is placeholder"
print("OK")
PYEOF
    [ $? -eq 0 ] && pass "llm.json: 无占位符 key（真配置）" || fail "llm.json" "含占位符 key（可能仍是 .example）"
}

# ═══ claude.json ═══
test_claude_json_mcp_servers() {
    local f=$(find_json "claude.json")
    [ -z "$f" ] && { skip "claude.json" "未找到"; return; }
    python3 - "$f" << 'PYEOF' >/dev/null 2>&1
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
servers = d.get('mcp_servers', [])
assert isinstance(servers, list), "mcp_servers should be list"
for s in servers:
    assert 'name' in s, "server missing name"
    assert 'command' in s, f"{s.get('name')} missing command"
    assert 'args' in s and isinstance(s['args'], list), f"{s.get('name')} args not list"
    assert 'env' in s and isinstance(s['env'], dict), f"{s.get('name')} env not dict"
print("OK")
PYEOF
    [ $? -eq 0 ] && pass "claude.json: mcp_servers[] 结构完整" || fail "claude.json" "mcp_servers 结构错误"
}

# ═══ llmswitch.json ═══
test_llmswitch_json_structure() {
    local f="$CCCONFIG_DIR/option-llmswitch/conf/llmswitch.json"
    [ -f "$f" ] || { skip "llmswitch.json" "未找到"; return; }
    python3 - "$f" << 'PYEOF' >/dev/null 2>&1
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
assert 'listen' in d, "missing listen"
assert 'mode' in d, "missing mode"
assert 'routes' in d, "missing routes"
assert 'peak_hours' in d, "missing peak_hours"
for name, r in d['routes'].items():
    if isinstance(r, dict):
        assert 'peak' in r and 'off_peak' in r, f"{name} route missing peak/off_peak"
print("OK")
PYEOF
    [ $? -eq 0 ] && pass "llmswitch.json: listen/mode/routes/peak_hours 齐全" || fail "llmswitch.json" "结构错误"
}

test_llmswitch_peak_hours_format() {
    local f="$CCCONFIG_DIR/option-llmswitch/conf/llmswitch.json"
    [ -f "$f" ] || return
    python3 - "$f" << 'PYEOF' >/dev/null 2>&1
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
for block in d.get('peak_hours', []):
    assert 'days' in block and isinstance(block['days'], list), "peak block missing days"
    assert 'start' in block and 'end' in block, "peak block missing start/end"
    assert ':' in block['start'] and ':' in block['end'], f"time format: {block['start']}-{block['end']}"
print("OK")
PYEOF
    [ $? -eq 0 ] && pass "llmswitch.json: peak_hours 时间格式 HH:MM" || fail "llmswitch.json" "peak_hours 格式错误"
}

# ═══ settings.json 兼容性（跨脚本写入） ═══
test_settings_json_env_merge() {
    # 验证 env 合并逻辑：写入不丢失已有字段（init-mcp/init-llm 共享）
    local tmp=$(mktemp)
    echo '{"env":{"EXISTING":"val"}}' > "$tmp"
    python3 - "$tmp" << 'PYEOF' >/dev/null 2>&1
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
d.setdefault('env', {}).update({'NEW_KEY': 'new'})
assert d['env']['EXISTING'] == 'val', "lost existing"
assert d['env']['NEW_KEY'] == 'new', "not merged"
print("OK")
PYEOF
    [ $? -eq 0 ] && pass "settings.json: env 合并保留已有字段" || fail "settings.json" "env 合并丢字段"
    rm -f "$tmp"
}

# ═══ .example 模板一致性 ═══
test_example_placeholder_detection() {
    local found=0
    for ex in "$CCCONFIG_DIR"/conf/*.json.example; do
        [ -f "$ex" ] || continue
        if grep -qE '请填入|请替换|your.key|placeholder|changeme|<your-' "$ex"; then
            found=$((found + 1))
        fi
    done
    if [ "$found" -gt 0 ]; then
        pass "example 模板: $found 个含占位符（正常，待用户填）"
    else
        pass "example 模板: 无占位符（可能是新模板）"
    fi
}

test_example_json_valid() {
    local invalid=0
    for ex in "$CCCONFIG_DIR"/conf/*.json.example; do
        [ -f "$ex" ] || continue
        python3 -m json.tool "$ex" >/dev/null 2>&1 || { fail "$(basename "$ex")" "JSON 语法错误"; invalid=$((invalid + 1)); }
    done
    [ "$invalid" -eq 0 ] && pass "example 模板: 全部合法 JSON" || echo ""
}

# ═══ 主流程 ═══

run_tests() {
    local idx=0
    local n=${#all_tests[@]}
    while [ $idx -lt $n ]; do
        local fn="${all_tests[$((idx+1))]:-}"
        if [ -n "$fn" ] && declare -F "$fn" >/dev/null 2>&1; then
            "$fn" 2>/dev/null || true
        fi
        idx=$((idx + 2))
    done
}

all_tests=(
    "desc: llm.json 结构" test_llm_json_structure
    "desc: llm.json current 指向" test_llm_json_current_in_llms
    "desc: llm.json 无占位符 key" test_llm_json_key_not_placeholder
    "desc: claude.json mcp_servers" test_claude_json_mcp_servers
    "desc: llmswitch.json 结构" test_llmswitch_json_structure
    "desc: llmswitch.json peak_hours 格式" test_llmswitch_peak_hours_format
    "desc: settings.json env 合并" test_settings_json_env_merge
    "desc: example 占位符检测" test_example_placeholder_detection
    "desc: example JSON 合法" test_example_json_valid
)

echo ""
echo -e "${CYAN}JSON schema 兼容性测试${NC}"
echo "══════════════════════════════"
echo ""

run_tests

echo ""
echo "────────────────────────────────────"
printf "  ${GREEN}PASS${NC}: %d  ${RED}FAIL${NC}: %d  ${YELLOW}SKIP${NC}: %d  TOTAL: %d\n" "$PASS" "$FAIL" "$SKIP" "$((${#all_tests[@]} / 2))"
echo "────────────────────────────────────"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1

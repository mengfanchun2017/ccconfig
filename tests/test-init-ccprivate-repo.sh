#!/bin/bash
# test-init-ccprivate-repo.sh — unit tests for bin/init-ccprivate-repo.sh config generation + migration
set -euo pipefail

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

CCPRIVATE_DIR="$TMPDIR/ccprivate"
CCCONFIG_DIR="$TMPDIR/ccconfig"
mkdir -p "$CCPRIVATE_DIR/conf" "$CCCONFIG_DIR/conf"

# ── Test 1: gen_llm_json writes to conf/llm.json with real keys ──
echo "=== Test 1: llm.json generation ==="
DEEPSEEK_KEY="sk-test-ds" MINIMAX_KEY="sk-cp-test-mm" CLAUDE_KEY="" DEFAULT_LLM="deepseek" OUT="$CCPRIVATE_DIR/conf/llm.json" python3 << 'PYEOF'
import json, os
llms = {}
dk = os.environ.get("DEEPSEEK_KEY", "")
mk = os.environ.get("MINIMAX_KEY", "")
if dk: llms["deepseek"] = {"name": "DeepSeek", "base_url": "https://api.deepseek.com/anthropic", "model": "deepseek-v4-pro", "key": dk, "small_model": "deepseek-v4-pro"}
if mk: llms["minimax"] = {"name": "MiniMax", "base_url": "https://api.minimaxi.com/anthropic", "model": "MiniMax-M3", "key": mk, "small_model": "MiniMax-M3"}
d = {"llms": llms, "current": "deepseek"}
json.dump(d, open(os.environ["OUT"], "w"), indent=4, ensure_ascii=False)
PYEOF

[ -f "$CCPRIVATE_DIR/conf/llm.json" ] && pass "llm.json at conf/llm.json" || fail "llm.json missing"
KEY=$(python3 -c "import json; print(json.load(open('$CCPRIVATE_DIR/conf/llm.json'))['llms']['deepseek']['key'])")
[[ "$KEY" == "sk-test-ds" ]] && pass "real key preserved" || fail "key is: $KEY"
echo "$KEY" | grep -q "请填入" && fail "placeholder in key!" || pass "no placeholder in key"

# ── Test 2: .generated migration (simulate do_update) ──
echo "=== Test 2: .generated/ migration ==="
mkdir -p "$CCPRIVATE_DIR/conf/.generated"
echo '{"llms":{"deepseek":{"key":"sk-old-migrate","model":"deepseek-v4-pro","base_url":"https://api.deepseek.com/anthropic","name":"DeepSeek","small_model":"deepseek-v4-pro"}},"current":"deepseek"}' > "$CCPRIVATE_DIR/conf/.generated/llm.json"
echo '{"git":{"username":"migrateuser","email":"mig@test.com"}}' > "$CCPRIVATE_DIR/conf/.generated/ubuntu.json"

llm_src=""
[ -f "$CCPRIVATE_DIR/conf/llm.json" ] && llm_src="$CCPRIVATE_DIR/conf/llm.json" || \
  [ -f "$CCPRIVATE_DIR/conf/.generated/llm.json" ] && llm_src="$CCPRIVATE_DIR/conf/.generated/llm.json"
[ -n "$llm_src" ] && pass "migration found old .generated/llm.json" || fail "migration skipped .generated/"

eval "$(LLM_SRC="$llm_src" python3 << 'PYEOF'
import json, os
d = json.load(open(os.environ["LLM_SRC"]))
llms = d.get("llms", {})
for key, var in [("deepseek","DEEPSEEK_KEY")]:
    print(f'{var}={llms.get(key,{}).get("key","")}')
PYEOF
)"
[[ "$DEEPSEEK_KEY" == "sk-old-migrate" ]] && pass "migrated key correct: $DEEPSEEK_KEY" || fail "migrated key: $DEEPSEEK_KEY"

# ── Test 3: symlink resolves to real key ──
echo "=== Test 3: symlink resolution ==="
rm -f "$CCCONFIG_DIR/conf/llm.json"
ln -s "$CCPRIVATE_DIR/conf/llm.json" "$CCCONFIG_DIR/conf/llm.json"
RESOLVED=$(python3 -c "import json; print(json.load(open('$CCCONFIG_DIR/conf/llm.json'))['llms']['deepseek']['key'])")
[[ "$RESOLVED" == "sk-test-ds" ]] && pass "symlink resolves to real key" || fail "symlink resolves to: $RESOLVED"

# ── Test 4: init-llm placeholder guard ──
echo "=== Test 4: placeholder rejection ==="
export SETTINGS="$TMPDIR/settings.json"
echo '{}' > "$SETTINGS"
export API_KEY="请填入你的 DeepSeek API Key" BASE_URL="https://api.deepseek.com/anthropic" MODEL_NAME="deepseek-v4-pro" SMALL_MODEL="deepseek-v4-pro"
python3 << 'PYEOF'
import json, os
env_update = {"ANTHROPIC_BASE_URL": os.environ["BASE_URL"], "ANTHROPIC_MODEL": os.environ["MODEL_NAME"], "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ["SMALL_MODEL"]}
api_key = os.environ["API_KEY"]
if any(kw in api_key for kw in ["请填入", "请替换", "your key", "your_key", "placeholder", "changeme"]):
    pass
else:
    env_update["ANTHROPIC_AUTH_TOKEN"] = api_key
sf = os.environ["SETTINGS"]
try:
    with open(sf) as f: data = json.load(f)
except: data = {}
data.setdefault("env", {}).update(env_update)
json.dump(data, open(sf, "w"), indent=2)
PYEOF

python3 -c "import json; d=json.load(open('$SETTINGS')); assert 'ANTHROPIC_AUTH_TOKEN' not in d.get('env',{})" \
  && pass "placeholder NOT written to settings" || fail "placeholder WAS written!"

# ── Test 5: real key written to settings ──
echo "=== Test 5: real key to settings ==="
echo '{}' > "$SETTINGS"
export API_KEY="sk-real-key-123" BASE_URL="https://api.deepseek.com/anthropic" MODEL_NAME="deepseek-v4-pro" SMALL_MODEL="deepseek-v4-pro"
python3 << 'PYEOF'
import json, os
env_update = {"ANTHROPIC_BASE_URL": os.environ["BASE_URL"], "ANTHROPIC_MODEL": os.environ["MODEL_NAME"], "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ["SMALL_MODEL"]}
api_key = os.environ["API_KEY"]
if any(kw in api_key for kw in ["请填入", "请替换", "your key"]):
    pass
else:
    env_update["ANTHROPIC_AUTH_TOKEN"] = api_key
sf = os.environ["SETTINGS"]
try:
    with open(sf) as f: data = json.load(f)
except: data = {}
data.setdefault("env", {}).update(env_update)
json.dump(data, open(sf, "w"), indent=2)
PYEOF

TOKEN=$(python3 -c "import json; print(json.load(open('$SETTINGS'))['env'].get('ANTHROPIC_AUTH_TOKEN','MISSING'))")
[[ "$TOKEN" == "sk-real-key-123" ]] && pass "real key written: $TOKEN" || fail "key: $TOKEN"

# ── Test 6: regex filters ──
echo "=== Test 6: regex filtering ==="
echo '{"message":"Bad credentials"}' | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$' \
  && fail "JSON should fail regex" || pass "JSON error rejected"
echo "mengfanchun2017" | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$' \
  && pass "valid username passes" || fail "valid username blocked"
echo "" | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$' \
  && fail "empty should fail" || pass "empty rejected"
echo "user-" | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$' \
  && fail "trailing dash should fail" || pass "trailing dash rejected"

# ── Test 7: .example placeholder detection ──
echo "=== Test 7: .example placeholder warn ==="
EXAMPLE="$TMPDIR/test.json"
echo '{"key": "请填入你的 API Key"}' > "$EXAMPLE"
grep -qE '请填入|请替换|your.key|placeholder|changeme' "$EXAMPLE" \
  && pass ".example placeholder detected" || fail ".example placeholder missed"

# ── Test 8+: 结构回归测试（修复的 bug 不复发） ──
_REAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$_REAL_DIR/init-ccprivate-repo.sh"

echo "=== Test 8: ensure_gh_cli binary mkdir ==="
grep -A3 'local tmp="/tmp/gh-install-$$"' "$SCRIPT" | grep -q 'mkdir -p "$tmp"' \
  && pass "binary 安装路径有 mkdir -p" || fail "binary 路径缺 mkdir"

echo "=== Test 9: ensure_gh_cli 跳过项 case ==="
grep -q '0|3)' "$SCRIPT" \
  && pass "跳过项(序号3)有 case 0|3" || fail "跳过项无 case 分支"
grep -q '\[\[ "\$install_choice" == "" \]\]' "$SCRIPT" \
  && fail "仍有死代码 == '' 兼容" || pass "已删 == '' 死代码"

echo "=== Test 10: check_gh_auth confirm 不反转 ==="
# SSH 分支应是"跳过 gh 登录"问句，y→return 0（跳过）
grep -q 'confirm "SSH 已够用，跳过 gh 登录？"' "$SCRIPT" \
  && pass "SSH confirm 文案正确（y=跳过）" || fail "SSH confirm 文案错误/反转"

echo "=== Test 11: A/B 菜单 cancel 处理 ==="
grep -A20 'login_method=\$(menu_select' "$SCRIPT" | grep -q '0)' \
  && pass "A/B 菜单有 0) cancel 分支" || fail "A/B 菜单 cancel 落 *) 走 PAT"

echo "=== Test 12: gh auth login || true ==="
count=$(grep -c 'gh auth login --with-token.*|| true\|gh auth login --web.*|| true\|gh auth login --with-token --hostname github.com || true' "$SCRIPT")
[ "$count" -ge 2 ] \
  && pass "gh auth login 有 || true（$count 处）" || fail "gh auth login 缺 || true（set -e 会杀脚本）"

echo "=== Test 13: rm -rf 改 mv 备份 ==="
if grep -q 'rm -rf "\$CCPRIVATE_DIR"' "$SCRIPT"; then
  fail "仍有 rm -rf ccprivate（违反 code.md）"
else
  pass "rm -rf 已改 mv 备份"
fi
grep -q 'mv "\$CCPRIVATE_DIR" "\$bak"' "$SCRIPT" \
  && pass "do_clone 用 mv 备份" || fail "do_clone 未用 mv"

echo "=== Test 14: LLM 菜单 cancel ==="
awk '/menu_select "默认 LLM"/{f=1} f{print} /esac/{if(f)exit}' "$SCRIPT" > "$TMPDIR/llm-case.txt"
grep -q '0)' "$TMPDIR/llm-case.txt" \
  && pass "LLM 菜单有 0) cancel（防 set -u 崩）" || fail "LLM 菜单无 cancel 分支"

echo "=== Test 15: gen_setup_sh 链接完整性 ==="
# gen_setup_sh heredoc 内应含真实 setup.sh 的关键链接（整文件 grep，模式唯一）
grep -q '.lark-default-account' "$SCRIPT" \
  && pass "gen_setup_sh 含 .lark-default-account" || fail "gen_setup_sh 缺 .lark-default-account"
grep -q '.claudeignore' "$SCRIPT" \
  && pass "gen_setup_sh 含 .claudeignore" || fail "gen_setup_sh 缺 .claudeignore"
grep -q 'skill-local' "$SCRIPT" \
  && pass "gen_setup_sh 含 skill-local" || fail "gen_setup_sh 缺 skill-local"
grep -q "tr '/' '-'" "$SCRIPT" \
  && pass "gen_setup_sh memory 用 tr 动态 ID" || fail "gen_setup_sh memory 未用 tr 动态 ID"
grep -q 'should-compact' "$SCRIPT" \
  && pass "gen_setup_sh 含 should-compact" || fail "gen_setup_sh 缺 should-compact"
grep -q 'llmswitch' "$SCRIPT" \
  && pass "gen_setup_sh 含 llmswitch" || fail "gen_setup_sh 缺 llmswitch"

echo "=== Test 16: do_update eval shlex.quote ==="
grep -A8 'eval "\$(LLM_SRC=' "$SCRIPT" | grep -q 'shlex' \
  && pass "do_update eval 用 shlex.quote 防注入" || fail "do_update eval 未引号化"

echo "=== Test 17: source 顺序 ==="
if grep -n 'source.*lib/' "$SCRIPT" | awk -F: '{print $1}' | head -3 | \
   awk 'NR==1{n=$1} NR==2{print ($1>n)? "ok":"bad"}' | grep -q ok; then
  # colors.sh 应在 interact.sh 之前
  line_colors=$(grep -n 'source.*lib/colors.sh' "$SCRIPT" | head -1 | cut -d: -f1)
  line_interact=$(grep -n 'source.*lib/interact.sh' "$SCRIPT" | head -1 | cut -d: -f1)
  [ "$line_colors" -lt "$line_interact" ] \
    && pass "colors.sh 先于 interact.sh" || fail "source 顺序错误"
else
  fail "无法解析 source 顺序"
fi

echo ""
echo "===================="
echo "Pass: $PASS  Fail: $FAIL"
echo "===================="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" && exit 0
echo "SOME TESTS FAILED"
exit 1

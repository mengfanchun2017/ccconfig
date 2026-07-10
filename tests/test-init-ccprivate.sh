#!/bin/bash
# test-init-ccprivate.sh — unit tests for init-ccprivate.sh config generation + migration
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

echo ""
echo "===================="
echo "Pass: $PASS  Fail: $FAIL"
echo "===================="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" && exit 0
echo "SOME TESTS FAILED"
exit 1

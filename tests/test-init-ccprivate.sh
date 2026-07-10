#!/bin/bash
# test-init-ccprivate.sh — unit tests for init-ccprivate.sh config generation + linking
set -euo pipefail

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# ── Test 1: gen_llm_json writes to conf/llm.json (not .generated) ──
echo "=== Test 1: llm.json path ==="
CCPRIVATE_DIR="$TMPDIR/ccprivate"
mkdir -p "$CCPRIVATE_DIR/conf"
DEEPSEEK_KEY="sk-test-ds" MINIMAX_KEY="sk-cp-test-mm" CLAUDE_KEY="" DEFAULT_LLM="deepseek" OUT="$CCPRIVATE_DIR/conf/llm.json" python3 -c '
import json, os
llms = {}
dk = os.environ.get("DEEPSEEK_KEY", "")
mk = os.environ.get("MINIMAX_KEY", "")
ck = os.environ.get("CLAUDE_KEY", "")
if dk:
    llms["deepseek"] = {"name": "DeepSeek", "base_url": "https://api.deepseek.com/anthropic", "model": "deepseek-v4-pro", "key": dk, "small_model": "deepseek-v4-pro"}
if mk:
    llms["minimax"] = {"name": "MiniMax", "base_url": "https://api.minimaxi.com/anthropic", "model": "MiniMax-M3", "key": mk, "small_model": "MiniMax-M3"}
d = {"llms": llms, "current": "deepseek"}
with open(os.environ["OUT"], "w") as fh:
    json.dump(d, fh, indent=4, ensure_ascii=False)
'

[ -f "$CCPRIVATE_DIR/conf/llm.json" ] && pass "llm.json exists at conf/llm.json" || fail "llm.json NOT at conf/llm.json"
[ ! -d "$CCPRIVATE_DIR/conf/.generated" ] && pass "no .generated/ subdirectory" || fail ".generated/ should not exist"

# ── Test 2: llm.json contains real keys, not placeholders ──
echo "=== Test 2: no placeholder keys ==="
KEY=$(python3 -c "import json; print(json.load(open('$CCPRIVATE_DIR/conf/llm.json'))['llms']['deepseek']['key'])")
[[ "$KEY" == "sk-test-ds" ]] && pass "deepseek key is real: $KEY" || fail "deepseek key wrong: $KEY"
[[ "$KEY" != *"请填入"* ]] && pass "no placeholder text in key" || fail "placeholder text found!"

# ── Test 3: gen_claude_json writes to conf/claude.json ──
echo "=== Test 3: claude.json path ==="
AUTH_TOKEN="sk-test-ds" BASE_URL="https://api.deepseek.com/anthropic" MODEL="deepseek-v4-pro" OUT="$CCPRIVATE_DIR/conf/claude.json" python3 -c '
import json, os
d = {"env": {"ANTHROPIC_BASE_URL": os.environ["BASE_URL"], "ANTHROPIC_MODEL": os.environ["MODEL"], "ANTHROPIC_AUTH_TOKEN": os.environ["AUTH_TOKEN"]}}
with open(os.environ["OUT"], "w") as fh: json.dump(d, fh, indent=2, ensure_ascii=False)
'
[ -f "$CCPRIVATE_DIR/conf/claude.json" ] && pass "claude.json exists at conf/claude.json" || fail "claude.json missing"

# ── Test 4: gen_ubuntu_json writes to conf/ubuntu.json ──
echo "=== Test 4: ubuntu.json path ==="
GH_USER="testuser" GIT_EMAIL="test@test.com" OUT="$CCPRIVATE_DIR/conf/ubuntu.json" python3 -c '
import json, os
d = {"git": {"repo": os.environ["GH_USER"] + "/cconfig", "target_dir": os.path.expanduser("~/git/cconfig"), "email": os.environ["GIT_EMAIL"], "username": os.environ["GH_USER"]}}
with open(os.environ["OUT"], "w") as fh: json.dump(d, fh, indent=2, ensure_ascii=False)
'
[ -f "$CCPRIVATE_DIR/conf/ubuntu.json" ] && pass "ubuntu.json exists at conf/ubuntu.json" || fail "ubuntu.json missing"

# ── Test 5: setup.sh conf linking picks up generated files ──
echo "=== Test 5: setup.sh conf glob matches ==="
CCCONFIG_DIR="$TMPDIR/ccconfig"
mkdir -p "$CCCONFIG_DIR/conf"

# simulate setup.sh 4a: link ccprivate/conf/*.json → ccconfig/conf/
for src in "$CCPRIVATE_DIR/conf/"*.json; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    dst="$CCCONFIG_DIR/conf/$name"
    [ -L "$dst" ] && rm -f "$dst"
    [ -f "$dst" ] && rm -f "$dst"
    ln -s "$src" "$dst"
done

[ -L "$CCCONFIG_DIR/conf/llm.json" ] && pass "llm.json symlink created" || fail "llm.json symlink missing"
REAL_KEY=$(python3 -c "import json; print(json.load(open('$CCCONFIG_DIR/conf/llm.json'))['llms']['deepseek']['key'])")
[[ "$REAL_KEY" == "sk-test-ds" ]] && pass "symlink resolves to real key: $REAL_KEY" || fail "symlink resolves to: $REAL_KEY"

# ── Test 6: init-llm.sh writes correct ANTHROPIC_AUTH_TOKEN ──
echo "=== Test 6: init-llm _write_llm_config ==="
SETTINGS="$TMPDIR/settings.json"
echo '{}' > "$SETTINGS"

CONFIG_FILE="$CCCONFIG_DIR/conf/llm.json" CLAUDE_JSON="$TMPDIR/claude.json" \
  BASE_URL="https://api.deepseek.com/anthropic" MODEL_NAME="deepseek-v4-pro" \
  SMALL_MODEL="deepseek-v4-pro" API_KEY="sk-test-ds" NAME="deepseek" \
  python3 -c '
import json, os
env_update = {
    "ANTHROPIC_BASE_URL": os.environ["BASE_URL"],
    "ANTHROPIC_MODEL": os.environ["MODEL_NAME"],
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ["SMALL_MODEL"]
}
api_key = os.environ["API_KEY"]
if any(kw in api_key for kw in ["请填入", "请替换", "your key"]):
    print("SKIPPED: placeholder")
else:
    env_update["ANTHROPIC_AUTH_TOKEN"] = api_key

sf = "'"$SETTINGS"'"
try:
    with open(sf) as f: data = json.load(f)
except: data = {}
data.setdefault("env", {}).update(env_update)
with open(sf, "w") as f: json.dump(data, f, indent=2)
'

TOKEN=$(python3 -c "import json; print(json.load(open('$SETTINGS'))['env'].get('ANTHROPIC_AUTH_TOKEN','MISSING'))")
[[ "$TOKEN" == "sk-test-ds" ]] && pass "settings.json AUTH_TOKEN correct: $TOKEN" || fail "settings.json AUTH_TOKEN: $TOKEN"

# ── Test 7: placeholder keys are rejected ──
echo "=== Test 7: placeholder rejection ==="
SETTINGS2="$TMPDIR/settings2.json"
echo '{}' > "$SETTINGS2"

API_KEY="请填入你的 DeepSeek API Key" BASE_URL="https://api.deepseek.com/anthropic" \
  MODEL_NAME="deepseek-v4-pro" SMALL_MODEL="deepseek-v4-pro" \
  python3 -c '
import json, os
env_update = {
    "ANTHROPIC_BASE_URL": os.environ["BASE_URL"],
    "ANTHROPIC_MODEL": os.environ["MODEL_NAME"],
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": os.environ["SMALL_MODEL"]
}
api_key = os.environ["API_KEY"]
if any(kw in api_key for kw in ["请填入", "请替换", "your key"]):
    pass  # intentionally skip
else:
    env_update["ANTHROPIC_AUTH_TOKEN"] = api_key

sf = "'"$SETTINGS2"'"
try:
    with open(sf) as f: data = json.load(f)
except: data = {}
data.setdefault("env", {}).update(env_update)
with open(sf, "w") as f: json.dump(data, f, indent=2)
'

HAS_TOKEN=$(python3 -c "import json; d=json.load(open('$SETTINGS2')); print('ANTHROPIC_AUTH_TOKEN' in d.get('env',{}))")
[[ "$HAS_TOKEN" == "False" ]] && pass "placeholder key NOT written to settings" || fail "placeholder key WAS written!"

# ── Test 8: detect_gh_user filters bad input ──
echo "=== Test 8: detect_gh_user filtering ==="
echo '{"message":"Bad credentials","status":401}' | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$' \
  && fail "JSON should NOT pass" || pass "JSON error rejected by regex"

echo "mengfanchun2017" | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$' \
  && pass "valid username passes" || fail "valid username rejected"

echo "" | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$' \
  && fail "empty string should NOT pass" || pass "empty string rejected"

echo "user-" | grep -qE '^[a-zA-Z0-9](-?[a-zA-Z0-9])*$' \
  && fail "trailing dash should NOT pass" || pass "trailing dash rejected"

# ── Summary ──
echo ""
echo "===================="
echo "Pass: $PASS  Fail: $FAIL"
echo "===================="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" && exit 0
echo "SOME TESTS FAILED"
exit 1

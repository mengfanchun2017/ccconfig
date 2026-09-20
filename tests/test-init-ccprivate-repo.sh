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
SCRIPT="$_REAL_DIR/init-bootstrap.sh"
SETUP_TPL="$_REAL_DIR/templates/ccprivate-setup.sh"

echo "=== Test 8: gh 安装临时目录独占 ==="
# 固定 /tmp/gh-install-$$ 在两个 job 并行时会互相覆盖解包目录
grep -q 'tmp=$(mktemp -d' "$SCRIPT" \
  && pass "gh 安装用 mktemp -d 独占临时目录" || fail "gh 安装仍用固定 /tmp 路径"

echo "=== Test 9: 死代码回归 ==="
grep -q '\[\[ "\$install_choice" == "" \]\]' "$SCRIPT" \
  && fail "仍有死代码 == '' 兼容" || pass "已删 == '' 死代码"

echo "=== Test 10: check_gh_auth confirm 不反转 ==="
# SSH 分支应是"跳过 gh 登录"问句，y→return 0（跳过）
grep -q 'confirm "SSH 已够用，跳过 gh 登录？"' "$SCRIPT" \
  && pass "SSH confirm 文案正确（y=跳过）" || fail "SSH confirm 文案错误/反转"

echo "=== Test 11: 认证方式菜单 cancel 处理 ==="
grep -A20 'method=\$(menu_select "认证方式"' "$SCRIPT" | grep -q '0)' \
  && pass "认证菜单有 0) cancel 分支" || fail "认证菜单 cancel 落 *) 走 PAT"

echo "=== Test 12: gh auth login || true ==="
count=$(grep -c 'gh auth login.*|| true' "$SCRIPT")
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

echo "=== Test 15: setup.sh 模板完整性 ==="
# setup.sh 内容住在 templates/ccprivate-setup.sh（唯一真相源），
# init-bootstrap.sh 与 lib/ccprivate-upgrade.sh 都 cp 它，不再各自内嵌
grep -q '.lark-default-account' "$SETUP_TPL" \
  && pass "模板含 .lark-default-account" || fail "模板缺 .lark-default-account"
grep -q '.claudeignore' "$SETUP_TPL" \
  && pass "模板含 .claudeignore" || fail "模板缺 .claudeignore"
grep -q 'skill-local' "$SETUP_TPL" \
  && pass "模板含 skill-local" || fail "模板缺 skill-local"
grep -q "tr '/' '-'" "$SETUP_TPL" \
  && pass "模板 memory 用 tr 动态 ID" || fail "模板 memory 未用 tr 动态 ID"
# 反向断言：should-compact.md 已废弃（ccconfig/commands/ 目录已删），模板不应再建其链接
# 注意匹配 setup_link 调用而非注释里提到的文件名
grep -qE 'setup_link.*should-compact' "$SETUP_TPL" \
  && fail "模板仍建已废弃的 should-compact 链接" || pass "模板不含 should-compact 链接（已废弃）"
# 反向断言：本机文件必须走 install_user_file（symlink 会跨机覆盖），且不再内嵌副本
grep -q 'install_user_file' "$SETUP_TPL" \
  && pass "模板用 install_user_file 建本机文件" || fail "模板未用 install_user_file"
grep -q 'cp "\$tpl" "\$CCPRIVATE_DIR/setup.sh"' "$SCRIPT" \
  && pass "gen_setup_sh 走 cp 模板（防内嵌副本漂移）" || fail "gen_setup_sh 未走模板"
grep -q 'llmswitch' "$SETUP_TPL" \
  && fail "模板仍含已废弃的 llmswitch" || pass "模板不含 llmswitch（gateway 已清）"
# 反向断言：CLAUDE.md 模板也必须走 cp（内嵌副本曾漂移到已改名的 f-research-domain）
UPGRADE="$_REAL_DIR/lib/ccprivate-upgrade.sh"
grep -q 'LINK_CLAUDE_MD=' "$UPGRADE" \
  && fail "ccprivate-upgrade 仍内嵌 CLAUDE.md 副本（会漂移）" || pass "CLAUDE.md 已抽出内嵌副本"
grep -q 'templates/CLAUDE.md.example' "$UPGRADE" \
  && pass "fix_link_content 走 templates/CLAUDE.md.example 模板" || fail "fix_link_content 未走模板"

echo "=== Test 16: do_update 不重建仓库侧配置（防 preset/Key 被覆盖） ==="
# gen_llm_json 只认 deepseek/minimax 两个 key，重建 llm.json 会抹掉其余 preset；
# gen_mcp_servers_json 无条件 cp 占位模板，会盖掉真实 mcp-servers.json 的 key。
# --update 的职责是恢复"本机侧"链接，不碰"仓库侧"配置。
awk '/^do_update\(\)/,/^}/' "$SCRIPT" | grep -vE '^[[:space:]]*#' \
  | grep -qE '^[[:space:]]*(gen_llm_json|gen_mcp_servers_json)' \
  && fail "do_update 仍重建 llm.json/mcp-servers.json（数据丢失）" \
  || pass "do_update 不碰仓库侧配置"

# ── Test 18+: 新机安装/恢复配置可靠性回归 ──
echo "=== Test 18: ccprivate 分支名不硬编码 main ==="
# 实际 ccprivate 仓库分支是 master；硬编码 main 会让 --update/--clone
# 报 could-not-find-remote-ref-main，且 pipefail 把 set -e 带崩、后续重建全跳过
grep -qE "pull origin main|push -u origin main" "$SCRIPT" \
  && fail "仍有硬编码 main 分支" || pass "pull/push 不再硬编码 main"
grep -q '^default_branch()' "$SCRIPT" \
  && pass "default_branch() 已定义" || fail "default_branch() 缺失"

echo "=== Test 19: 拉取失败降级，不终止恢复链 ==="
grep -A2 'pull origin "\$br"' "$SCRIPT" | grep -q '|| warn' \
  && pass "pull 失败降级为 warn" || fail "pull 失败仍会 set -e 终止后续步骤"

echo "=== Test 20: setup.sh 缺失可自愈 ==="
grep -q '^ensure_setup_sh()' "$SCRIPT" \
  && pass "ensure_setup_sh() 已定义" || fail "缺 ensure_setup_sh()（老 ccprivate 上 set -e 直接死）"
[[ $(grep -c 'ensure_setup_sh || return 1' "$SCRIPT") -ge 3 ]] \
  && pass "3 处调用点都做了守卫" || fail "ensure_setup_sh 调用点未全守卫"

echo "=== Test 21: link/CLAUDE.md 走模板，不再内嵌副本 ==="
# 内嵌副本曾与 templates/CLAUDE.md.example 不一致 → 新机 bootstrap 和老机 upgrade
# 拿到两份不同的用户级 CLAUDE.md
grep -q "templates/CLAUDE.md.example" "$SCRIPT" \
  && pass "gen_claude_md 走 templates/CLAUDE.md.example" || fail "gen_claude_md 仍内嵌副本"
grep -q '## 权限$' "$SCRIPT" \
  && fail "init-bootstrap 仍内嵌 CLAUDE.md 正文" || pass "init-bootstrap 无内嵌 CLAUDE.md 正文"

echo "=== Test 22: 首装写权威 llm-current ==="
# ADR-0020：当前选择归 ~/.claude/llm-current；llm.json.current 是废弃字段。
# 不写 llm-current，init-base.sh 的 LLM 步骤只能靠"回落废弃字段"碰巧工作。
awk '/^do_create\(\)/,/^}/' "$SCRIPT" | grep -q 'write_local_current' \
  && pass "do_create 写 llm-current" || fail "do_create 未写 llm-current"
awk '/^do_update\(\)/,/^}/' "$SCRIPT" | grep -q 'write_local_current' \
  && fail "do_update 会覆盖本机 llm-current" || pass "do_update 不碰 llm-current"

echo "=== Test 23: 本机文件补齐模板基线键 ==="
# init-ubuntu(setup_hook)/init-llm 都可能先于 setup.sh 创建 settings.json，
# 旧逻辑"已存在即跳过"→ permissions/hooks/statusLine 永不写入，status 还报绿
grep -q '补齐缺失键' "$SETUP_TPL" \
  && pass "install_user_file 补齐缺失基线键" || fail "install_user_file 仍一律跳过"
grep -q 'missing = \[k for k in t if k not in d\]' "$SETUP_TPL" \
  && pass "只补顶层缺失键、不覆盖已有键" || fail "补齐逻辑缺失或会覆盖已有键"

echo "=== Test 24: clone 模式也配 git 身份 ==="
# 缺这一步，恢复回来的机器没有 user.name/email，auto-sync 提交会失败
awk '/^if \$CLONE_MODE; then/,/^fi/' "$SCRIPT" | grep -q 'setup_git_ident' \
  && pass "clone 模式调用 setup_git_ident" || fail "clone 模式缺 setup_git_ident"

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

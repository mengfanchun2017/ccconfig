#!/bin/bash
# test-ccprivate-boundary.sh — 公开仓/私有仓边界回归测试
#
# 背景（2026-10-27 审计后清理，见 memory skill-repo-split-audit-20261027）：
#   skill-local 层、2 个无用 agent、usage CSV 目录全部删除，agent/skill 实体统一
#   放公开的 ~/git/skill。本测试锁死这些决定，防止它们被"顺手"复活。
#
# 测试的是**真实仓文件与脚本**，不是复制粘贴的副本 —— 副本会与实现漂移。

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CCPRIV="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

PASS=0; FAIL=0
_pass() { echo -e "  \033[0;32m✅\033[0m $1"; PASS=$((PASS+1)); }
_fail() { echo -e "  \033[0;31m❌\033[0m $1"; FAIL=$((FAIL+1)); }

# 断言：某文件/目录不应存在
_absent() { [ ! -e "$1" ] && _pass "$2" || _fail "$2（仍存在: $1）"; }
# 断言：某文件里不应出现某模式
_no_pat() { ! grep -qE "$2" "$1" 2>/dev/null && _pass "$3" || _fail "$3"; }
# 断言：某文件里应出现某模式
_has_pat() { grep -qE "$2" "$1" 2>/dev/null && _pass "$3" || _fail "$3"; }

echo ""
echo "═══ ccprivate 边界（公开/私有 分工）回归测试 ═══"
echo "  ccconfig: $REPO"
echo "  ccprivate: $CCPRIV"
echo ""

# ── 1. 已删项不得复活 ──
echo "── 1. 已删项不得复活 ──"
_absent "$REPO/templates/agents"  "templates/agents 已删（agent 不与公开模板同步）"
_absent "$CCPRIV/skill-local"     "ccprivate/skill-local 已删"
_absent "$CCPRIV/usage"           "ccprivate/usage 已删"
_absent "$CCPRIV/CLAUDE.md"       "ccprivate/CLAUDE.md 已删（该仓不按项目启动）"
for f in settings.json .config.json .claudeignore; do
    _absent "$CCPRIV/link/$f.example" "ccprivate/link/$f.example 已删（模板唯一真相源在 ccconfig/templates）"
done

# ── 2. 脚本不得再重建已删项 ──
echo ""
echo "── 2. 脚本不得重建已删项 ──"
_TPL="$REPO/templates/ccprivate-setup.sh"
_no_pat "$_TPL" 'mkdir -p .*skill-local'   "setup.sh 模板不再 mkdir skill-local"
_has_pat "$_TPL" 'install_user_file.*_TDIR|install_user_file.*templates' "setup.sh 模板从 ccconfig/templates 取本机文件模板"
_no_pat "$_TPL" 'install_user_file.*SCRIPT_DIR/link/' "setup.sh 模板不再指 link/*.example"

_UPG="$REPO/lib/ccprivate-upgrade.sh"
_no_pat "$_UPG" 'expected=.*skill-local'  "ccprivate-upgrade 不再把 skill-local 列为必备目录"
_no_pat "$_UPG" 'dirs=.*skill-local'      "ccprivate-upgrade 不再创建 skill-local"
_no_pat "$_UPG" 'cp "\$CCCONFIG_DIR/templates/\$f.example" "\$CCPRIVATE/link/\$f.example"' \
    "ccprivate-upgrade 不再往 link/ 复制模板副本"

_MAINT="$REPO/maintain.sh"
_no_pat "$_MAINT" 'expected_dirs=.*skill-local' "maintain fix 不再补建 skill-local"

_SYNC="$REPO/lib/sync.sh"
_no_pat "$_SYNC" 'templates/agents' "sync.sh 不再复制 agents 模板"

# 匹配路径用法（templates/agents/ 或 templates/agents:），不匹配解释性注释里的
# "templates/agents 这条链已删" —— 注释里提及历史是允许的，代码里用才算复活。
_BOOT="$REPO/init-bootstrap.sh"
_no_pat "$_BOOT" 'templates/agents[/:]' "init-bootstrap 不再复制 agents 模板"

_ES="$REPO/lib/example-sync.sh"
_no_pat "$_ES" 'templates/agents[/:]' "example-sync 不再映射 templates/agents"

# ── 3. status 不得因目录不存在而误报 ──
echo ""
echo "── 3. status 检查项 ──"
_ST="$REPO/lib/status.sh"
_no_pat "$_ST" 'ccconfig_example/agents' "status 不再比对已删的 agents 模板"
_has_pat "$_ST" 'agents_count' "status 改报 agents 数量"

# ── 4. skill 层只剩单源 ──
echo ""
echo "── 4. skill 单源 ──"
_IS="$REPO/lib/init-skill.sh"
_has_pat "$_IS" '遗留私有 skill 链接' "init-skill 会清理老机器上遗留的私有 skill 链接"
_no_pat "$_IS" '_dep_srcs\+=\("\$LOCAL_SKILLS_SRC"\)' "init-skill 依赖扫描不再含私有源"
_no_pat "$_IS" '_dep_srcs\+=\("\$LOCAL_SKILLS_SRC"\)' "init-skill 依赖扫描单源"

# ── 5. 私有值不得泄进公开仓 ──
echo ""
echo "── 5. 公开仓无私有真值 ──"
if [ -f "$REPO/lib/secret-patterns.sh" ]; then
    # shellcheck source=/dev/null
    source "$REPO/lib/secret-patterns.sh"
    hits=$(grep -rlE "$SECRET_RE" "$REPO" \
        --include=*.sh --include=*.py --include=*.json --include=*.md \
        --exclude-dir=.git --exclude-dir=tests 2>/dev/null || true)
    [ -z "$hits" ] && _pass "公开仓无凭据形状命中" \
                   || _fail "公开仓有凭据形状命中: $(echo "$hits" | head -3 | tr '\n' ' ')"
else
    _fail "secret-patterns.sh 缺失，无法扫描"
fi

echo ""
echo "──────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
    echo -e "\033[0;32mPASS: $PASS  FAIL: 0\033[0m"
else
    echo -e "\033[0;31mPASS: $PASS  FAIL: $FAIL\033[0m"
fi
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
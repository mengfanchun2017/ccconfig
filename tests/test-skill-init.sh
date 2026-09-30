#!/bin/bash
# test-skill-init.sh — init-skill.sh 命令入口完整性回归测试
#
# 覆盖：
#   - 所有命令入口（sync/sync-lite/update/...）case 分支存在
#   - sync-lite → do_sync 1（跳技能 symlink，避免 3A 里与 link-only 重复扫描）
#   - do_sync 的 _lite 跳过 do_link_self_built 逻辑在位
#   - 各入口调用的函数体均存在
#
# 用法: bash tests/test-skill-init.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IS="$CCCONFIG_DIR/lib/init-skill.sh"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

echo ""
echo "init-skill.sh 命令入口回归"
echo "══════════════════════════"
echo ""

# ── 1. 文件存在 + 语法（bash -n，与 test-syntax 互补）──
echo "=== 1. 存在与语法 ==="
[[ -f "$IS" ]] && pass "init-skill.sh 存在" || fail "init-skill.sh 缺失"
bash -n "$IS" && pass "bash -n 语法" || fail "bash -n 失败"

# ── 2. 命令入口全部注册 ──
echo "=== 2. 命令入口注册 ==="
declare -A CMDS=( [sync]=do_sync [sync-lite]="do_sync 1" [update]=do_update [remove]=do_remove \
                  [cleanup]=do_cleanup [list]=do_list [status]=do_status [diff]=do_diff \
                  [link-single]=do_link_single [link-only]=do_link_self_built )
for name in "${!CMDS[@]}"; do
    grep -qE "[[:space:]]${name}\))" "$IS" && pass "命令 $name 已注册" || fail "命令 $name 未注册"
done

# sync-lite 展开为 do_sync 1（跳过技能 symlink 的关键）
[[ "$(grep -oE 'sync-lite\)  *do_sync ?1;' "$IS")" == *"do_sync 1"* ]] \
    && pass "sync-lite → do_sync 1" || fail "sync-lite 未指向 do_sync 1"

# ── 3. do_sync 的 _lite 跳过技能 symlink ──
echo "=== 3. sync-lite 跳过技能扫描 ==="
# do_sync 必须在 _lite==1 时跳过 do_link_self_built（技能扫描由 setup.sh 的 link-only 承担）
grep -q '\[\[ "$_lite" == "1" \]\] || do_link_self_built' "$IS" \
    && pass "_lite=1 跳过 do_link_self_built" || fail "缺少 _lite 跳过 do_link_self_built 逻辑"
# 完整 sync 必须仍执行技能 symlink
grep -qE '^do_sync\(\)' "$IS" \
    && ! grep -A3 '^do_sync()' "$IS" | grep -qE '^[[:space:]]*do_link_self_built$' \
    && pass "技能扫描仍在 do_sync 内（条件调用）" || fail "do_sync 技能扫描调用异常"
# bare 标题路径存在：sync-lite 用无编号标题避免 1→0 段号错乱
grep -q 'if \[\[.*\${\1:-0}\|\[\"\${1:-0}\" == \"1\"\]\]' "$IS" >/dev/null 2>&1 || true
grep -q '"1" ]]; then' "$IS" && pass "bare 标题分支存在（_lite 无编号）" || fail "bare 标题分支缺失"

# ── 4. 各入口调用的函数体存在 ──
echo "=== 4. 函数体存在 ==="
for fn in do_sync do_update do_remove do_cleanup do_list do_status do_diff \
          do_link_single do_link_self_built do_install_cli_deps do_apply_ccprivate_config; do
    grep -qE "^${fn}\(\)" "$IS" && pass "函数 $fn 存在" || fail "函数 $fn 缺失"
done

# usage 文案含 sync-lite
grep -q 'sync-lite' "$IS" && pass "usage 文案含 sync-lite" || fail "usage 缺 sync-lite"

echo ""
echo "──────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}PASS: $PASS  FAIL: $FAIL${NC}"
    exit 0
else
    echo -e "${RED}PASS: $PASS  FAIL: $FAIL${NC}"
    exit 1
fi
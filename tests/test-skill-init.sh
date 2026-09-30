#!/bin/bash
# test-skill-init.sh — init-skill.sh 命令入口完整性回归测试
#
# 覆盖：
#   - 所有命令入口 case 分支存在
#   - sync-lite → do_sync 1（跳技能 symlink，避免 3A 里与 link-only 重复扫描）
#   - do_sync 的 _lite 跳过 do_link_self_built 逻辑在位
#   - bare 标题分支（sync-lite 用无编号标题，避免 1→0 段号错乱）
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

# ── 1. 存在 + 语法 ──
echo "=== 1. 存在与语法 ==="
[[ -f "$IS" ]] && pass "init-skill.sh 存在" || fail "init-skill.sh 缺失"
bash -n "$IS" && pass "bash -n 语法" || fail "bash -n 失败"

# ── 2. 命令入口全部注册 ──
echo "=== 2. 命令入口注册 ==="
for name in sync sync-lite update remove cleanup list status diff link-single link-only; do
    if grep -qE "^[[:space:]]*${name}\)" "$IS"; then
        pass "命令 $name 已注册"
    else
        fail "命令 $name 未注册"
    fi
done

# sync-lite 展开为 do_sync 1
if grep -qE "sync-lite\)[[:space:]]*do_sync[[:space:]]+1[[:space:]]*;;" "$IS"; then
    pass "sync-lite → do_sync 1"
else
    fail "sync-lite 未指向 do_sync 1"
fi

# ── 3. sync-lite 跳过技能扫描 ──
echo "=== 3. sync-lite 跳过技能扫描 ==="
grep -q '\[\[ "$_lite" == "1" \]\] || do_link_self_built' "$IS" \
    && pass "_lite=1 跳过 do_link_self_built" || fail "缺少 _lite 跳过 do_link_self_built 逻辑"
# do_sync 里 do_link_self_built 是条件调用（非裸调）——保证完整 sync 仍扫技能
awk '/^do_sync\(\)/,/^}/' "$IS" | grep -q 'do_link_self_built' \
    && pass "do_sync 内仍含技能扫描（条件调用）" || fail "do_sync 技能扫描调用异常"
# bare 标题分支：do_install_cli_deps / do_apply_ccprivate_config 支持 ${1:-0} 判定
cnt=$(grep -cE '\[\[ "\$\{1:-0\}" == "1" \]\]' "$IS")
[[ "$cnt" -ge 2 ]] && pass "bare 标题分支存在（CLI 依赖 + 配置覆盖）($cnt 处)" \
                    || fail "bare 标题分支不足 (仅 $cnt 处)"

# ── 4. 函数体存在 ──
echo "=== 4. 函数体存在 ==="
for fn in do_sync do_update do_remove do_cleanup do_list do_status do_diff \
          do_link_single do_link_self_built do_install_cli_deps do_apply_ccprivate_config; do
    grep -qE "^${fn}\(\)" "$IS" && pass "函数 $fn 存在" || fail "函数 $fn 缺失"
done

grep -q 'sync-lite' "$IS" && pass "usage 文案含 sync-lite" || fail "usage 缺 sync-lite"

echo ""
echo "──────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo -e "\033[0;32mPASS: $PASS  FAIL: $FAIL\033[0m"
    exit 0
else
    echo -e "\033[0;31mPASS: $PASS  FAIL: $FAIL\033[0m"
    exit 1
fi
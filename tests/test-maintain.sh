#!/bin/bash
# test-maintain.sh — maintain.sh 数据层/子菜单/入口回归测试
#
# 覆盖：
#   - 语法 + MAINTAIN_TEST_MODE guard
#   - MENU_ENTRIES 完整性：字段数、分类、退出项
#   - action 引用的脚本/函数全部存在；submenu:xxx → _submenu_xxx 已定义
#   - menu_loop 死代码清除（无 selected/items 残留）
#   - menu_select 取消契约（cancel="0"）
#   - _submenu_usage timer case 回归（数字分支，非字母 i/u/c）
#   - 顶层 feishu case 无 local（set -e 不中断）
#   - SCRIPT_DIR 单赋值（无重复）
#   - pty：菜单渲染一次、q 干净退出、无堆叠
#
# 用法: bash tests/test-maintain.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1${2:+ — $2}"; FAIL=$((FAIL+1)); }

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── 1. 语法 ──
echo "=== 1. 语法检查 ==="
for f in maintain.sh lib/menu-data-maintain.sh lib/menu-feishu.sh lib/interact.sh; do
    bash -n "$CCCONFIG_DIR/$f" 2>/dev/null && pass "$f syntax" || fail "$f syntax"
done

# ── 2. guard ──
echo "=== 2. MAINTAIN_TEST_MODE guard ==="
grep -q 'MAINTAIN_TEST_MODE' "$CCCONFIG_DIR/maintain.sh" && pass "guard 存在" || fail "guard 缺失"

# ── 3. source 加载函数/数据 ──
echo "=== 3. 加载函数 + MENU_ENTRIES ==="
eval "$(MAINTAIN_TEST_MODE=1 bash -c '
source "'"$CCCONFIG_DIR"'/lib/colors.sh" 2>/dev/null || true
source "'"$CCCONFIG_DIR"'/lib/path-helper.sh" 2>/dev/null || true
source "'"$CCCONFIG_DIR"'/lib/interact.sh"
source "'"$CCCONFIG_DIR"'/lib/menu-data-maintain.sh"
' 2>/dev/null)"
# submenu 函数定义在 maintain.sh 主体，单独 source
# 注意：maintain.sh 内部 set -euo pipefail 会打开 set -e，source 后重置避免测试误中断
MAINTAIN_TEST_MODE=1 source "$CCCONFIG_DIR/maintain.sh" 2>/dev/null
set +e

[[ "${#MENU_ENTRIES[@]}" -gt 0 ]] && pass "MENU_ENTRIES 已加载 (${#MENU_ENTRIES[@]} 条)" || fail "MENU_ENTRIES 空"

# ── 4. MENU_ENTRIES 字段完整性 + 退出项 ──
echo "=== 4. MENU_ENTRIES 完整性 ==="
has_exit=false
bad_fields=0
for entry in "${MENU_ENTRIES[@]}"; do
    local_fields=$(echo "$entry" | awk -F'|' '{print NF}')
    [[ "$local_fields" -eq 6 ]] || bad_fields=$((bad_fields+1))
    echo "$entry" | grep -q '^0|' && has_exit=true
done
$has_exit && pass "含退出项 (cat=0)" || fail "缺退出项"
[[ $bad_fields -eq 0 ]] && pass "所有条目 6 字段" || fail "字段数不对" "$bad_fields 条"

# ── 5. action/submenu 引用解析 ──
echo "=== 5. action/submenu 引用 ==="
missing=0
for entry in "${MENU_ENTRIES[@]}"; do
    IFS='|' read -r cat letter title desc action submenu <<< "$entry"
    cat=$(trim "$cat"); letter=$(trim "$letter")
    [[ "$cat" == "0" ]] && continue
    # submenu:xxx → _submenu_xxx 必须已定义
    if [[ -n "$submenu" && "$submenu" =~ ^menu: ]]; then
        sub="${submenu#menu:}"
        declare -F "_submenu_$sub" >/dev/null 2>&1 || { fail "submenu $sub → _submenu_$sub 未定义"; missing=$((missing+1)); continue; }
        pass "submenu:$sub → _submenu_$sub 已定义"
        continue
    fi
    # action: bash "path" → 路径存在；或函数名已定义
    [[ -z "$action" ]] && { fail "$cat$letter 无 action 且无 submenu"; missing=$((missing+1)); continue; }
    # 提取 bash "..." 中的路径
    script_path=$(echo "$action" | grep -oE 'bash "\$[A-Z_]+/[^"]+"' | head -1 | sed -E 's/bash "\$[A-Z_]+\///; s/"$//')
    if [[ -n "$script_path" ]]; then
        # 解析变量前缀：LIB_DIR/CCCONFIG_DIR
        case "$action" in
            *'"$LIB_DIR/'*) full="$CCCONFIG_DIR/lib/$script_path" ;;
            *'"$CCCONFIG_DIR/'*) full="$CCCONFIG_DIR/$script_path" ;;
            *) full="$CCCONFIG_DIR/$script_path" ;;
        esac
        [[ -e "$full" ]] || { fail "$cat$letter action 路径不存在: $full"; missing=$((missing+1)); continue; }
    else
        # 函数名（如 do_finalize）
        declare -F "$action" >/dev/null 2>&1 || echo "$action" | grep -qE '^(bash|exit|return)' || { fail "$cat$letter action 未定义函数: $action"; missing=$((missing+1)); continue; }
    fi
    pass "$cat$letter action OK"
done
[[ $missing -eq 0 ]] && pass "action/submenu 引用全部解析" || fail "$missing 处引用断裂"

# ── 6. menu_loop 死代码清除 ──
echo "=== 6. menu_loop 无死代码 ==="
if grep -A2 'read -r dummy' "$CCCONFIG_DIR/lib/interact.sh" | grep -qE 'selected\[@\]|items\[@\]'; then
    fail "menu_loop 仍有 selected/items 死代码"
else
    pass "menu_loop 死代码已清除"
fi

# ── 7. menu_select 取消契约 ──
echo "=== 7. menu_select 取消契约 ==="
out=$(printf "99\n" | menu_select "t" "a" "b" 2>/dev/null)
[[ "$out" == "0" ]] && pass "OOR → 0" || fail "OOR" "got $out"
out=$(menu_select "t" "a" "b" </dev/null 2>/dev/null)
[[ "$out" == "0" ]] && pass "EOF → 0" || fail "EOF" "got $out"
out=$(printf "2\n" | menu_select "t" "a" "b" 2>/dev/null)
[[ "$out" == "2" ]] && pass "valid → 序号" || fail "valid" "got $out"

# ── 8. _submenu_usage timer case 回归（数字非字母）──
echo "=== 8. timer case 回归 ==="
timer_line=$(grep 'case "\$ts" in' "$CCCONFIG_DIR/maintain.sh")
if echo "$timer_line" | grep -qE '1\).*install.*2\).*uninstall.*3\).*config'; then
    pass "timer case 用数字 1/2/3"
else
    fail "timer case 仍用字母" "$timer_line"
fi
echo "$timer_line" | grep -qE 'i\)|u\)|c\)' && fail "timer case 残留字母 i/u/c" || pass "无字母 i/u/c"

# ── 9. feishu 顶层 case 无 local ──
echo "=== 9. feishu case 无顶层 local ==="
awk '/^case "\$\{1:-menu\}/,/^esac$/' "$CCCONFIG_DIR/maintain.sh" | grep -q 'local ' \
    && fail "顶层 case 仍用 local" || pass "顶层 case 无 local"

# ── 10. SCRIPT_DIR 单赋值 ──
echo "=== 10. SCRIPT_DIR 单赋值 ==="
count=$(grep -c 'SCRIPT_DIR=' "$CCCONFIG_DIR/maintain.sh" 2>/dev/null || echo 0)
# 允许 1 处赋值 + 若干引用；赋值行（含 :=）应只有 1
assign_count=$(grep -cE '^SCRIPT_DIR=' "$CCCONFIG_DIR/maintain.sh")
[[ $assign_count -eq 1 ]] && pass "SCRIPT_DIR 单赋值 ($assign_count)" || fail "SCRIPT_DIR 重复赋值" "$assign_count 处"

# ── 11. pty：菜单渲染一次 + q 干净退出 ──
echo "=== 11. pty 菜单交互（无堆叠）==="
pty_out=$(python3 - "$CCCONFIG_DIR" <<'PYEOF'
import os, pty, sys, time, select
ccconfig = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(ccconfig)
    os.execvp("bash", ["bash", "maintain.sh"])
buf = b""
# 发 q 退出
time.sleep(0.8)
os.write(fd, b"q\n")
deadline = time.time() + 4
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.3)
    if fd in r:
        try:
            d = os.read(fd, 8192)
        except OSError:
            break
        if not d:
            break
        buf += d
    else:
        if time.time() > deadline - 2:
            break
try:
    _, status = os.waitpid(pid, 0)
    sys.stdout.write(buf.decode("utf-8", "replace"))
except Exception:
    sys.stdout.write(buf.decode("utf-8", "replace"))
PYEOF
)
banner_count=$(echo "$pty_out" | grep -c 'ccconfig 运维中心')
if [[ $banner_count -eq 1 ]]; then
    pass "菜单 banner 渲染一次（无堆叠）"
else
    fail "banner 渲染 $banner_count 次（应 1）"
fi
echo "$pty_out" | grep -q -- '选择:' && pass "菜单显示选择提示" || fail "无选择提示"
echo "$pty_out" | grep -q -- '退出' && pass "菜单含退出项" || fail "无退出项"

# ── 12. menu_parse 快捷键返回码（不执行动作）──
echo "=== 12. menu_parse 快捷键 ==="
menu_parse "q" ; [[ $? -eq 2 ]] && pass "q → 2(退出)" || fail "q"
menu_parse "r" ; [[ $? -eq 1 ]] && pass "r → 1(刷新)" || fail "r"
menu_parse "zzz" ; [[ $? -eq 3 ]] && pass "无效 → 3" || fail "无效输入"

echo ""
echo "────────────────────────────────────"
printf "  ${GREEN}PASS${NC}: %d  ${RED}FAIL${NC}: %d\n" "$PASS" "$FAIL"
echo "────────────────────────────────────"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1

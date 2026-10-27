#!/bin/bash
# tests/test-botmux-option.sh — option-botmux 回归
#
# 覆盖：
#   1. 语法 + 可执行 + shebang
#   2. --status 契约（首行 OK/WARN/MISSING，退出码与状态一致）
#   3. 接线：init-option 分组、maintain 菜单项、maintain.sh 子命令、deps-check
#   4. 已废弃 ccbridge 不再被引用（无 resolve_ccbridge 调用方）
#   5. dry-run 安全（--install 不真装）
#   6. 非 TTY 不阻塞（无 tty 时 sessions 走 --plain）

set -uo pipefail
CCCONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INIT="$CCCONFIG_DIR/option-botmux/init.sh"

PASS=0; FAIL=0
pass() { echo -e "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ❌ $1"; FAIL=$((FAIL + 1)); }
section() { echo -e "\n=== $1 ==="; }

# ── 1. 语法 / 可执行 / shebang ──
section "1. 语法 / 可执行 / shebang"
if bash -n "$INIT" 2>/dev/null; then pass "bash -n 语法 OK"; else fail "bash -n 语法错误"; fi
if [ -x "$INIT" ]; then pass "可执行"; else fail "不可执行"; fi
if head -1 "$INIT" | grep -q '^#!/bin/bash'; then pass "bash shebang"; else fail "shebang 非 bash"; fi

# ── 2. --status 契约 ──
section "2. --status 契约"
out="$(bash "$INIT" --status 2>&1)"; rc=$?
first="$(printf '%s\n' "$out" | head -1)"
if printf '%s' "$first" | grep -qE '^(OK|WARN|MISSING) botmux '; then
    pass "首行符合 OK/WARN/MISSING 契约: $first"
else
    fail "首行不符契约: $first"
fi
case "$first" in
    OK*)      [ $rc -eq 0 ] && pass "OK → rc=0" || fail "OK 但 rc=$rc（应 0）" ;;
    WARN*)    [ $rc -eq 1 ] && pass "WARN → rc=1" || fail "WARN 但 rc=$rc（应 1）" ;;
    MISSING*) [ $rc -eq 2 ] && pass "MISSING → rc=2" || fail "MISSING 但 rc=$rc（应 2）" ;;
esac
# 无 ANSI 在首行（init-option 按行解析，带色会解析失败）
if printf '%s' "$first" | grep -q $'\x1b'; then fail "首行含 ANSI（破坏 init-option 解析）"; else pass "首行无 ANSI"; fi

# ── 3. 接线 ──
section "3. 接线（init-option / maintain / deps-check）"
if grep -q '"\-\-飞书--|larkcli botmux"' "$CCCONFIG_DIR/init-option.sh"; then
    pass "init-option 分组含 botmux"
else
    fail "init-option 分组缺 botmux"
fi
if grep -q 'botmux)' "$CCCONFIG_DIR/init-option.sh"; then
    pass "init-option --yes 分支含 botmux"
else
    fail "init-option --yes 分支缺 botmux"
fi
if grep -q 'botmux)' "$CCCONFIG_DIR/maintain.sh"; then
    pass "maintain.sh 有 botmux 子命令"
else
    fail "maintain.sh 缺 botmux 子命令"
fi
if grep -q '5|G|botmux' "$CCCONFIG_DIR/lib/menu-data-maintain.sh"; then
    pass "主菜单含 botmux 项（5G）"
else
    fail "主菜单缺 botmux 项"
fi
if grep -q '"botmux|botmux --version' "$CCCONFIG_DIR/lib/deps-check.sh"; then
    pass "deps-check 含 botmux 依赖项"
else
    fail "deps-check 缺 botmux 依赖项"
fi
if grep -q 'botmux)' "$CCCONFIG_DIR/lib/status.sh"; then
    pass "status.sh 有 botmux 检测分支"
else
    fail "status.sh 缺 botmux 检测分支"
fi

# 旧名转发（larkbridge → botmux）
if grep -q 'larkbridge' "$CCCONFIG_DIR/init-option.sh" && \
   grep -q 'install_option "botmux"' "$CCCONFIG_DIR/init-option.sh"; then
    pass "旧名 larkbridge 转发到 botmux"
else
    fail "旧名 larkbridge 未转发"
fi

# ── 4. ccbridge 已摘除 ──
section "4. ccbridge 已摘除"
# resolve_ccbridge 无调用方（定义已删，注释里提到不算）
if grep -rn 'resolve_ccbridge' --include=*.sh "$CCCONFIG_DIR/lib" "$CCCONFIG_DIR/init-option.sh" "$CCCONFIG_DIR/maintain.sh" 2>/dev/null \
    | grep -v '^.*#' | grep -q .; then
    fail "仍有 resolve_ccbridge 调用方"
else
    pass "无 resolve_ccbridge 调用方（已摘除）"
fi
if grep -q 'lark-channel-bridge' "$CCCONFIG_DIR/lib/deps-check.sh"; then
    fail "deps-check 仍引用 lark-channel-bridge"
else
    pass "deps-check 不再引用 lark-channel-bridge"
fi

# ── 5. dry-run 安全 ──
section "5. dry-run 安全"
out="$(bash "$INIT" --install --dry-run 2>&1)"
if printf '%s' "$out" | grep -q 'would:'; then
    pass "--install --dry-run 走 would:（未真装）"
else
    # 已安装时 --dry-run 也会打印 would；缺 would 说明 dry-run 未生效
    fail "--install --dry-run 未走 dry-run 路径: $(printf '%s' "$out" | head -1)"
fi

# ── 6. 非 TTY 不阻塞 ──
section "6. 非 TTY 不阻塞"
# sessions 在无 tty 下应走 --plain，且不挂起（用 < /dev/null 模拟）
if timeout 15 bash "$INIT" sessions </dev/null >/dev/null 2>&1; then
    pass "sessions 非 TTY 快速返回（未阻塞）"
else
    rc=$?
    if [ $rc -eq 124 ]; then fail "sessions 非 TTY 超时（阻塞）"; else pass "sessions 非 TTY 返回 rc=$rc（非阻塞）"; fi
fi
if grep -q 'has_tty' "$INIT"; then pass "sessions 有 TTY 判定分支"; else fail "sessions 无 TTY 判定"; fi

echo ""
echo "────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────"
[ "$FAIL" -eq 0 ]
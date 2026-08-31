#!/bin/bash
# test-interact.sh — lib/interact.sh 单元测试
#
# 覆盖：
#   - confirm/menu_select/prompt/prompt_password/table/spinner/menu_multi 在 EOF stdin 下的行为
#   - menu_select 序号返回（含越界、非法、空）
#   - menu_select items 重复数字修复回归（callers 传纯文本）
#   - /dev/tty 三重判断的 fallback 路径
#
# 用法: bash tests/test-interact.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERACT="$SCRIPT_DIR/../lib/interact.sh"
COLORS="$SCRIPT_DIR/../lib/colors.sh"

# 临时屏蔽颜色码便于断言
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; GRAY=$'\033[0;90m'; NC=$'\033[0m'

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

source "$COLORS" 2>/dev/null || true
source "$INTERACT"

# 互 helpers
run_in() {
    local desc="$1"; shift
    local expect="$1"; shift
    local got
    got=$("$@" 2>/dev/null) || true
    if [[ "$got" == "$expect" ]]; then
        pass "$desc (got '$got')"
    else
        fail "$desc (expected '$expect', got '$got')"
    fi
}

# ── Test 1: menu_select items 为空应失败 ──
echo "=== Test 1: menu_select empty ==="
if menu_select "x" </dev/null >/dev/null 2>&1; then
    fail "empty items should return non-zero"
else
    pass "empty items returns non-zero"
fi

# ── Test 2: menu_select 在 EOF stdin 时返回 0（取消）──
echo "=== Test 2: menu_select EOF fallback ==="
out=$(menu_select "title" "a" "b" "c" </dev/null 2>/dev/null)
[[ "$out" == "0" ]] && pass "EOF returns 0 (cancel)" || fail "EOF got: '$out'"

# ── Test 3: menu_select 通过 stdin 喂数字应返回序号 ──
echo "=== Test 3: menu_select stdin input ==="
out=$(printf "2\n" | menu_select "title" "a" "b" "c" 2>/dev/null)
[[ "$out" == "2" ]] && pass "stdin '2' returns '2'" || fail "stdin '2' got: '$out'"

out=$(printf "1\n" | menu_select "title" "alpha" "beta" "gamma" 2>/dev/null)
[[ "$out" == "1" ]] && pass "stdin '1' first item" || fail "got: '$out'"

# ── Test 4: menu_select 越界返回 0 ──
echo "=== Test 4: menu_select out-of-range ==="
out=$(printf "99\n" | menu_select "title" "a" "b" "c" 2>/dev/null)
[[ "$out" == "0" ]] && pass "OOR '99' returns 0" || fail "OOR got: '$out'"

out=$(printf "0\n" | menu_select "title" "a" "b" "c" 2>/dev/null)
[[ "$out" == "0" ]] && pass "OOR '0' returns 0" || fail "OOR got: '$out'"

# ── Test 5: menu_select 非法字符返回 0 ──
echo "=== Test 5: menu_select invalid ==="
out=$(printf "abc\n" | menu_select "title" "a" "b" "c" 2>/dev/null)
[[ "$out" == "0" ]] && pass "non-numeric returns 0" || fail "got: '$out'"

out=$(printf "\n" | menu_select "title" "a" "b" "c" 2>/dev/null)
[[ "$out" == "0" ]] && pass "empty line returns 0" || fail "got: '$out'"

# ── Test 6: menu_select items 重复数字回归 ──
echo "=== Test 6: items double-number regression ==="
# 旧版: caller 传 "1) item1" → 输出 "1) 1) item1"（双前缀）
# 新版: caller 传纯文本 "item1" → 输出 "1) item1"
out=$(menu_select "title" "item1" "item2" "item3" </dev/null 2>&1 >/dev/null)
out_plain=$(echo "$out" | sed 's/\x1b\[[0-9;]*m//g')
if echo "$out_plain" | grep -qE "^\s+1\)\s+1\)\s"; then
    fail "double number detected: $out_plain"
else
    pass "items rendered correctly (no double number)"
fi
if echo "$out_plain" | grep -qE "^\s+1\)\s+item1\s*$"; then
    pass "item1 rendered as '1) item1'"
else
    fail "item1 missing: $out_plain"
fi

# ── Test 7: confirm EOF fallback (默认 n) ──
echo "=== Test 7: confirm EOF ==="
if confirm "test" n </dev/null 2>/dev/null; then
    fail "confirm should return 1 on EOF default=n"
else
    pass "confirm EOF default=n returns 1"
fi

if confirm "test" y </dev/null 2>/dev/null; then
    pass "confirm EOF default=y returns 0"
else
    fail "confirm EOF default=y should return 0"
fi

# ── Test 8: confirm 通过 stdin 喂 y/n ──
echo "=== Test 8: confirm stdin ==="
if printf "y\n" | confirm "test" n 2>/dev/null; then
    pass "confirm 'y' returns 0"
else
    fail "confirm 'y' failed"
fi

if printf "n\n" | confirm "test" y 2>/dev/null; then
    fail "confirm 'n' with default=y should return 1"
else
    pass "confirm 'n' returns 1"
fi

# ── Test 9: prompt EOF 返回 default ──
echo "=== Test 9: prompt EOF fallback ==="
out=$(prompt "msg" "default-val" </dev/null 2>/dev/null)
[[ "$out" == "default-val" ]] && pass "prompt EOF returns default" || fail "got: '$out'"

out=$(prompt "msg" </dev/null 2>/dev/null)
[[ -z "$out" ]] && pass "prompt no-default EOF returns empty" || fail "got: '$out'"

# ── Test 9.5: menu_select EOF 返回 "0"（cancel 哨值）──
echo "=== Test 9.5: EOF returns '0' as cancel sentinel ==="
out=$(menu_select "t" "a" "b" </dev/null 2>/dev/null)
[[ "$out" == "0" ]] && pass "EOF returns '0' (callers guard with [[ \$c == 0 ]])" || fail "got: '$out'"

# ── Test 10: prompt stdin 喂值 ──
echo "=== Test 10: prompt stdin ==="
out=$(printf "user-input\n" | prompt "msg" "default" 2>/dev/null)
[[ "$out" == "user-input" ]] && pass "prompt stdin value" || fail "got: '$out'"

# ── Test 11: prompt_password EOF 不会卡死 ──
echo "=== Test 11: prompt_password EOF ==="
out=$(prompt_password "msg" </dev/null 2>/dev/null)
[[ -z "$out" ]] && pass "prompt_password EOF returns empty (no hang)" || fail "got: '$out'"

# ── Test 12: table 渲染 ──
echo "=== Test 12: table ==="
out=$(table "MCP" "name,ver" "tavily,1.0" "getnote,2.1" 2>&1)
if echo "$out" | grep -q "tavily"; then
    pass "table contains data"
else
    fail "table missing data: $out"
fi

# ── Test 13: menu_select 走 stderr 验证 ──
echo "=== Test 13: menu_select stdout=number, stderr=menu ==="
# stdout 只收返回值（数字）；stderr 收菜单+提示
out_stdout=$(printf "2\n" | menu_select "title" "a" "b" "c" 2>/dev/null)
out_stderr=$(printf "2\n" | menu_select "title" "a" "b" "c" 2>&1 >/dev/null)
out_stderr_plain=$(echo "$out_stderr" | sed 's/\x1b\[[0-9;]*m//g')
[[ "$out_stdout" == "2" ]] && pass "stdout contains number" || fail "stdout got: '$out_stdout'"
if echo "$out_stderr_plain" | grep -qE "1\)\s+a"; then
    pass "stderr contains menu"
else
    fail "stderr missing menu: $out_stderr_plain"
fi
if echo "$out_stderr_plain" | grep -q "title"; then
    pass "stderr contains title section"
else
    fail "stderr missing title: $out_stderr_plain"
fi

echo ""
echo "════════════════════════"
printf "  PASS: %d  FAIL: %d\n" "$PASS" "$FAIL"
echo "════════════════════════"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
#!/bin/bash
# test-syntax.sh — 所有 .sh 脚本的 bash -n 语法检查
#
# 覆盖：
#   - 根脚本: init-*.sh, maintain.sh, bootstrap-gh-auth.sh
#   - lib/*.sh
#   - option-*/*.sh
#   - tests/*.sh
#
# 用途：CI 快速检查语法错误，无需 mock。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo ""
echo "ccconfig 脚本语法全检"
echo "════════════════════════"
echo ""

# 找所有 .sh，排除 .git/、node_modules/、worktrees/
sh_files=$(find "$CCCONFIG_DIR" -name "*.sh" \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/worktrees/*" \
    -type f 2>/dev/null | sort)

total=0
for shfile in $sh_files; do
    total=$((total + 1))
    rel="${shfile#$CCCONFIG_DIR/}"
    if bash -n "$shfile" 2>/dev/null; then
        pass "$rel"
    else
        fail "$rel"
        bash -n "$shfile" 2>&1 | head -5 | sed 's/^/    /'
    fi
done

echo ""
echo "──────────────────────────────────────────"
printf "  PASS: %d  FAIL: %d  TOTAL: %d\n" "$PASS" "$FAIL" "$total"
echo "──────────────────────────────────────────"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1

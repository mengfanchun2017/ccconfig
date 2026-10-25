#!/bin/bash
# 回归测试：mcp-manager.sh 的 py_write 变量转义
#
# 背景：py_write 把 $name/$desc/$target/$escaped_path 直接拼进 `python3 -c` 字符串。
# 名字里带单引号或反斜杠 → SyntaxError → 写入失败被 `|| err` 吞成一行提示，
# 表现是菜单报"已注册"但 .config.json 没变（静默失效）。

set -u
CCCONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CCCONFIG_DIR"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }

echo "=== mcp-manager py_write 转义 ==="

# 只取 py_str 定义，不 source 整个脚本（mcp-manager.sh 无 sourced/executed 保护，source 会跑主流程）
eval "$(sed -n '/^py_str()/,/^}/p' lib/mcp-manager.sh)"
type py_str >/dev/null 2>&1 && pass "py_str 已定义" || { fail "py_str 缺失"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

# 1. 无特殊字符 → 原样
[ "$(py_str "plain")" = "plain" ] && pass "普通字符串原样透传" || fail "普通字符串被改动"

# 2. 单引号 → 反斜杠转义
[ "$(py_str "a'b")" = "a\\'b" ] && pass "单引号被转义" || fail "单引号未转义: $(py_str "a'b")"

# 3. 反斜杠 → 双写（且必须先于引号处理，否则 \\' 会被二次转义）
[ "$(py_str 'back\slash')" = 'back\\slash' ] && pass "反斜杠被双写" || fail "反斜杠未双写: $(py_str 'back\slash')"

# 4. 混合：反斜杠 + 单引号
[ "$(py_str "m'\\x")" = "m\\'\\\\x" ] && pass "混合场景转义顺序正确" || fail "混合场景错误: $(py_str "m'\\x")"

# 5. 关键断言：转义后的值拼进 python 单引号字面量必须语法合法且往返一致
for s in "plain" "a'b" 'back\slash' "m'\\x" 'a"b' "tab	x"; do
    esc="$(py_str "$s")"
    got="$(python3 -c "print('$esc', end='')" 2>/dev/null)"
    if [ "$got" = "$s" ]; then
        pass "python 往返一致: $(printf '%q' "$s")"
    else
        fail "python 往返失败: in=$(printf '%q' "$s") out=$(printf '%q' "$got")"
    fi
done

# 6. 未转义时会崩（证明这个测试不是空转）——拿反例验证测试有效性
if python3 -c "print('a'b', end='')" >/dev/null 2>&1; then
    fail "反例竟然通过了，说明断言无效"
else
    pass "反例（未转义）确实语法错误 —— 断言有效"
fi

# 7. 所有 py_write 调用点的插值都已走 py_str（静态检查裸插）
bare=$(grep -nE "setdefault\('[^']*', \{\}\)|== '\\\$|append\('\\\$" lib/mcp-manager.sh | grep -v 'py_str' | grep -v "startswith" | wc -l)
[ "$bare" -eq 0 ] && pass "无残留裸插变量" || fail "仍有 $bare 处裸插: $(grep -nE "append\('\\\$" lib/mcp-manager.sh | grep -v py_str | head -2)"

echo ""
echo "────────────────────────────────────"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "────────────────────────────────────"
[ "$FAIL" -eq 0 ] || exit 1
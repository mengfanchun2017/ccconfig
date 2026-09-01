#!/bin/bash
# test-init-option.sh — init-option.sh 单元测试
#
# 测什么：
#   1. 语法 + shebang
#   2. 交互菜单退出逻辑（exit→break，cancel→break）
#   3. --dry-run 入口解析（不再当未知选项）
#   4. CLI_DESC key 与菜单项匹配
#   5. usage 子菜单无双重显示
#   6. batcat 版本检测（先 resolve cmd）
#   7. sudo dpkg 已移除（只用 apt-get）
#   8. cd 变量遮蔽已重命名
#   9. install_option dry-run 消息
#
# 不测什么：实际 apt/pip/npm 安装（需 root + 网络）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPT="$CCCONFIG_DIR/init-option.sh"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# ── Test 1: 语法 ──
echo "=== Test 1: bash -n 语法 ==="
bash -n "$OPT" 2>/dev/null && pass "syntax OK" || { fail "syntax error"; exit 1; }

# ── Test 2: shebang + 可执行 ──
echo "=== Test 2: shebang + 可执行 ==="
head -1 "$OPT" | grep -q "^#!/bin/bash" && pass "bash shebang" || fail "wrong shebang"
[ -x "$OPT" ] && pass "executable" || fail "not executable"

# ── Test 3: 交互菜单退出逻辑（exit→break，cancel→break） ──
echo "=== Test 3: 菜单退出逻辑 ==="
if grep -q '\[\[ -z "\$choice" || "\$choice" == "0" || "\$choice" == "\$exit_idx" \]\] && break' "$OPT"; then
    pass "exit/cancel → break"
else
    fail "退出逻辑应为 break（含 cancel 0）"
fi
if ! grep -q '&& continue' "$OPT" || ! grep -q 'exit_idx' "$OPT"; then
    pass "无 exit_idx && continue 反模式"
else
    # 确认 exit_idx 行用的是 break
    if grep 'exit_idx' "$OPT" | grep -q 'break'; then
        pass "exit_idx 行用 break"
    else
        fail "exit_idx 行仍用 continue"
    fi
fi

# ── Test 4: --dry-run 入口解析 ──
echo "=== Test 4: --dry-run 入口 ==="
if grep -q '_DRY_RUN_GLOBAL=true' "$OPT" && grep -q 'export CCC_DRY_RUN=1' "$OPT"; then
    pass "入口剥离 --dry-run 并设 CCC_DRY_RUN"
else
    fail "入口未解析 --dry-run"
fi
# 实跑：--dry-run <name> 应输出 would 而非"未知选项"
out=$(bash "$OPT" --dry-run mcp 2>&1) || true
if echo "$out" | grep -q "would: install mcp"; then
    pass "--dry-run mcp → would: install"
else
    fail "--dry-run mcp 输出异常: $(echo "$out" | head -1)"
fi
# --dry-run 自身不应被当未知选项
out=$(bash "$OPT" --dry-run 2>&1) || true
if ! echo "$out" | grep -q "未知选项: --dry-run"; then
    pass "--dry-run 不被当未知选项"
else
    fail "--dry-run 仍被当未知选项"
fi

# ── Test 5: CLI_DESC key 与菜单项匹配 ──
echo "=== Test 5: CLI_DESC key 匹配 ==="
if grep -q 'CLI_DESC\["batcat"\]' "$OPT" && ! grep -q 'CLI_DESC\["bat"\]' "$OPT"; then
    pass "CLI_DESC key = batcat（与菜单项一致）"
else
    fail "CLI_DESC key 仍是 bat（与菜单项 batcat 不匹配）"
fi

# ── Test 6: usage 子菜单无双重显示 ──
echo "=== Test 6: usage 子菜单 ==="
# 不应再有手写 "1) 安装 timer" echo + menu_select 双重列表
if ! grep -q 'echo "    1) 安装 timer' "$OPT"; then
    pass "usage 子菜单无手写重复列表"
else
    fail "usage 子菜单仍有手写 echo 列表"
fi

# ── Test 7: batcat 版本检测 ──
echo "=== Test 7: batcat 版本检测 ==="
if grep -q 'command -v bat &>/dev/null || bcmd="batcat"' "$OPT" || \
   grep -q 'local bcmd' "$OPT"; then
    pass "batcat 版本检测先 resolve cmd"
else
    fail "batcat 版本检测未先 resolve cmd"
fi

# ── Test 8: sudo dpkg 已移除 ──
echo "=== Test 8: 无 sudo dpkg ==="
if ! grep -q 'sudo dpkg' "$OPT"; then
    pass "无 sudo dpkg（只用 apt-get）"
else
    fail "仍有 sudo dpkg（违反 sudo 只限 apt-get 规则）"
fi

# ── Test 9: cd 变量遮蔽已重命名 ──
echo "=== Test 9: 无 cd 变量遮蔽 ==="
if ! grep -q 'local cd=' "$OPT"; then
    pass "无 local cd= 变量遮蔽"
else
    fail "仍有 local cd= 变量遮蔽内置命令"
fi

# ── Test 10: A&&B||C 反模式已改 if/else ──
echo "=== Test 10: feishu_key 分支 ==="
if ! grep -q 'feishu_key_wizard || install_option' "$OPT"; then
    pass "feishu_key_wizard 用 if/else（无 || 反模式）"
else
    fail "feishu_key_wizard 仍用 A&&B||C 反模式"
fi

# ── Test 11: --status 退出码 0 ──
echo "=== Test 11: --status 退出码 ==="
if bash "$OPT" --status >/dev/null 2>&1; then
    pass "--status 退出码 0"
else
    fail "--status 退出码非 0"
fi

# ── Test 12: list_names_compact 用显式 if ──
echo "=== Test 12: list_names_compact ==="
if grep -q 'if \[ -n "\${AUTO_MANAGED' "$OPT"; then
    pass "list_names_compact 显式 if（无 ||/&& 优先级陷阱）"
else
    fail "list_names_compact 仍用 ||/&& 链"
fi

echo ""
echo "==========================="
echo "PASS: $PASS | FAIL: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1

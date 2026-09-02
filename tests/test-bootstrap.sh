#!/bin/bash
# test-bootstrap.sh — bootstrap-gh-auth.sh 测试
#
# bootstrap-gh-auth.sh 现在是 curl|bash 入口（pre-bootstrap）：
#   装 git + clone ccconfig + 提示 init-bootstrap.sh
# gh auth + ccprivate 已移交 init-bootstrap.sh，本脚本不重复。
#
# 测什么：
#   1. 语法（bash -n）+ 可执行 + shebang
#   2. 自包含（不 source 任何 lib/，curl|bash 可用）
#   3. 装 git 逻辑（command -v git + apt-get install git）
#   4. clone ccconfig 逻辑（git clone + CCCONFIG_DIR）
#   5. 提示 init-bootstrap.sh 下一步
#   6. 全流程链路输出（init-bootstrap → init-base → init-option → maintain）
#   7. CCCONFIG_REPO 环境变量支持
#
# 不测什么：
#   - 实际网络 clone / sudo apt（CI 沙箱可能无外网/无 root）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP="$CCCONFIG_DIR/bootstrap-gh-auth.sh"

PASS=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# ── Test 1: 语法检查 ──
echo "=== Test 1: bash -n 语法 ==="
if bash -n "$BOOTSTRAP" 2>/dev/null; then
    pass "syntax OK"
else
    fail "syntax error"
    exit 1
fi

# ── Test 2: 可执行权限 ──
echo "=== Test 2: 文件可执行 ==="
[ -x "$BOOTSTRAP" ] && pass "executable bit set" || fail "not executable"

# ── Test 3: shebang ──
echo "=== Test 3: shebang 是 bash ==="
head -1 "$BOOTSTRAP" | grep -q "^#!/bin/bash" && pass "bash shebang" || fail "wrong shebang: $(head -1 "$BOOTSTRAP")"

# ── Test 4: 自包含（curl|bash 可用，不 source lib/）──
echo "=== Test 4: 自包含，不 source lib ==="
if grep -E '^[^#]*source.*lib/' "$BOOTSTRAP" | grep -qv '^\s*#'; then
    fail "source lib/ — curl|bash 场景 ccconfig 还没 clone，会失败"
else
    pass "不 source 任何 lib/（自包含）"
fi
# 自定义输出函数（不依赖 lib/colors.sh）
grep -q '^info()' "$BOOTSTRAP" && pass "自定义 info()" || fail "no info() def"
grep -q '^ok()' "$BOOTSTRAP" && pass "自定义 ok()" || fail "no ok() def"

# ── Test 5: 装 git 逻辑 ──
echo "=== Test 5: 装 git 逻辑 ==="
grep -q 'command -v git' "$BOOTSTRAP" && pass "检查 git 是否已装" || fail "no git check"
grep -q 'apt-get install -y git' "$BOOTSTRAP" && pass "apt install git fallback" || fail "no apt install git"

# ── Test 6: clone ccconfig 逻辑 ──
echo "=== Test 6: clone ccconfig 逻辑 ==="
grep -q 'git clone' "$BOOTSTRAP" && pass "执行 git clone" || fail "no git clone"
grep -q 'CCCONFIG_DIR="$HOME/git/ccconfig"' "$BOOTSTRAP" && pass "目标路径 ~/git/ccconfig" || fail "no CCCONFIG_DIR"
grep -q '\.git' "$BOOTSTRAP" && pass "检查 .git 判断已 clone" || fail "no .git check"

# ── Test 7: 提示 init-bootstrap.sh 下一步 ──
echo "=== Test 7: 引导 init-bootstrap.sh ==="
grep -q 'init-bootstrap.sh' "$BOOTSTRAP" && pass "提示 bash init-bootstrap.sh" || fail "no init-bootstrap prompt"

# ── Test 8: 全流程链路输出 ──
echo "=== Test 8: 全流程链路 ==="
grep -q 'init-bootstrap.sh' "$BOOTSTRAP" && pass "链路含 init-bootstrap.sh" || fail "no init-bootstrap in flow"
grep -q 'init-base.sh all' "$BOOTSTRAP" && pass "链路含 init-base.sh all" || fail "no init-base in flow"
grep -q 'init-option.sh' "$BOOTSTRAP" && pass "链路含 init-option.sh" || fail "no init-option in flow"
grep -q 'maintain.sh' "$BOOTSTRAP" && pass "链路含 maintain.sh" || fail "no maintain in flow"

# ── Test 9: CCCONFIG_REPO 环境变量 ──
echo "=== Test 9: CCCONFIG_REPO 支持 ==="
grep -q 'CCCONFIG_REPO' "$BOOTSTRAP" && pass "支持 CCCONFIG_REPO env（fork 用）" || fail "no CCCONFIG_REPO"

# ── Test 10: 不残留旧 gh-auth 逻辑 ──
echo "=== Test 10: 不含旧 gh-auth 残留 ==="
if grep -q 'gh auth login' "$BOOTSTRAP"; then
    fail "仍含 gh auth login（已移交 init-bootstrap.sh）"
else
    pass "无 gh auth login 残留"
fi
if grep -q 'Step [0-9]/5' "$BOOTSTRAP"; then
    fail "仍含旧 5-step 结构"
else
    pass "无旧 5-step 结构残留"
fi

echo ""
echo "==========================="
echo "PASS: $PASS | FAIL: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1

#!/bin/bash
# test-bootstrap.sh — unit tests for bootstrap.sh
#
# 测什么：
#   1. 语法（bash -n）
#   2. shebang + 可执行
#   3. 5 步结构（前置 → 装 gh → 认证 → git 身份 → 引导）
#   4. git 必装检查（前置条件）
#   5. gh 安装三路径（apt / NOSUDO binary / 已装）
#   6. gh auth 引导 + SSH 跳过逻辑
#   7. git 用户身份从 gh api 拿
#   8. 引导输出包含 cd + init.sh all
#
# 不测什么：
#   - 实际网络 clone（CI 沙箱可能无外网）
#   - sudo apt-get（需要真 root + apt 源）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP="$CCCONFIG_DIR/bootstrap.sh"

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

# ── Test 4: 5 步结构 ──
echo "=== Test 4: 5 步结构 ==="
grep -q 'Step 1/5 前置检查' "$BOOTSTRAP" && pass "Step 1/5 前置检查" || fail "missing Step 1"
grep -q 'Step 2/5 装 GitHub CLI' "$BOOTSTRAP" && pass "Step 2/5 装 gh" || fail "missing Step 2"
grep -q 'Step 3/5 GitHub 认证' "$BOOTSTRAP" && pass "Step 3/5 认证" || fail "missing Step 3"
grep -q 'Step 4/5 git 用户身份' "$BOOTSTRAP" && pass "Step 4/5 git 身份" || fail "missing Step 4"
grep -q 'Step 5/5 准备完成' "$BOOTSTRAP" && pass "Step 5/5 引导" || fail "missing Step 5"

# ── Test 5: git 必装检查 ──
echo "=== Test 5: git 前置检查 ==="
grep -q 'command -v git' "$BOOTSTRAP" && pass "checks git" || fail "no git check"
grep -q 'git 未装' "$BOOTSTRAP" && pass "报错 'git 未装'" || fail "no 'git 未装' error"

# ── Test 6: 关键引导输出 ──
echo "=== Test 6: 引导输出 ==="
grep -q 'bash init.sh all' "$BOOTSTRAP" && pass "instructs bash init.sh all" || fail "missing init.sh all"
grep -q 'BOOTSTRAP_NOSUDO' "$BOOTSTRAP" && pass "supports BOOTSTRAP_NOSUDO env" || fail "missing NO-SUDO support"

# ── Test 7: gh 安装三路径 ──
echo "=== Test 7: gh 安装路径 ==="
grep -q 'command -v gh' "$BOOTSTRAP" && pass "checks gh installed" || fail "no gh check"
grep -q 'apt-get install -y gh' "$BOOTSTRAP" && pass "apt install gh fallback" || fail "no apt install gh"
grep -q 'linux_amd64.tar.gz' "$BOOTSTRAP" && pass "binary download fallback (NOSUDO)" || fail "no binary download"

# ── Test 8: gh auth + SSH 跳过 ──
echo "=== Test 8: gh auth 逻辑 ==="
grep -q 'gh auth status' "$BOOTSTRAP" && pass "checks gh auth" || fail "no gh auth check"
grep -q 'id_ed25519' "$BOOTSTRAP" && pass "detects existing SSH key" || fail "no SSH detection"
grep -q 'gh auth login' "$BOOTSTRAP" && pass "prompts gh auth login" || fail "no gh auth login"

# ── Test 9: git 用户身份从 gh api 拿 ──
echo "=== Test 9: git 身份配置 ==="
grep -q 'gh api user' "$BOOTSTRAP" && pass "fetches user from gh api" || fail "no gh api user"
grep -q 'git config --global user.email' "$BOOTSTRAP" && pass "sets git user.email" || fail "no git config email"
grep -q 'git config --global user.name' "$BOOTSTRAP" && pass "sets git user.name" || fail "no git config name"
grep -q 'gh auth setup-git' "$BOOTSTRAP" && pass "runs gh auth setup-git" || fail "no setup-git"

# ── Test 10: 三步流程在文档中体现（脚本里能搜到 init.sh all 引导） ──
echo "=== Test 10: 三步流程定位 ==="
grep -q 'cd ~/git/ccconfig && bash init.sh all' "$BOOTSTRAP" && pass "指引 cd + init.sh all" || fail "no cd + init.sh all guide"

# ── Test 11: 颜色变量定义 ──
echo "=== Test 11: 颜色输出 ==="
grep -q "RED=" "$BOOTSTRAP" && pass "color RED" || fail "no RED"
grep -q "GREEN=" "$BOOTSTRAP" && pass "color GREEN" || fail "no GREEN"
grep -q "YELLOW=" "$BOOTSTRAP" && pass "color YELLOW" || fail "no YELLOW"

# ── Test 12: 不应再含旧版一行 curl 引导（已拆三步） ──
echo "=== Test 12: 不含旧版引导 ==="
if ! grep -q 'curl -fsSL.*| bash' "$BOOTSTRAP"; then
    pass "no one-line curl|bash bootstrap (deprecated)"
else
    fail "still contains curl|bash bootstrap"
fi

echo ""
echo "==========================="
echo "PASS: $PASS | FAIL: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
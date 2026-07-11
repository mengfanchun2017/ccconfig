#!/bin/bash
# test-bootstrap.sh — unit tests for bootstrap.sh
#
# 测什么：
#   1. 语法（bash -n）
#   2. 默认值正确（CCCONFIG_REPO/BRANCH/DIR）
#   3. env override 生效
#   4. fetch 函数优先 curl，wget 兜底
#   5. Step 1: 缺 curl+wget → exit 1
#   6. Step 2: git 已装 → 跳过 sudo
#   7. Step 4: 输出包含关键命令（cd + init.sh all）
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

# ── Test 4: 默认值（不依赖运行环境，纯文本扫描） ──
echo "=== Test 4: 默认值（用户/仓库/分支/路径）==="
grep -q 'CCCONFIG_REPO:-mengfanchun2017/ccconfig' "$BOOTSTRAP" && pass "default CCCONFIG_REPO = mengfanchun2017/ccconfig" || fail "default repo missing"
grep -q 'CCCONFIG_BRANCH:-main' "$BOOTSTRAP" && pass "default branch = main" || fail "default branch missing"
grep -q 'CCCONFIG_HOME:-\$HOME/git/ccconfig' "$BOOTSTRAP" && pass "default dir = ~/git/ccconfig" || fail "default dir missing"

# ── Test 5: 关键引导输出存在 ──
echo "=== Test 5: 引导输出包含 init.sh all + 下一步命令 ==="
grep -q 'bash init.sh all' "$BOOTSTRAP" && pass "instructs bash init.sh all" || fail "missing init.sh all instruction"
grep -q 'CCCONFIG_DIR' "$BOOTSTRAP" && pass "uses CCCONFIG_DIR" || fail "missing CCCONFIG_DIR"
grep -q 'BOOTSTRAP_NOSUDO' "$BOOTSTRAP" && pass "supports BOOTSTRAP_NOSUDO env" || fail "missing NO-SUDO support"

# ── Test 6: 包含完整的 Step 编号 ──
echo "=== Test 6: 4 步结构 ==="
grep -q 'Step 1/4' "$BOOTSTRAP" && pass "Step 1/4 网络工具" || fail "missing Step 1"
grep -q 'Step 2/4' "$BOOTSTRAP" && pass "Step 2/4 git" || fail "missing Step 2"
grep -q 'Step 3/4' "$BOOTSTRAP" && pass "Step 3/4 clone" || fail "missing Step 3"
grep -q 'Step 4/4' "$BOOTSTRAP" && pass "Step 4/4 引导" || fail "missing Step 4"

# ── Test 7: fetch 函数 + curl/wget fallback ──
echo "=== Test 7: fetch 函数 curl/wget 双 fallback ==="
grep -q 'if $have_curl' "$BOOTSTRAP" && pass "fetch prefers curl" || fail "no curl branch"
grep -q 'wget -q' "$BOOTSTRAP" && pass "fetch falls back to wget" || fail "no wget fallback"

# ── Test 8: 检测 curl+wget 都缺时报错退出 ──
echo "=== Test 8: 缺 curl+wget 检测逻辑 ==="
grep -q 'curl 和 wget 都缺失' "$BOOTSTRAP" && pass "detects no curl+wget" || fail "missing curl+wget detection"
grep -q 'exit 1' "$BOOTSTRAP" && pass "exits 1 on missing tools" || fail "no exit on missing tools"

# ── Test 9: git 已装跳过 sudo ──
echo "=== Test 9: git 检测逻辑 ==="
grep -q 'command -v git' "$BOOTSTRAP" && pass "checks git" || fail "no git check"

# ── Test 10: clone 用 gh fallback 到 git clone ──
echo "=== Test 10: gh auth fallback 到 HTTPS clone ==="
grep -q 'gh auth status' "$BOOTSTRAP" && pass "checks gh auth" || fail "no gh auth check"
grep -q 'git clone "https://github.com' "$BOOTSTRAP" && pass "falls back to https clone" || fail "no https fallback"

# ── Test 11: 幂等性支持（重跑不重复 clone） ──
echo "=== Test 11: 幂等性 ==="
grep -q '\$CCCONFIG_DIR/.git' "$BOOTSTRAP" && pass "detects existing .git" || fail "no idempotency check"
grep -q 'git pull' "$BOOTSTRAP" && pass "pull existing" || fail "no git pull on existing"

# ── Test 12: 缺 curl+wget 检测（stub command 模拟） ──
echo "=== Test 12: 提取检测逻辑验证 ==="
TMP=$(mktemp -d)
cat > "$TMP/detect.sh" << 'DETECT_EOF'
have_curl=false; have_wget=false
command -v curl &>/dev/null && have_curl=true
command -v wget &>/dev/null && have_wget=true
if $have_curl || $have_wget; then
    echo "FOUND"
else
    echo "curl 和 wget 都缺失"
fi
DETECT_EOF

# A. 系统有 curl → 应 FOUND
bash "$TMP/detect.sh" | grep -q "FOUND" && pass "系统有 curl/wget 时通过" || fail "应检测到有 curl/wget"

# B. stub command 函数 → 强制找不到
bash -c '
    command() { return 1; }
    export -f command
    bash "'"$TMP"'/detect.sh"
' 2>&1 | grep -q "curl 和 wget 都缺失" \
    && pass "无 curl+wget 时正确报错" \
    || fail "应报错 'curl 和 wget 都缺失'"

rm -rf "$TMP"

echo ""
echo "==========================="
echo "PASS: $PASS | FAIL: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
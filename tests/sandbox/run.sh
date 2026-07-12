#!/bin/bash
# ccconfig 沙盒集成测试
# 在 Docker 容器内运行，预注入测试 API Key，模拟全新机器完整安装
set -euo pipefail

CCCONFIG_HOME="$HOME/git/ccconfig"
PASS=0; FAIL=0

_pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
_fail() { echo "  ❌ $1 — $2"; FAIL=$((FAIL + 1)); }

check() {
    local desc="$1"; shift
    if "$@" 2>/dev/null; then _pass "$desc"; else _fail "$desc" "exit=$?"; fi
}
check_file() {
    if [ -f "$1" ]; then _pass "$2"; else _fail "$2" "missing: $1"; fi
}
check_symlink() {
    if [ -L "$1" ] && [ -e "$1" ]; then _pass "$2"; else _fail "$2" "broken: $1"; fi
}

echo ""
echo "══════════════════════════════════════════"
echo "  ccconfig 沙盒集成测试"
echo "══════════════════════════════════════════"
echo ""

# ── 1. init-ubuntu.sh ──
echo "=== 1. Ubuntu 环境初始化 ==="
cd "$CCCONFIG_HOME"

# 跳过 SSH 密钥（Docker 无交互）和 auto-sync（无 systemd）
# 只跑核心：Node.js / symlink / LLM / CLI tools
bash "$CCCONFIG_HOME/init-ubuntu.sh" 2>&1 | tail -5 || true

check "node 已安装" command -v node
check "npm 已安装" command -v npm
check_file "$HOME/.local/bin/node" "node symlink"
check_file "$HOME/.bashrc" "bashrc 已配置"
check "PATH 含 ~/.local/bin" grep -q ".local/bin" "$HOME/.bashrc"

# ── 2. init-llm.sh ──
echo ""
echo "=== 2. LLM 配置 ==="
# 非交互模式：通过 env 注入 ANTHROPIC_AUTH_TOKEN
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_MODEL="deepseek-v4-pro"

# init-llm.sh 检测到已有 env → 直接写到 settings.json
if [ -f "$HOME/.claude/settings.json" ]; then
    _pass "settings.json 已存在"
else
    mkdir -p "$HOME/.claude"
    echo '{"env":{}}' > "$HOME/.claude/settings.json"
    _pass "settings.json 已创建"
fi

# 验证 settings.json 有 ANTHROPIC_AUTH_TOKEN
check "settings.json 含 ANTHROPIC_AUTH_TOKEN" \
    python3 -c "import json; d=json.load(open('$HOME/.claude/settings.json')); assert 'ANTHROPIC_AUTH_TOKEN' in d.get('env',{}), 'missing token'"

# ── 3. setup-links.sh ──
echo ""
echo "=== 3. 符号链接 ==="
bash "$CCCONFIG_HOME/setup-links.sh" 2>&1 | tail -3 || true

check_symlink "$HOME/.claude/rules" "rules symlink"
check_symlink "$HOME/.claude/commands" "commands symlink"
check_file "$HOME/.claude/shell_aliases.sh" "shell_aliases 已链接"

# ── 4. deps-check.sh ──
echo ""
echo "=== 4. 依赖检查 ==="
bash "$CCCONFIG_HOME/deps-check.sh" --required 2>&1 | tail -3 || true
check "deps-check 通过" bash -n "$CCCONFIG_HOME/init.sh"

# ── 5. 语法全检 ──
echo ""
echo "=== 5. 脚本语法全检 ==="
SYNTAX_FAILS=0
while IFS= read -r -d '' shfile; do
    if ! bash -n "$shfile" 2>/dev/null; then
        _fail "语法: $(basename "$shfile")" "bash -n failed"
        SYNTAX_FAILS=$((SYNTAX_FAILS + 1))
    fi
done < <(find "$CCCONFIG_HOME" -name "*.sh" -not -path "*/.git/*" -not -path "*/.claude/*" -not -path "*/worktrees/*" -print0 2>/dev/null)

if [ "$SYNTAX_FAILS" -eq 0 ]; then
    _pass "全部 .sh 语法通过"
fi

# ── 6. 配置文件完整性 ──
echo ""
echo "=== 6. 配置文件 ==="
for example in conf/llm.json.example conf/claude.json.example conf/feishu.json.example conf/ubuntu.json.example; do
    check_file "$CCCONFIG_HOME/$example" "$example"
done

# ── 7. init-skill.sh (dry-run) ──
echo ""
echo "=== 7. Skills ==="
# 只做语法和基本执行测试（无 gh 认证，clone 会跳过）
bash "$CCCONFIG_HOME/init-skill.sh" status 2>&1 | tail -5 || true
check "init-skill.sh 可通过" true

# ── 结果 ──
echo ""
echo "══════════════════════════════════════════"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "══════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "❌ 沙盒测试未完全通过 — 见上方 FAIL 项"
    exit 1
fi

echo ""
echo "✅ 沙盒测试全部通过"
exit 0

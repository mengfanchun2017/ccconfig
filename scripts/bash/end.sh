#!/bin/bash
# Claude Code - 结束工作 (Linux/WSL)
#
# ============================================================
# 功能说明
# ============================================================
#
# 由于 start.sh 已通过符号链接建立双向同步，
# 本脚本主要完成 Git 操作：
#   1. 符号链接检查 - 确保同步链路正常
#   2. git add .     - 暂存所有更改
#   3. git commit    - 提交更改
#   4. git push      - 推送到 GitHub
#
# 注意：MEMORY.md 等文件已通过符号链接同步，
#       无需额外复制操作。
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
MEMORY_DIR="$CLAUDE_DIR/projects/home-francis-git/memory"

# ========== 符号链接检查函数 ==========
check_symlink() {
    local link="$1"
    local name="$2"
    if [ -L "$link" ]; then
        if [ -e "$link" ]; then
            echo "   ✅ $name: 正常"
            return 0
        else
            echo "   ❌ $name: 链接断开（目标不存在）"
            return 1
        fi
    elif [ -e "$link" ]; then
        echo "   ⚠️  $name: 是文件而非链接"
        return 2
    else
        echo "   ❌ $name: 不存在"
        return 3
    fi
}

echo "========================================"
echo "  Claude Code - 结束工作"
echo "  当前系统: Linux/WSL"
echo "========================================"
echo ""
echo "仓库目录: $REPO_DIR"
echo ""

cd "$REPO_DIR"

# ========== 符号链接检查（push 前必须通过）==========
echo "========================================"
echo "  🔍 符号链接状态检查"
echo "========================================"

failed=0
check_symlink "$CLAUDE_DIR/settings.json" "settings.json" || ((failed++))
check_symlink "$HOME/CLAUDE.md" "CLAUDE.md" || ((failed++))
check_symlink "$MEMORY_DIR/MEMORY.md" "MEMORY.md" || ((failed++))

echo ""

if [ $failed -gt 0 ]; then
    echo "❌ 符号链接检查失败，请先运行 start.sh 修复"
    exit 1
fi

echo "✅ 符号链接检查通过"
echo ""

# ========== Git 状态 ==========
echo "[1/3] 检查 git 状态..."
git status --short
echo ""

# ========== Git 提交 ==========
echo "[2/3] 提交更改..."
git add .

if [ -z "$1" ]; then
    read -p "请输入提交信息 (默认: 更新配置): " commit_msg
else
    commit_msg="$1"
fi
if [ -z "$commit_msg" ]; then
    commit_msg="更新配置"
fi
git commit -m "$commit_msg"
echo "✅ 已提交: $commit_msg"
echo ""

# ========== Git 推送 ==========
echo "[3/3] 推送到 GitHub..."
git push
echo "✅ 成功推送到 GitHub"
echo ""

echo "========================================"
echo "  ✅ 同步完成！"
echo "========================================"
echo ""

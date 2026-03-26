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
echo "[1/5] 检查 git 状态..."
git status --short
echo ""

# ========== Git 拉取（暂存更改后操作）==========
echo "[2/5] 暂存本地更改..."
git add .
git stash
echo "✅ 已暂存"

echo "[3/5] 检查远程更新..."
if git pull --rebase origin main; then
    echo "✅ 已同步远程更新"
else
    echo "⚠️  拉取失败，尝试恢复暂存..."
    if git stash pop 2>&1; then
        echo "⚠️  已恢复本地更改，但未推送"
    else
        echo "❌ 有冲突，请手动解决后重试"
        echo "   冲突文件："
        git diff --name-only --diff-filter=U
    fi
    exit 1
fi
echo ""

# ========== 恢复并重新提交 ==========
echo "[4/5] 恢复本地更改..."
if git stash pop 2>&1; then
    echo "✅ 已恢复"
else
    echo "⚠️  恢复时有冲突，请手动检查"
fi

# 重新 add
git add .
echo "✅ 已暂存本地更改"
echo ""

# ========== Git 提交 ==========
echo "[5/5] 提交并推送..."
if [ -z "$1" ]; then
    read -p "请输入提交信息 (默认: 更新配置): " commit_msg
else
    commit_msg="$1"
fi
if [ -z "$commit_msg" ]; then
    commit_msg="更新配置"
fi

if git diff --cached --quiet; then
    echo "没有可提交的内容"
else
    git commit -m "$commit_msg"
    echo "✅ 已提交: $commit_msg"
fi
echo ""

# ========== Git 推送 ==========
git push
echo "✅ 成功推送到 GitHub"
echo ""

echo "========================================"
echo "  ✅ 同步完成！"
echo "========================================"
echo ""

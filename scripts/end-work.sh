#!/bin/bash
# Claude Code - 结束工作 (Git Bash / Linux / Mac)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================"
echo "  Claude Code - 结束工作"
echo "========================================"
echo ""

cd "$REPO_DIR"

if [ -n "$USERPROFILE" ]; then
    USER_HOME="$USERPROFILE"
else
    USER_HOME="$HOME"
fi

echo "[1/5] 从本地同步配置到仓库..."

echo "同步 .claude.json..."
cp -f "$USER_HOME/.claude.json" "$REPO_DIR/.claude.json"
echo "   - .claude.json 已同步"

echo "智能同步 settings.json..."
if command -v node &> /dev/null; then
    node "$SCRIPT_DIR/sync-settings.js" push
else
    echo "⚠️  Node.js 未找到，使用直接复制方式"
    cp -f "$USER_HOME/.claude/settings.json" "$REPO_DIR/settings.json"
    echo "   - settings.json 已复制"
fi

echo "同步 CLAUDE.md..."
cp -f "/c/git/CLAUDE.md" "$REPO_DIR/CLAUDE.md" 2>/dev/null || true
echo "   - CLAUDE.md 已同步"

echo "✅ 配置文件收集完成"
echo ""

echo "[2/5] 检查 git 状态..."
git status --short
echo ""

echo "[3/5] 提交更改..."
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
echo ""

echo "[4/5] 推送到 GitHub..."
git push
echo "✅ 成功推送到 GitHub"
echo ""

echo "[5/5] 同步 Memory..."
MEMORY_FILE="$USER_HOME/.claude/projects/C--git/memory/MEMORY.md"
if [ -f "$MEMORY_FILE" ]; then
    cp -f "$MEMORY_FILE" "$REPO_DIR/memory/MEMORY.md"
    echo "   - MEMORY.md 已同步"
    git add "$REPO_DIR/memory/MEMORY.md"
else
    echo "   ⚠️  未找到 MEMORY.md"
fi
echo ""

echo "========================================"
echo "  ✅ 同步完成！"
echo "========================================"
echo ""

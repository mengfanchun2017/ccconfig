#!/bin/bash
# Claude Code - 开始工作 (Git Bash / Linux / Mac)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================"
echo "  Claude Code - 开始工作"
echo "========================================"
echo ""

cd "$REPO_DIR"

echo "[1/4] 从 GitHub 拉取最新配置..."
git pull
echo "✅ 成功拉取最新配置"
echo ""

echo "[2/4] 同步 .claude.json..."
if [ -n "$USERPROFILE" ]; then
    USER_HOME="$USERPROFILE"
else
    USER_HOME="$HOME"
fi
cp -f "$REPO_DIR/.claude.json" "$USER_HOME/.claude.json"
echo "   - .claude.json 已同步"

echo "[3/4] 智能同步 settings.json..."
if command -v node &> /dev/null; then
    node "$SCRIPT_DIR/sync-settings.js" pull
else
    echo "⚠️  Node.js 未找到，使用直接复制方式"
    if [ ! -d "$USER_HOME/.claude" ]; then
        mkdir -p "$USER_HOME/.claude"
    fi
    cp -f "$REPO_DIR/settings.json" "$USER_HOME/.claude/settings.json"
    echo "   - settings.json 已复制"
fi

echo "[4/4] 同步 CLAUDE.md..."
cp -f "$REPO_DIR/CLAUDE.md" "/c/git/CLAUDE.md" 2>/dev/null || true
echo "   - CLAUDE.md 已同步"
echo ""

echo "✅ 配置文件同步完成"
echo ""

echo "检查 Memory 符号链接..."
MEMORY_DIR="$USER_HOME/.claude/projects/C--git/memory"
if [ -d "$MEMORY_DIR" ]; then
    echo "   - Memory 目录已存在"
else
    echo "   ⚠️  Memory 目录不存在，请参考 README.md 手动设置"
fi
echo ""

echo "========================================"
echo "  ✅ 准备就绪！可以开始工作了"
echo "========================================"
echo ""
echo "提示: 如果配置有更新，请重启 Claude Code"
echo ""

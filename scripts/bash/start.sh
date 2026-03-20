#!/bin/bash
# Claude Code - 开始工作 (Linux/WSL)
#
# ============================================================
# 架构说明 - 双向同步机制
# ============================================================
#
# 本脚本通过符号链接实现本地配置与仓库的双向同步。
# 符号链接 = 两个路径指向同一个文件，修改任一，另一处同步变化。
#
# 同步结构：
#   settings.json  →  ~/.claude/settings.json
#   CLAUDE.md      →  ~/CLAUDE.md
#   MEMORY.md      →  ~/.claude/projects/{项目名}/memory/MEMORY.md
#
# 所有路径都链接到仓库中的源文件，实现双向同步。
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "========================================"
echo "  Claude Code - 开始工作"
echo "  当前系统: Linux/WSL"
echo "========================================"
echo ""
echo "仓库目录: $REPO_DIR"
echo "Claude 目录: $CLAUDE_DIR"
echo ""

# ========== Git Pull ==========
echo "[1/4] 从 GitHub 拉取最新配置..."
git pull
echo "✅ 成功拉取最新配置"
echo ""

# ========== settings.json 双向同步 ==========
echo "[2/4] 同步 settings.json (符号链接)..."
mkdir -p "$CLAUDE_DIR"
rm -f "$CLAUDE_DIR/settings.json" 2>/dev/null || true
ln -sf "$REPO_DIR/config/settings.json" "$CLAUDE_DIR/settings.json"
echo "   ✅ $CLAUDE_DIR/settings.json -> $REPO_DIR/config/settings.json"
echo ""

# ========== CLAUDE.md 双向同步 ==========
echo "[3/4] 同步 CLAUDE.md (符号链接)..."
rm -f "$HOME/CLAUDE.md" 2>/dev/null || true
ln -sf "$REPO_DIR/config/CLAUDE.md" "$HOME/CLAUDE.md"
echo "   ✅ $HOME/CLAUDE.md -> $REPO_DIR/config/CLAUDE.md"
echo ""

# ========== Memory 双向同步 ==========
echo "[4/4] Memory 同步 (符号链接)..."

# 获取当前项目路径
CLAUDE_PROJECT_PATH="$(pwd)"
CURRENT_PROJECT=$(basename "$CLAUDE_PROJECT_PATH")
echo "   检测到当前项目: $CURRENT_PROJECT"

# 如果是 claude-config 仓库，使用父目录
if [ "$CURRENT_PROJECT" = "claude-config" ]; then
    ACTUAL_PROJECT_PATH="$(dirname "$CLAUDE_PROJECT_PATH")"
    ACTUAL_PROJECT=$(basename "$ACTUAL_PROJECT_PATH")
    echo "   📍 检测到配置仓库，使用父项目: $ACTUAL_PROJECT"
else
    ACTUAL_PROJECT_PATH="$CLAUDE_PROJECT_PATH"
fi

# 转换路径为 Claude Code 格式: /home/francis/git -> -home-francis-git
REPO_MEMORY_NAME=$(echo "$ACTUAL_PROJECT_PATH" | sed 's/^\///' | sed 's/\//-/g')
MEMORY_DIR="$CLAUDE_DIR/projects/$REPO_MEMORY_NAME/memory"
MEMORY_REPO_PATH="$REPO_DIR/memory/$REPO_MEMORY_NAME/MEMORY.md"

echo "   仓库 Memory: $MEMORY_REPO_PATH"
echo "   本地 Memory: $MEMORY_DIR/MEMORY.md"

if [ -d "$REPO_DIR/memory/$REPO_MEMORY_NAME" ]; then
    mkdir -p "$MEMORY_DIR"
    rm -f "$MEMORY_DIR/MEMORY.md" 2>/dev/null || true
    ln -sf "$MEMORY_REPO_PATH" "$MEMORY_DIR/MEMORY.md"
    echo "   ✅ $REPO_MEMORY_NAME 的 Memory 已链接"
else
    echo "   ⚠️  仓库中未找到 $REPO_MEMORY_NAME 的 Memory，跳过"
fi
echo ""

echo "========================================"
echo "  ✅ 准备就绪！可以开始工作了"
echo "========================================"
echo ""
echo "提示: 所有配置已通过符号链接与仓库同步"
echo "      对任意文件的修改都会双向同步"
echo ""

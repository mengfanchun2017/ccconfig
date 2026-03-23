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
# ========== 符号链接检查函数 ==========
setup_symlink() {
    local link="$1"
    local target="$2"
    local name="$3"

    mkdir -p "$(dirname "$link")" 2>/dev/null || true

    if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$(readlink -f "$target")" ]; then
        echo "   ✅ $name: 已链接，跳过"
        return 0
    fi

    # 移除旧链接或文件
    rm -f "$link" 2>/dev/null || true
    ln -sf "$target" "$link"
    echo "   🔗 $name: 重新创建链接"
    return 0
}

echo "[1/4] 从 GitHub 拉取最新配置..."
git pull
echo "✅ 成功拉取最新配置"
echo ""

# ========== 获取项目信息 ==========
CLAUDE_PROJECT_PATH="$(pwd)"
CURRENT_PROJECT=$(basename "$CLAUDE_PROJECT_PATH")

if [ "$CURRENT_PROJECT" = "claude-config" ]; then
    ACTUAL_PROJECT_PATH="$(dirname "$CLAUDE_PROJECT_PATH")"
else
    ACTUAL_PROJECT_PATH="$CLAUDE_PROJECT_PATH"
fi

REPO_MEMORY_NAME=$(echo "$ACTUAL_PROJECT_PATH" | sed 's/^\///' | sed 's/\//-/g')
MEMORY_DIR="$CLAUDE_DIR/projects/$REPO_MEMORY_NAME/memory"
MEMORY_REPO_PATH="$REPO_DIR/memory/$REPO_MEMORY_NAME/MEMORY.md"

# ========== settings.json 双向同步 ==========
echo "[2/4] 同步 settings.json..."
setup_symlink "$CLAUDE_DIR/settings.json" "$REPO_DIR/config/settings.json" "settings.json"
echo ""

# ========== CLAUDE.md 双向同步 ==========
echo "[3/4] 同步 CLAUDE.md..."
setup_symlink "$HOME/CLAUDE.md" "$REPO_DIR/config/CLAUDE.md" "CLAUDE.md"
echo ""

# ========== Memory 双向同步 ==========
echo "[4/4] Memory 同步..."
if [ -d "$REPO_DIR/memory/$REPO_MEMORY_NAME" ]; then
    setup_symlink "$MEMORY_DIR/MEMORY.md" "$MEMORY_REPO_PATH" "MEMORY.md"
else
    echo "   ⚠️  仓库中未找到 Memory，跳过"
fi
echo ""

echo "========================================"
echo "  ✅ 准备就绪！可以开始工作了"
echo "========================================"
echo ""

# ========== 符号链接检查 ==========
echo "========================================"
echo "  🔍 符号链接状态检查"
echo "========================================"

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

check_symlink "$CLAUDE_DIR/settings.json" "settings.json"
check_symlink "$HOME/CLAUDE.md" "CLAUDE.md"
check_symlink "$MEMORY_DIR/MEMORY.md" "MEMORY.md"

echo ""

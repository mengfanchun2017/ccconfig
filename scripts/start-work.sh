#!/bin/bash
# Claude Code - 开始工作 (多平台版本)
# 支持: Windows (PowerShell/Git Bash), WSL (Ubuntu), Linux

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载公共函数库
source "$SCRIPT_DIR/lib-common.sh"

# 检测当前系统
OS_TYPE=$(detect_os)
echo "========================================"
echo "  Claude Code - 开始工作"
echo "  当前系统: $OS_TYPE"
echo "========================================"
echo ""

cd "$REPO_DIR"

# 获取用户主目录
USER_HOME=$(get_user_home)
echo "用户主目录: $USER_HOME"

# 获取 Claude 配置目录
CLAUDE_DIR=$(get_claude_dir)
echo "Claude 配置目录: $CLAUDE_DIR"

echo ""
echo "[1/3] 从 GitHub 拉取最新配置..."
git pull
echo_success "✅ 成功拉取最新配置"
echo ""

echo "[2/3] 智能同步 settings.json..."
if command -v node &> /dev/null; then
    node "$SCRIPT_DIR/sync-settings.js" pull
else
    echo_warn "⚠️  Node.js 未找到，使用直接复制方式"
    mkdir -p "$CLAUDE_DIR"
    cp -f "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"
    echo "   - settings.json 已复制"
fi

echo "[3/3] 同步 CLAUDE.md..."
sync_claude_md "pull"
echo ""

echo "✅ 配置文件同步完成"
echo ""

# 检查/创建 Memory 符号链接或目录
echo "检查 Memory 目录..."
PROJECT_PATH="$REPO_DIR"
MEMORY_DIR=$(get_memory_dir "$PROJECT_PATH")

if [ -d "$MEMORY_DIR" ]; then
    echo "   - Memory 目录已存在: $MEMORY_DIR"
else
    mkdir -p "$MEMORY_DIR"
    echo "   - 已创建 Memory 目录: $MEMORY_DIR"

    # 如果仓库中有 MEMORY.md，复制过去
    if [ -f "$REPO_DIR/memory/MEMORY.md" ]; then
        cp -f "$REPO_DIR/memory/MEMORY.md" "$MEMORY_DIR/MEMORY.md"
        echo "   - 已复制 MEMORY.md 到 Memory 目录"
    fi
fi
echo ""

echo "========================================"
echo "  ✅ 准备就绪！可以开始工作了"
echo "========================================"
echo ""
echo "提示: 如果配置有更新，请重启 Claude Code"
echo ""

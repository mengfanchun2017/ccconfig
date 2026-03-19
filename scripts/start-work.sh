#!/bin/bash
# Claude Code - 开始工作 (多平台版本)
# 支持: Windows (PowerShell/Git Bash), WSL (Ubuntu), Linux
# 自动检测当前项目：只匹配最后一级目录名

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
echo "[1/4] 从 GitHub 拉取最新配置..."
git pull
echo_success "✅ 成功拉取最新配置"
echo ""

echo "[2/4] 智能同步 settings.json..."
if command -v node &> /dev/null; then
    node "$SCRIPT_DIR/sync-settings.js" pull
else
    echo_warn "⚠️  Node.js 未找到，使用直接复制方式"
    mkdir -p "$CLAUDE_DIR"
    cp -f "$REPO_DIR/settings.json" "$CLAUDE_DIR/settings.json"
    echo "   - settings.json 已复制"
fi

echo "[3/4] 同步 CLAUDE.md..."
sync_claude_md "pull"
echo ""

# ========== Memory 自动同步 ==========
echo "[4/4] Memory 同步..."

# 获取当前目录的最后一级目录名
CURRENT_PROJECT=$(basename "$(pwd)")
echo "   检测到当前项目: $CURRENT_PROJECT"

# 检查仓库中是否存在该项目对应的 memory 目录
if [ -d "memory/$CURRENT_PROJECT" ]; then
    # 构建 Claude Code 项目路径
    # Linux/WSL: /home/francis/git -> /home/francis/.claude/projects/-home-francis-git/
    # Windows: C:\git -> C:\Users\franc\.claude\projects\C--git\
    CLAUDE_PROJECT_PATH="$HOME/$(basename "$(pwd)")"

    # 获取本地 Memory 目录
    MEMORY_DIR=$(get_memory_dir "$CLAUDE_PROJECT_PATH")
    echo "   Memory 目录: $MEMORY_DIR"

    # 创建目录并复制
    mkdir -p "$MEMORY_DIR"
    cp -f "memory/$CURRENT_PROJECT/MEMORY.md" "$MEMORY_DIR/MEMORY.md"
    echo_success "   ✅ $CURRENT_PROJECT 的 Memory 已同步"
else
    echo_warn "⚠️  仓库中未找到 $CURRENT_PROJECT 的 Memory，跳过"
    echo "   可用项目: $(ls -d memory/*/ 2>/dev/null | sed 's|/$||' | sed 's|memory/||' | tr '\n' ' ')"
fi
echo ""

echo "========================================"
echo "  ✅ 准备就绪！可以开始工作了"
echo "========================================"
echo ""
echo "提示: 如果配置有更新，请重启 Claude Code"
echo ""

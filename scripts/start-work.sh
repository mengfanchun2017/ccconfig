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

# ========== Memory 同步 ==========
echo "[4/4] Memory 同步..."

# 检查可选的项目列表
AVAILABLE_PROJECTS=$(ls -d memory/*/ 2>/dev/null | sed 's|/$||' | sed 's|memory/||' | tr '\n' ' ')

if [ -z "$AVAILABLE_PROJECTS" ]; then
    echo_warn "⚠️  仓库 memory 目录为空，无可同步的项目"
else
    echo "可选项目: $AVAILABLE_PROJECTS"
    echo ""

    # 如果传入了项目参数，使用它；否则让用户选择
    if [ -n "$1" ]; then
        SELECTED_PROJECT="$1"
    else
        echo "请选择要同步 Memory 的项目："
        echo "  1) git        (对应 $HOME/git 目录)"
        echo "  2) claude-config (对应 $HOME/git/claude-config 目录)"
        echo ""

        # 列出可用选项
        echo -n "请输入选项 [1]: "
        read choice
        choice="${choice:-1}"

        case "$choice" in
            1|"git")
                SELECTED_PROJECT="git"
                ;;
            2|"claude-config")
                SELECTED_PROJECT="claude-config"
                ;;
            *)
                echo_warn "无效选择，默认使用 git"
                SELECTED_PROJECT="git"
                ;;
        esac
    fi

    echo "   选中项目: $SELECTED_PROJECT"

    # 检查仓库中是否存在该项目对应的 memory 目录
    if [ -d "memory/$SELECTED_PROJECT" ]; then
        # 获取 Claude Code 中对应的项目路径名
        case "$SELECTED_PROJECT" in
            git)
                # git 根目录对应的项目名
                if [ "$OS_TYPE" = "wsl" ] || [ "$OS_TYPE" = "linux" ]; then
                    CLAUDE_PROJECT_PATH="$HOME/git"
                else
                    CLAUDE_PROJECT_PATH="$USER_HOME\\git"
                fi
                ;;
            claude-config)
                # claude-config 目录对应的项目名
                if [ "$OS_TYPE" = "wsl" ] || [ "$OS_TYPE" = "linux" ]; then
                    CLAUDE_PROJECT_PATH="$HOME/git/claude-config"
                else
                    CLAUDE_PROJECT_PATH="$USER_HOME\\git\\claude-config"
                fi
                ;;
            *)
                CLAUDE_PROJECT_PATH="$HOME/git/$SELECTED_PROJECT"
                ;;
        esac

        # 获取本地 Memory 目录
        MEMORY_DIR=$(get_memory_dir "$CLAUDE_PROJECT_PATH")
        echo "   Memory 目录: $MEMORY_DIR"

        # 创建目录并复制
        mkdir -p "$MEMORY_DIR"
        cp -f "memory/$SELECTED_PROJECT/MEMORY.md" "$MEMORY_DIR/MEMORY.md"
        echo_success "   ✅ $SELECTED_PROJECT 的 Memory 已同步"
    else
        echo_warn "⚠️  仓库中未找到 $SELECTED_PROJECT 的 Memory"
    fi
fi
echo ""

echo "========================================"
echo "  ✅ 准备就绪！可以开始工作了"
echo "========================================"
echo ""
echo "提示: 如果配置有更新，请重启 Claude Code"
echo ""

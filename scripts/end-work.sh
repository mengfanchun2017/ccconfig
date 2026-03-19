#!/bin/bash
# Claude Code - 结束工作 (多平台版本)
# 支持: Windows (PowerShell/Git Bash), WSL (Ubuntu), Linux

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载公共函数库
source "$SCRIPT_DIR/lib-common.sh"

# 检测当前系统
OS_TYPE=$(detect_os)
echo "========================================"
echo "  Claude Code - 结束工作"
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
echo "[1/5] 从本地同步配置到仓库..."

echo "智能同步 settings.json..."
if command -v node &> /dev/null; then
    node "$SCRIPT_DIR/sync-settings.js" push
else
    echo_warn "⚠️  Node.js 未找到，使用直接复制方式"
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        cp -f "$CLAUDE_DIR/settings.json" "$REPO_DIR/settings.json"
        echo "   - settings.json 已复制"
    else
        echo_warn "   ⚠️  未找到 settings.json"
    fi
fi

echo "同步 CLAUDE.md..."
sync_claude_md "push"

echo_success "✅ 配置文件收集完成"
echo ""

# ========== Memory 同步 ==========
echo "Memory 同步..."

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

    # 获取 Claude Code 中对应的项目路径名
    case "$SELECTED_PROJECT" in
        git)
            if [ "$OS_TYPE" = "wsl" ] || [ "$OS_TYPE" = "linux" ]; then
                CLAUDE_PROJECT_PATH="$HOME/git"
            else
                CLAUDE_PROJECT_PATH="$USER_HOME\\git"
            fi
            ;;
        claude-config)
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

    if [ -d "$MEMORY_DIR" ] && [ -f "$MEMORY_DIR/MEMORY.md" ]; then
        mkdir -p "memory/$SELECTED_PROJECT"
        cp -f "$MEMORY_DIR/MEMORY.md" "memory/$SELECTED_PROJECT/MEMORY.md"
        git add "memory/$SELECTED_PROJECT/MEMORY.md"
        echo_success "   ✅ $SELECTED_PROJECT 的 Memory 已同步"
    else
        echo_warn "   ⚠️  未找到 Memory: $MEMORY_DIR/MEMORY.md"
    fi
fi
echo ""

echo "[2/5] 检查 git 状态..."
git status --short
echo ""

echo "[3/5] 提交更改..."
git add .
if [ -z "$2" ]; then
    read -p "请输入提交信息 (默认: 更新配置): " commit_msg
else
    commit_msg="$2"
fi
if [ -z "$commit_msg" ]; then
    commit_msg="更新配置"
fi
git commit -m "$commit_msg"
echo ""

echo "[4/5] 推送到 GitHub..."
git push
echo_success "✅ 成功推送到 GitHub"
echo ""

echo "[5/5] 完成"
echo ""

echo "========================================"
echo "  ✅ 同步完成！"
echo "========================================"
echo ""

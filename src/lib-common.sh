#!/bin/bash
# Claude Code 配置同步 - 公共函数库
# 支持: Windows (PowerShell/Git Bash), WSL (Ubuntu), Linux

# 检测运行环境
detect_os() {
    if [ -n "$WSL_DISTRO_NAME" ] || [ -n "$WSLENV" ]; then
        echo "wsl"
    elif [ -n "$USERPROFILE" ] && [ -n "$SYSTEMROOT" ]; then
        echo "windows"
    else
        echo "linux"
    fi
}

# 检测是否是 WSL 与 Windows 共存环境
is_wsl_with_windows_home() {
    if [ -n "$WSL_DISTRO_NAME" ] && [ -n "$USERPROFILE" ]; then
        return 0  # true
    fi
    return 1  # false
}

# 获取用户主目录
get_user_home() {
    local os=$(detect_os)
    case "$os" in
        wsl)
            # WSL: 根据配置选择 Windows 主目录或 Linux 主目录
            # 优先使用 Windows 主目录以保持与 Windows 端配置一致
            if [ -n "$USERPROFILE" ]; then
                # 转换 Windows 路径到 WSL 路径
                local win_home
                win_home=$(echo "$USERPROFILE" | sed 's/\\/\//g' | sed 's/^\([A-Z]\):/\L\1/' | sed 's/^c/\/c/' | sed 's/^d/\/d/')
                echo "$win_home"
            else
                echo "$HOME"
            fi
            ;;
        windows)
            echo "$USERPROFILE"
            ;;
        *)
            echo "$HOME"
            ;;
    esac
}

# 获取 Linux 原生主目录（不使用 Windows 主目录）
get_linux_home() {
    echo "$HOME"
}

# 获取 Claude 配置目录
get_claude_dir() {
    local home=$(get_user_home)
    local os=$(detect_os)

    case "$os" in
        wsl|linux)
            # Linux/WSL: ~/.claude
            echo "$home/.claude"
            ;;
        windows)
            # Windows: %USERPROFILE%\.claude
            echo "$home/.claude"
            ;;
        *)
            echo "$home/.claude"
            ;;
    esac
}

# 获取项目根目录（CLAUDE.md 所在目录）
# WSL: 返回 WSL 路径
# Windows: 返回 Windows 路径
get_project_root() {
    local os=$(detect_os)
    case "$os" in
        wsl)
            # WSL: 使用仓库的 WSL 路径
            echo "$REPO_DIR"
            ;;
        windows)
            # Windows: 使用仓库的 Windows 路径
            echo "C:\\git"
            ;;
        *)
            echo "$REPO_DIR"
            ;;
    esac
}

# 获取项目记忆目录路径
# 参数: 项目路径 (如 /home/francis/git 或 C:\git)
# 注意: 这里指的是 Claude Code 打开的项目目录，即 claude-config 仓库的位置
get_memory_dir() {
    local project_path="$1"
    local claude_dir=$(get_claude_dir)
    local os=$(detect_os)

    # 将项目路径转换为 Claude Code 使用的目录名
    # C:\git -> C--git
    # /home/francis/git -> -home-francis-git
    # C:\git\claude-config -> C--git-claude-config
    # /home/francis/git/claude-config -> -home-francis-git-claude-config
    local dir_name
    case "$os" in
        wsl|linux)
            # Linux/WSL: 替换 / 为 -
            dir_name=$(echo "$project_path" | sed 's/^\///' | sed 's/\//-/g')
            ;;
        windows)
            # Windows: 替换 \ 为 -，替换 : 为空
            dir_name=$(echo "$project_path" | sed 's/\\/-/g' | sed 's/://g')
            ;;
    esac

    echo "$claude_dir/projects/$dir_name/memory"
}

# 获取 CLAUDE.md 路径（项目根目录）
get_claude_md_path() {
    local project_path="$1"
    local os=$(detect_os)

    case "$os" in
        wsl)
            # WSL: 直接使用 Linux 路径
            echo "$project_path/CLAUDE.md"
            ;;
        windows)
            # Windows: 保持 Windows 路径格式
            echo "$project_path/CLAUDE.md"
            ;;
        *)
            echo "$project_path/CLAUDE.md"
            ;;
    esac
}

# 同步 CLAUDE.md 文件
# 参数: pull - 从仓库拉取到本地; push - 从本地推送到仓库
sync_claude_md() {
    local action="$1"
    local os=$(detect_os)
    local repo_claude_md="$REPO_DIR/config/CLAUDE.md"

    case "$os" in
        wsl|linux)
            # Linux/WSL: 同步到 Linux 主目录下的 CLAUDE.md
            local linux_home=$(get_linux_home)
            local local_claude_md="$linux_home/CLAUDE.md"

            if [ "$action" = "pull" ]; then
                # 从仓库拉取到本地
                if [ -f "$repo_claude_md" ]; then
                    cp -f "$repo_claude_md" "$local_claude_md"
                    echo "   - CLAUDE.md 已同步 (Linux: $local_claude_md)"
                else
                    echo_warn "   ⚠️  仓库中未找到 CLAUDE.md"
                fi
            else
                # 从本地推送到仓库
                if [ -f "$local_claude_md" ]; then
                    cp -f "$local_claude_md" "$repo_claude_md"
                    echo "   - CLAUDE.md 已同步 (仓库: $repo_claude_md)"
                else
                    echo_warn "   ⚠️  本地未找到 CLAUDE.md: $local_claude_md"
                fi
            fi
            ;;
        windows)
            # Windows: CLAUDE.md 位于 C:\git\CLAUDE.md，由仓库直接管理
            # Windows 下 CLAUDE.md 路径由仓库管理，无需额外同步
            if [ "$action" = "pull" ]; then
                echo "   - CLAUDE.md 由仓库直接管理"
            else
                echo "   - CLAUDE.md 由仓库直接管理"
            fi
            ;;
    esac
}

# 调试输出
debug_echo() {
    if [ "$DEBUG" = "1" ]; then
        echo "[DEBUG] $*"
    fi
}

# 彩色输出
echo_info() {
    echo -e "\033[36m$1\033[0m"
}

echo_success() {
    echo -e "\033[32m$1\033[0m"
}

echo_warn() {
    echo -e "\033[33m$1\033[0m"
}

echo_error() {
    echo -e "\033[31m$1\033[0m"
}

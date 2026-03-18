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

# 获取用户主目录
get_user_home() {
    local os=$(detect_os)
    case "$os" in
        wsl)
            # WSL: 优先使用 Windows 主目录（如果可用），否则用 Linux 主目录
            if [ -n "$USERPROFILE" ]; then
                # 转换 Windows 路径到 WSL 路径
                echo "$USERPROFILE" | sed 's/\\/\//g' | sed 's/^C:\/c/' | sed 's/^D:\/d/' || echo "$HOME"
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

# 获取 Claude 配置目录
get_claude_dir() {
    local home=$(get_user_home)
    local os=$(detect_os)

    case "$os" in
        wsl)
            # WSL: ~/.claude
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

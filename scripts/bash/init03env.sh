#!/bin/bash
# Claude Code 环境准备脚本
# 用途：安装运行时环境依赖 + 建立符号链接
#
# 使用方法（从仓库上级目录运行）：
#   bash claude-config/scripts/bash/init03env.sh
#
# 此脚本会：
#   1. 安装 MCP 服务器所需的运行时环境
#      - Node.js (用于 npm/npx-based MCP 服务器)
#      - uv (用于 Python-based MCP 服务器)
#      - Playwright (浏览器自动化)
#      - 中文字体
#   2. 建立符号链接实现配置双向同步
#      - settings.json → ~/.claude/settings.json
#      - CLAUDE.md → ~/CLAUDE.md
#      - MEMORY.md → ~/.claude/projects/.../memory/MEMORY.md
#
# 安装完成后，请运行 init04mcp.sh 安装具体的 MCP 服务器：
#   bash claude-config/scripts/bash/init04mcp.sh

set -e

# 版本
NODE_VERSION="20.11.0"
UV_VERSION="0.10.12"

# 目录
LOCAL_DIR="/home/francis/.local"
BIN_DIR="${LOCAL_DIR}/bin"
NODE_DIR="${LOCAL_DIR}/node-v${NODE_VERSION}-linux-x64"
UV_DIR="${LOCAL_DIR}/uv-${UV_VERSION}-x86_64-unknown-linux-gnu"
TARBALL="/tmp/node.tar.gz"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
good() { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "${CYAN}=== $1 ===${NC}"; }

# 检查命令是否存在
check_command() {
    command -v "$1" &> /dev/null
}

# ========== Node.js ==========
check_node_installed() {
    if check_command node; then
        local current_version=$(node --version 2>/dev/null || echo "unknown")
        info "Node.js 已安装: $current_version"
        return 0
    fi
    return 1
}

install_nodejs() {
    section "安装 Node.js"

    local url="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz"
    info "下载 Node.js v${NODE_VERSION}..."
    info "URL: $url"

    if ! curl -fsSL "$url" -o "$TARBALL"; then
        error "Node.js 下载失败"
        return 1
    fi
    info "下载完成"

    info "解压到 ~/.local/..."
    tar -xzf "$TARBALL" -C "$LOCAL_DIR/"

    mkdir -p "$BIN_DIR"

    info "创建符号链接..."
    ln -sf "${NODE_DIR}/bin/node" "${BIN_DIR}/node"
    ln -sf "${NODE_DIR}/bin/npm" "${BIN_DIR}/npm"
    ln -sf "${NODE_DIR}/bin/npx" "${BIN_DIR}/npx"

    rm -f "$TARBALL"
    info "Node.js 安装完成"
}

verify_nodejs() {
    echo ""
    info "Node.js 验证:"
    echo "  node: $(node --version)"
    echo "  npm:  $(npm --version)"
    echo "  npx:  $(npx --version 2>/dev/null || echo 'not found')"
    echo ""
}

setup_path() {
    # 确保 ~/.local/bin 在 PATH 中
    local local_bin="$HOME/.local/bin"
    if [[ ":$PATH:" != *":$local_bin:"* ]]; then
        info "添加 $local_bin 到 PATH..."
        if ! grep -q "\.local/bin" "$HOME/.bashrc" 2>/dev/null; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        export PATH="$local_bin:$PATH"
        good "PATH 已更新"
    else
        info "PATH 已包含 $local_bin"
    fi
}

# ========== uv (Python 包管理器) ==========
check_uv_installed() {
    if check_command uvx || check_command uv; then
        local version=$(uvx --version 2>/dev/null || uv --version 2>/dev/null || echo "unknown")
        info "uv 已安装: $version"
        return 0
    fi
    return 1
}

install_uv() {
    section "安装 uv"

    info "使用官方安装脚本安装 uv..."
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
        error "uv 安装失败"
        return 1
    fi

    info "uv 安装完成"
}

verify_uv() {
    echo ""
    info "uv 验证:"
    echo "  uv:  $(uv --version)"
    echo "  uvx: $(uvx --version)"
    echo ""
}

# ========== Playwright 浏览器 ==========
check_playwright_installed() {
    if check_command npx; then
        # 使用 timeout 避免 npx 长时间卡住（最多 10 秒）
        local version=$(timeout 10 npx playwright --version 2>/dev/null || echo "")
        if [[ -n "$version" ]]; then
            info "Playwright 已安装: $version"
            return 0
        fi
    fi
    return 1
}

install_playwright_browsers() {
    section "安装 Playwright 浏览器"

    if ! check_command npx; then
        error "npx 未安装，请先安装 Node.js"
        return 1
    fi

    info "安装 Playwright chromium (官方推荐)..."

    # 先在临时目录安装 playwright（避免项目目录未初始化导致的警告）
    local tmp_dir="/tmp/pw-install-$$"
    mkdir -p "$tmp_dir"
    cd "$tmp_dir"
    npm init -y > /dev/null 2>&1
    npm install playwright > /dev/null 2>&1

    # 使用临时目录的 playwright 安装 chromium，添加超时
    # 如果下载失败会重试3次，每次超时2分钟
    local max_attempts=3
    local attempt=1
    local success=false

    while [[ $attempt -le $max_attempts ]] && [[ "$success" == "false" ]]; do
        echo ""
        info "尝试 $attempt/$max_attempts..."

        # 设置超时 120 秒，如果超时或失败则重试
        if timeout 180 ./node_modules/.bin/playwright install chromium 2>&1; then
            success=true
            good "Chromium 安装成功"
        else
            if [[ $attempt -lt $max_attempts ]]; then
                warn "下载失败，10秒后重试..."
                sleep 10
            fi
            attempt=$((attempt + 1))
        fi
    done

    if [[ "$success" == "false" ]]; then
        warn "Chromium 下载失败，将跳过安装"
        warn "可以稍后手动运行: npx playwright install chromium"
    fi

    # 清理临时目录
    cd - > /dev/null
    rm -rf "$tmp_dir"
}

verify_playwright() {
    echo ""
    info "Playwright 验证:"
    if check_command npx; then
        echo "  npx playwright: $(timeout 10 npx playwright --version 2>/dev/null || echo '未安装')"
        echo "  浏览器缓存: $(ls ~/.cache/ms-playwright/ 2>/dev/null | wc -l) 个"
    fi
    echo ""
}

# ========== 中文字体 ==========
check_chinese_fonts() {
    if fc-list :lang=zh 2>/dev/null | grep -q .; then
        info "中文字体已安装"
        return 0
    fi
    return 1
}

install_chinese_fonts() {
    section "安装中文字体"

    # 优先使用用户级字体安装（无需 sudo）
    USER_FONTS_DIR="$HOME/.local/share/fonts"
    FONT_URL="https://github.com/anthtype/wqy/raw/main/fonts/wqy-microhei.ttc"

    mkdir -p "$USER_FONTS_DIR"

    if command -v apt-get &>/dev/null; then
        local fonts_pkg="fonts-wqy-microhei"

        # 先尝试用户级安装（下载字体）
        if command -v curl &>/dev/null; then
            info "用户级安装中文字体（无需 sudo）..."
            if curl -fsSL "$FONT_URL" -o "$USER_FONTS_DIR/wqy-microhei.ttc" 2>/dev/null; then
                fc-cache -f "$USER_FONTS_DIR" 2>/dev/null && success "字体已安装到 $USER_FONTS_DIR" && return 0
            fi
        fi

        # 下载失败或无 curl，提示用户用 sudo 安装
        warn "用户级安装失败，需要 sudo 权限安装系统字体"
        echo ""
        echo "请选择："
        echo "  1) 使用 sudo 安装系统字体（推荐）"
        echo "  2) 跳过字体安装"
        echo "  3) 手动安装后继续"
        echo ""
        read -p "请输入选项 [1]: " font_choice
        font_choice="${font_choice:-1}"

        if [[ "$font_choice" == "1" ]]; then
            if command -v sudo &>/dev/null; then
                sudo apt-get update && sudo apt-get install -y $fonts_pkg fontconfig 2>&1 || {
                    warn "sudo 安装失败，请手动执行:"
                    echo "  sudo apt-get install $fonts_pkg fontconfig"
                    return 1
                }
            else
                apt-get update && apt-get install -y $fonts_pkg fontconfig 2>&1 || {
                    warn "需要 root 权限，请手动执行:"
                    echo "  apt-get install $fonts_pkg fontconfig"
                    return 1
                }
            fi
            fc-cache -f 2>/dev/null && info "字体缓存已刷新"
        elif [[ "$font_choice" == "3" ]]; then
            info "请手动安装字体后继续"
            return 1
        else
            info "跳过字体安装"
        fi
    else
        warn "未检测到 apt-get，请手动安装中文字体"
    fi
}

verify_fonts() {
    echo ""
    info "字体验证:"
    echo "  中文字体数量: $(fc-list :lang=zh 2>/dev/null | grep -c . || echo 0)"
    echo ""
}

# ========== 主流程 ==========
main() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CLAUDE_DIR="$HOME/.claude"

    echo "========================================"
    echo "  Claude Code 环境准备脚本"
    echo "========================================"
    echo ""

    echo "此脚本将："
    echo "  1. 安装 MCP 服务器所需的运行时环境"
    echo "     - Node.js - npm/npx-based MCP 服务器"
    echo "     - uv - Python-based MCP 服务器"
    echo "     - Playwright - 浏览器自动化"
    echo "     - 中文字体"
    echo "  2. 建立符号链接实现配置双向同步"
    echo ""
    echo "安装完成后请运行 mcpcheck.sh 安装具体的 MCP 服务器"
    echo ""

    # Node.js
    section "检测 Node.js"
    if check_node_installed; then
        warn "跳过 Node.js 安装（已存在）"
        verify_nodejs
    else
        install_nodejs
        verify_nodejs
    fi

    # 确保 PATH 包含 ~/.local/bin
    setup_path

    # uv
    section "检测 uv"
    if check_uv_installed; then
        warn "跳过 uv 安装（已存在）"
        verify_uv
    else
        install_uv
        verify_uv
    fi

    # Playwright
    section "检测 Playwright"
    if check_playwright_installed; then
        warn "跳过 Playwright 安装（已存在）"
        verify_playwright
    else
        info "安装 Playwright CLI..."
        if npm install -g playwright &>/dev/null; then
            info "Playwright CLI 安装成功"
        else
            warn "Playwright CLI 安装失败，但可通过 npx 使用"
        fi
        verify_playwright
    fi

    # Playwright 浏览器
    section "检测 Playwright 浏览器"
    if ls ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome &>/dev/null || \
       ls ~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux64/chrome &>/dev/null; then
        warn "跳过浏览器安装（已存在）"
    else
        install_playwright_browsers
    fi
    verify_playwright

    # 中文字体
    section "检测中文字体"
    if check_chinese_fonts; then
        warn "跳过中文字体安装（已存在）"
    else
        install_chinese_fonts
    fi
    verify_fonts

    # ========== 建立符号链接 ==========
    section "建立符号链接"

    # 获取当前项目路径
    CLAUDE_PROJECT_PATH="$(pwd)"
    CURRENT_PROJECT=$(basename "$CLAUDE_PROJECT_PATH")

    # 如果是 claude-config 仓库，使用父目录
    if [ "$CURRENT_PROJECT" = "claude-config" ]; then
        ACTUAL_PROJECT_PATH="$(dirname "$CLAUDE_PROJECT_PATH")"
    else
        ACTUAL_PROJECT_PATH="$CLAUDE_PROJECT_PATH"
    fi

    # 转换路径为 Claude Code 格式: /home/francis/git -> -home-francis-git
    REPO_MEMORY_NAME=$(echo "$ACTUAL_PROJECT_PATH" | sed 's/^\///' | sed 's/\//-/g')
    MEMORY_DIR="$CLAUDE_DIR/projects/$REPO_MEMORY_NAME/memory"
    MEMORY_REPO_PATH="$REPO_DIR/memory/$REPO_MEMORY_NAME/MEMORY.md"

    # 符号链接检查函数
    setup_symlink() {
        local link="$1"
        local target="$2"
        local name="$3"

        if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$(readlink -f "$target")" ]; then
            info "$name: 已链接，跳过"
            return 0
        elif [ -L "$link" ] || [ -e "$link" ]; then
            rm -f "$link"
        fi

        mkdir -p "$(dirname "$link")"
        ln -sf "$target" "$link"
        good "$name: 已建立链接"
        return 0
    }

    # settings.json
    setup_symlink "$CLAUDE_DIR/settings.json" "$REPO_DIR/config/settings.json" "settings.json"

    # CLAUDE.md
    setup_symlink "$HOME/CLAUDE.md" "$REPO_DIR/config/CLAUDE.md" "CLAUDE.md"

    # MEMORY.md
    if [ -d "$REPO_DIR/memory/$REPO_MEMORY_NAME" ]; then
        mkdir -p "$MEMORY_DIR"
        setup_symlink "$MEMORY_DIR/MEMORY.md" "$MEMORY_REPO_PATH" "MEMORY.md"
    else
        info "MEMORY.md: 仓库中未找到对应目录，跳过"
    fi

    echo ""

    section "安装完成"
    echo ""
    info "环境准备就绪，符号链接已建立"
    echo ""
    echo "========================================"
    echo "  📋 下一步操作"
    echo "========================================"
    echo ""
    echo "  安装 MCP 服务器："
    echo "  bash claude-config/scripts/bash/init04mcp.sh"
    echo ""
    echo "  或运行每日启动（同步 + 开始工作）："
    echo "  bash claude-config/scripts/bash/start.sh"
    echo ""
}

main "$@"

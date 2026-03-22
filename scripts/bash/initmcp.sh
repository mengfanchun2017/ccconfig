#!/bin/bash
# MCP 环境准备脚本
# 用途：为 Claude Code MCP 安装运行时环境依赖
#
# 使用方法：
#   bash scripts/bash/initmcp.sh
#
# 此脚本会检测并安装 MCP 服务器所需的依赖：
#   1. Node.js (用于 npm/npx-based MCP 服务器)
#   2. uv (用于 Python-based MCP 服务器)
#   3. Playwright (浏览器自动化 - 网页截图/抓取/交互)
#   4. 中文字体 (用于显示中文网页)
#
# 安装完成后，请运行 mcpcheck.sh 安装具体的 MCP 服务器：
#   bash scripts/bash/mcpcheck.sh
#
# MCP 服务器安装完成后，在 Claude Code 中执行 /mcp 添加服务器

set -e

# 版本
NODE_VERSION="20.11.0"
UV_VERSION=""

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
        if npx playwright --version &>/dev/null; then
            local version=$(npx playwright --version 2>/dev/null || echo "unknown")
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
    if npx playwright install chromium 2>&1; then
        good "Chromium 安装成功"
    else
        warn "Chromium 安装可能需要 sudo 权限"
    fi
}

verify_playwright() {
    echo ""
    info "Playwright 验证:"
    if check_command npx; then
        echo "  npx playwright: $(npx playwright --version 2>/dev/null || echo '未安装')"
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

    info "安装 Noto CJK 中文字体..."
    if command -v apt-get &>/dev/null; then
        # 检测 sudo
        if command -v sudo &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y fonts-noto-cjk fontconfig 2>&1 || {
                warn "需要 sudo 权限，请手动执行:"
                echo "  sudo apt-get install fonts-noto-cjk fontconfig"
            }
        else
            apt-get update && apt-get install -y fonts-noto-cjk fontconfig 2>&1 || {
                warn "需要 root 权限，请手动执行:"
                echo "  apt-get install fonts-noto-cjk fontconfig"
            }
        fi
        fc-cache -f 2>/dev/null && info "字体缓存已刷新" || true
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
    echo "========================================"
    echo "  MCP 环境准备脚本"
    echo "========================================"
    echo ""

    echo "此脚本将安装 MCP 服务器所需的运行时环境："
    echo "  1. Node.js - 用于 npm/npx-based MCP 服务器"
    echo "  2. uv - 用于 Python-based MCP 服务器"
    echo "  3. Playwright - 用于浏览器自动化"
    echo "  4. 中文字体 - 用于显示中文网页"
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
    if ls ~/.cache/ms-playwright/chromium-*/chrome-linux/chrome &>/dev/null || \
       ls ~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/chrome &>/dev/null; then
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

    section "安装完成"
    echo ""
    info "MCP 环境已准备就绪"
    echo ""
    echo "下一步："
    echo "  1. 运行 mcpcheck.sh 安装具体的 MCP 服务器"
    echo "     bash scripts/bash/mcpcheck.sh"
    echo ""
    echo "  2. 在 Claude Code 中执行 /mcp 添加服务器"
    echo ""
}

main "$@"

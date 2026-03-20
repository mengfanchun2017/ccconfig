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
#
# 安装完成后，请运行 mcpcheck.sh 安装具体的 MCP 服务器：
#   bash scripts/bash/mcpcheck.sh
#
# MCP 服务器安装完成后，在 Claude Code 中执行 /mcp 添加服务器

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

    # 检测架构
    local arch=$(uname -m)
    if [ "$arch" = "x86_64" ]; then
        local arch_str="x86_64-unknown-linux-gnu"
    elif [ "$arch" = "aarch64" ]; then
        local arch_str="aarch64-unknown-linux-gnu"
    else
        warn "不支持的架构: $arch，尝试 x86_64"
        local arch_str="x86_64-unknown-linux-gnu"
    fi

    local url="https://astral.sh/uv/${UV_VERSION}/uv-${UV_VERSION}-${arch_str}.tar.gz"
    info "下载 uv v${UV_VERSION}..."
    info "URL: $url"

    local tarball="/tmp/uv.tar.gz"
    if ! curl -fsSL "$url" -o "$tarball"; then
        error "uv 下载失败"
        return 1
    fi
    info "下载完成"

    info "解压到 ~/.local/..."
    tar -xzf "$tarball" -C "$LOCAL_DIR/"

    mkdir -p "$BIN_DIR"

    info "创建符号链接..."
    ln -sf "${UV_DIR}/uv" "${BIN_DIR}/uv"
    ln -sf "${UV_DIR}/uvx" "${BIN_DIR}/uvx"

    rm -f "$tarball"
    info "uv 安装完成"
}

verify_uv() {
    echo ""
    info "uv 验证:"
    echo "  uv:  $(uv --version)"
    echo "  uvx: $(uvx --version)"
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

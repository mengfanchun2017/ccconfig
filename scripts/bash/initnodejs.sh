#!/bin/bash
# Node.js 安装脚本
# 用途：为 Claude Code MCP 安装 Node.js 环境（npm/npx 需要）
#
# 使用方法：
#   bash scripts/bash/install-nodejs.sh
#
# 此脚本会：
#   1. 检测 Node.js 是否已安装
#   2. 下载并安装 Node.js 20.x LTS 到 ~/.local/
#   3. 创建 node, npm, npx 符号链接到 ~/.local/bin/
#
# 安装完成后运行 mcpcheck 安装 MCP：
#   bash scripts/bash/mcpcheck.sh

set -e

NODE_VERSION="20.11.0"
NODE_DIR="/home/francis/.local/node-v${NODE_VERSION}-linux-x64"
BIN_DIR="/home/francis/.local/bin"
TARBALL="/tmp/node.tar.gz"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查是否已安装
check_installed() {
    if command -v node &> /dev/null; then
        local current_version=$(node --version 2>/dev/null || echo "unknown")
        info "Node.js 已安装: $current_version"
        return 0
    fi
    return 1
}

# 下载 Node.js
download_node() {
    local url="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz"

    info "下载 Node.js v${NODE_VERSION}..."
    info "URL: $url"

    if curl -fsSL "$url" -o "$TARBALL"; then
        info "下载完成"
        return 0
    else
        error "下载失败"
        return 1
    fi
}

# 安装 Node.js
install_node() {
    info "解压到 ~/.local/..."
    tar -xzf "$TARBALL" -C "$HOME/.local/"

    # 创建 bin 目录
    mkdir -p "$BIN_DIR"

    # 创建符号链接
    info "创建符号链接..."

    ln -sf "${NODE_DIR}/bin/node" "${BIN_DIR}/node"
    ln -sf "${NODE_DIR}/bin/npm" "${BIN_DIR}/npm"
    ln -sf "${NODE_DIR}/bin/npx" "${BIN_DIR}/npx"

    # 清理
    rm -f "$TARBALL"

    info "安装完成"
}

# 验证安装
verify_install() {
    info "验证安装..."
    echo ""
    echo "  node: $(node --version)"
    echo "  npm:  $(npm --version)"
    echo "  npx:  $(npx --version)"
    echo ""
}

# 主流程
main() {
    echo "========================================"
    echo "  Node.js 安装脚本"
    echo "========================================"
    echo ""

    if check_installed; then
        read -p "Node.js 已存在，是否重新安装? [y/N]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            info "跳过安装"
            exit 0
        fi
    fi

    if download_node; then
        install_node
        verify_install
    else
        error "安装失败"
        exit 1
    fi
}

main "$@"

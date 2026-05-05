#!/bin/bash
# ccconfig/feishu/init-cconnect.sh
# 兼容包装器：安装 cc-connect 二进制 → 委托 ailabbot 生成配置
#
# 使用：
#   bash ccconfig/feishu/init-cconnect.sh   # 完整安装+配置

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AILABBOT_INIT="$SCRIPT_DIR/../ailabbot/scripts/init.sh"
CC_CONNECT_VERSION="1.3.2"
CC_CONNECT_BIN="$HOME/.local/bin/cc-connect"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad() { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║     cc-connect 初始化（ailabbot 委托）          ║"
echo "╚══════════════════════════════════════════════════╝"
echo "$NC"

# ========== 环境检查 ==========
export PATH="$HOME/.local/bin:$HOME/.local/node-v20.11.0-linux-x64/bin:$PATH"

echo -n "Node.js ... "
if command -v node &> /dev/null; then
    good "✓ $(node --version)"
else
    bad "❌ 未安装，请先运行 bash ccconfig/init-ubuntu.sh"
    exit 1
fi

echo -n "Claude Code ... "
if command -v claude &> /dev/null; then
    good "✓"
else
    bad "❌ 未安装"
    exit 1
fi

# ========== 安装 cc-connect 二进制 ==========
echo ""
echo -e "${CYAN}── 安装 cc-connect ──${NC}"

if [ -x "$CC_CONNECT_BIN" ]; then
    current_ver=$("$CC_CONNECT_BIN" --version 2>/dev/null | head -1 || echo "unknown")
    good "✓ 已安装: $current_ver"
else
    echo "下载 cc-connect v${CC_CONNECT_VERSION} ..."
    local download_url="https://github.com/chenhg5/cc-connect/releases/download/v${CC_CONNECT_VERSION}/cc-connect-v${CC_CONNECT_VERSION}-linux-amd64.tar.gz"
    local tmp_dir="/tmp/cc-connect-install-$$"

    mkdir -p "$tmp_dir" "$HOME/.local/bin"

    if curl -fsSL "$download_url" -o "$tmp_dir/cc-connect.tar.gz"; then
        tar -xzf "$tmp_dir/cc-connect.tar.gz" -C "$tmp_dir"
        binary=$(find "$tmp_dir" -name "cc-connect" -type f 2>/dev/null | head -1)
        if [ -n "$binary" ]; then
            cp "$binary" "$CC_CONNECT_BIN"
            chmod +x "$CC_CONNECT_BIN"
            good "✅ 安装成功: $CC_CONNECT_BIN"
        fi
    else
        bad "❌ 下载失败"
        warn "手动下载: https://github.com/chenhg5/cc-connect/releases"
        exit 1
    fi
    rm -rf "$tmp_dir"
fi

# ========== 委托 ailabbot 生成配置 ==========
echo ""
echo -e "${CYAN}── 委托 ailabbot 生成配置 ──${NC}"

if [ -x "$AILABBOT_INIT" ]; then
    exec bash "$AILABBOT_INIT" "$@"
else
    bad "❌ ailabbot/scripts/init.sh 不存在"
    exit 1
fi

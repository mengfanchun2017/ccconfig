#!/bin/bash
# install-inotify.sh — 安装 inotify-tools（apt 优先 → 免 sudo deb 提取）
#
# inotifywait 是 monitor.sh 的核心依赖。WSL 频繁重启会让 apt 缓存丢失，
# 故 apt 失败时从 archive.ubuntu.com 直接拉 .deb 解包到 ~/.local/bin/，
# 整个流程无需 sudo（除 apt 路径）。
#
# 用法:
#   bash install-inotify.sh         # 检测 + 安装，返回 0=已装/装好 1=失败
#
# 依赖外部: curl, dpkg-deb, mkdir, cp, chmod（系统自带）
#
# 兼容 source 调用:
#   source install-inotify.sh && install_inotify

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh" 2>/dev/null || {
    GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
    info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
    warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
    error()   { echo -e "${RED}[ERROR]${NC} $1"; }
    success() { echo -e "${GREEN}[OK]${NC} $1"; }
}

install_inotify() {
    if command -v inotifywait &>/dev/null; then
        success "inotifywait 已存在: $(command -v inotifywait)"
        return 0
    fi

    local installed=false

    # 方式 1：apt（有 sudo 且非 NOSUDO 模式）
    if [[ -z "${BOOTSTRAP_NOSUDO:-}" ]] && command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        info "apt 安装 inotify-tools..."
        if sudo apt-get install -y inotify-tools 2>/dev/null; then
            installed=true
        fi
    fi

    # 方式 2：免 sudo deb 提取 → ~/.local/bin + ~/.local/lib
    if ! $installed; then
        info "免 sudo deb 提取 inotify-tools..."
        local arch
        arch=$(uname -m 2>/dev/null || echo "x86_64")
        [[ "$arch" == "x86_64" ]] && arch="amd64"
        [[ "$arch" == "aarch64" ]] && arch="arm64"

        local tmp_dir="/tmp/inotify-install-$$"
        mkdir -p "$tmp_dir"

        (
            cd "$tmp_dir" || exit 1
            local base="http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools"
            curl -sL "$base/inotify-tools_3.22.6.0-4_${arch}.deb" -o pkg.deb
            curl -sL "$base/libinotifytools0_3.22.6.0-4_${arch}.deb" -o lib.deb
            dpkg-deb -x pkg.deb . 2>/dev/null
            dpkg-deb -x lib.deb . 2>/dev/null

            mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
            cp usr/bin/inotify* "$HOME/.local/bin/" 2>/dev/null || true
            chmod +x "$HOME/.local/bin/inotify"* 2>/dev/null || true
            local libdir
            libdir=$(find usr/lib -name "libinotifytools.so.0" 2>/dev/null | head -1)
            [[ -n "$libdir" ]] && cp "$libdir" "$HOME/.local/lib/"
        ) || warn "inotify-tools 解包失败"

        rm -rf "$tmp_dir"

        # PATH 含 ~/.local/bin 即可识别
        export PATH="$HOME/.local/bin:$PATH"
        if command -v inotifywait &>/dev/null; then
            installed=true
        fi
    fi

    if $installed; then
        success "inotify-tools 安装成功"
        return 0
    fi

    error "inotify-tools 安装失败 — 手动: sudo apt install inotify-tools"
    return 1
}

# CLI 直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_inotify
fi
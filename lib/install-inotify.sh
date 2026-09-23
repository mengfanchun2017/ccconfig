#!/bin/bash
# install-inotify.sh — 安装 inotify-tools（apt 优先 → 免 sudo deb 提取）
#
# inotifywait 是 monitor.sh 的核心依赖。WSL 频繁重启会让 apt 缓存丢失，
# 故 apt 失败时从 apt 池直接拉 .deb 解包到 ~/.local/，整个流程无需 sudo（除 apt 路径）。
#
# 为什么要 wrapper：免 sudo 装的二进制链接 libinotifytools.so.0，库落在
# ~/.local/lib（非 loader 默认路径），裸跑必然 "error while loading shared
# libraries"。wrapper 自带 LD_LIBRARY_PATH，调用方（monitor/systemd/手动）
# 都不用再配环境变量。
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
source "$SCRIPT_DIR/colors.sh"

# inotifywait 是否"真能跑"。command -v 只看得见 PATH 上的文件，
# 库缺失时二进制在、一执行就 "cannot open shared object file"。
inotify_works() {
    command -v inotifywait &>/dev/null || return 1
    local probe
    probe=$(inotifywait --help 2>&1 || true)
    [[ "$probe" != *"error while loading shared libraries"* &&
       "$probe" != *"cannot open shared object file"* ]]
}

# 写 wrapper 到 ~/.local/bin，真实二进制留 ~/.local/libexec
_write_wrapper() {
    local libexec="$HOME/.local/libexec"
    [ -x "$libexec/inotifywait" ] || return 1
    [ -f "$HOME/.local/lib/libinotifytools.so.0" ] || return 1
    mkdir -p "$HOME/.local/bin"
    local b
    for b in inotifywait inotifywatch; do
        [ -x "$libexec/$b" ] || continue
        cat > "$HOME/.local/bin/$b" <<WRAPPER
#!/bin/sh
# ccconfig 生成：自带 LD_LIBRARY_PATH，指向 ~/.local/lib 的 libinotifytools.so.0
export LD_LIBRARY_PATH="\$HOME/.local/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$libexec/$b" "\$@"
WRAPPER
        chmod +x "$HOME/.local/bin/$b"
    done
    return 0
}

install_inotify() {
    if inotify_works; then
        success "inotifywait 可用: $(command -v inotifywait)"
        return 0
    fi
    # 存在 ≠ 可用：库丢了要当"未安装"处理，否则修复流程直接空过
    command -v inotifywait &>/dev/null && \
        warn "inotifywait 存在但无法运行（多为 libinotifytools.so.0 缺失）→ 尝试修复"

    local installed=false

    # 方式 1：apt（有 sudo 且非 NOSUDO 模式）
    # --reinstall 修"包装了但库丢了"的坏状态；失败再退普通 install
    if [[ -z "${BOOTSTRAP_NOSUDO:-}" ]] && command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
        info "apt 安装/修复 inotify-tools..."
        if sudo apt-get install -y --reinstall inotify-tools libinotifytools0 2>/dev/null \
           || sudo apt-get install -y inotify-tools libinotifytools0 2>/dev/null; then
            inotify_works && installed=true
        fi
    fi

    # 方式 2：免 sudo 提取 → 真实二进制 ~/.local/libexec + 库 ~/.local/lib + wrapper ~/.local/bin
    if ! $installed; then
        info "免 sudo 提取 inotify-tools..."
        local arch
        arch=$(uname -m 2>/dev/null || echo "x86_64")
        [[ "$arch" == "x86_64" ]] && arch="amd64"
        [[ "$arch" == "aarch64" ]] && arch="arm64"

        local tmp_dir="/tmp/inotify-install-$$"
        mkdir -p "$tmp_dir"

        (
            set -e
            cd "$tmp_dir" || exit 1
            # 优先 apt-get download：版本与本机发行版一致，且不需要 sudo
            apt-get download inotify-tools libinotifytools0 >/dev/null 2>&1 || true
            apt-get download inotify-tools >/dev/null 2>&1 || true
            for d in ./*.deb; do
                [ -f "$d" ] || continue
                dpkg-deb -x "$d" . 2>/dev/null || true
            done

            # 二进制或库缺任一 → 回退到 archive pool 的固定版本
            if [ ! -x usr/bin/inotifywait ] \
               || ! find usr/lib -name 'libinotifytools.so.0' 2>/dev/null | grep -q .; then
                local base="http://archive.ubuntu.com/ubuntu/pool/universe/i/inotify-tools"
                curl -fsSL "$base/inotify-tools_3.22.6.0-4_${arch}.deb" -o pkg.deb 2>/dev/null || true
                curl -fsSL "$base/libinotifytools0_3.22.6.0-4_${arch}.deb" -o lib.deb 2>/dev/null || true
                for d in pkg.deb lib.deb; do
                    [ -f "$d" ] || continue
                    dpkg-deb -x "$d" . 2>/dev/null || true
                done
            fi

            mkdir -p "$HOME/.local/libexec" "$HOME/.local/lib"
            cp usr/bin/inotify* "$HOME/.local/libexec/" 2>/dev/null || true
            chmod +x "$HOME/.local/libexec/inotify"* 2>/dev/null || true
            local libdir
            libdir=$(find usr/lib -name "libinotifytools.so.0" 2>/dev/null | head -1)
            [ -n "$libdir" ] && cp "$libdir" "$HOME/.local/lib/" || true
        ) || warn "inotify-tools 解包失败"

        rm -rf "$tmp_dir"

        _write_wrapper || warn "wrapper 生成失败（缺 libexec 二进制或 .so）"
        export PATH="$HOME/.local/bin:$PATH"
        inotify_works && installed=true
    fi

    if $installed; then
        success "inotify-tools 安装成功（$(command -v inotifywait)）"
        return 0
    fi

    error "inotify-tools 安装失败 — 手动: sudo apt install --reinstall inotify-tools libinotifytools0"
    return 1
}

# CLI 直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_inotify
fi

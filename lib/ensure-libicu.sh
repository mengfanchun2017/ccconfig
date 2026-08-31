#!/bin/bash
# ensure-libicu.sh — 确保系统 libicu 可用（.NET 单文件应用运行时必需）
#
# officecli / fpptx / fdocx / fxlsx 都是 .NET 单文件二进制，缺 libicu 启动即
# FailFast: "Couldn't find a valid ICU package"。Ubuntu 26.04 包名 libicu78，
# 24.04 是 libicu74，随发行版变 → 用 apt-cache search 自适应。
#
# 调用方：
#   - lib/init-ubuntu.sh main() — 首次初始化装好，upgrade 时 dpkg 命中 skip
#   - option-officecli/init.sh — install/update/status 前置
#
# 用法:
#   bash ensure-libicu.sh          # 检测 + 安装
#   source ensure-libicu.sh && ensure_libicu
#
# 依赖外部: ldconfig, apt-cache, sudo, apt-get
# 兼容 source 调用（不 exit 主进程）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# source 调用时 colors.sh 可能已加载，CLI 调用时需自行 source
if ! command -v info &>/dev/null; then
    source "$SCRIPT_DIR/colors.sh"
fi

# 探测当前发行版对应的 libicu 包名
_detect_libicu_pkg() {
    # 优先 apt-cache search（最准，返回仓库里实际可用包）
    local found
    found=$(apt-cache search --names-only '^libicu[0-9]+$' 2>/dev/null | awk '{print $1}' | sort -V | tail -1)
    [ -n "$found" ] && { echo "$found"; return 0; }

    # fallback：按 os-release 版本号映射
    local ver
    ver=$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null || echo "")
    case "$ver" in
        26.*) echo "libicu78" ;;
        24.*) echo "libicu74" ;;
        22.*) echo "libicu70" ;;
        20.*) echo "libicu66" ;;
        *)    echo "libicu74" ;;  # 默认保守值
    esac
}

ensure_libicu() {
    # 已装 → ldconfig 能查到 libicuuc.so 即满足
    if ldconfig -p 2>/dev/null | grep -q "libicuuc\.so"; then
        return 0
    fi

    local pkg
    pkg=$(_detect_libicu_pkg)
    warn "缺少 libicu（.NET 运行时必需，officecli/fpptx/fdocx/fxlsx 无法启动）"
    info "目标包: $pkg"

    if [[ -n "${BOOTSTRAP_NOSUDO:-}" ]] || ! command -v sudo &>/dev/null; then
        warn "跳过 sudo（NOSUDO 或无 sudo），手动: sudo apt-get install -y $pkg"
        return 1
    fi

    if sudo apt-get install -y "$pkg" 2>&1 | tail -3; then
        if ldconfig -p 2>/dev/null | grep -q "libicuuc\.so"; then
            ok "libicu 已装 ($pkg)"
            return 0
        else
            warn "$pkg 安装后 libicuuc.so 仍未就绪，可能需 ldconfig 或重启"
            return 1
        fi
    else
        warn "$pkg 安装失败，手动: sudo apt-get install -y $pkg"
        return 1
    fi
}

# CLI 直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ensure_libicu
fi

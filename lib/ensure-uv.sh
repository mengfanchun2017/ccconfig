#!/bin/bash
# ensure-uv.sh — 确保 uv / uvx 可用（Python 工具隔离运行器）
#
# uv 是 astral.sh 的 Rust 单文件二进制（apt 无此包，~/.local/bin 用户级安装）。
# uvx = `uv tool run`，在临时隔离环境跑 Python CLI 工具（如 mineru-open-mcp），
# 不污染系统 Python。被这些组件依赖，缺了直接挂：
#   - option-mineru    (uvx --from mineru-open-mcp ... 跑 MCP)
#   - option-evalscope (uv venv 建独立 py3.11 环境)
#
# 调用方：
#   - lib/init-ubuntu.sh main() — 首次初始化装好（upgrade 时 command -v 命中 skip）
#   - lib/update.sh update_uv   — 升级（uv self update）
#   - option-mineru/init.sh, option-evalscope/init.sh — install 前置
#
# 用法:
#   bash ensure-uv.sh               # 检测 + 安装
#   source ensure-uv.sh && ensure_uv
#
# 无 sudo（用户级安装）。兼容 source 调用（不 exit 主进程）。

set -euo pipefail
# 用唯一名，别用 SCRIPT_DIR：source 时变量共享作用域，会覆盖调用方的 SCRIPT_DIR
_ENSURE_UV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 检查函数而非命令：裸 PATH 上 /usr/bin/info（texinfo）会让 command -v 误判已加载
if ! declare -F info >/dev/null 2>&1; then
    source "$_ENSURE_UV_DIR/colors.sh"
fi
# configure_uv_index 用 run/atomic_write；调用方（如 option-evalscope）未必 source 过 dry-run
if ! declare -F run >/dev/null 2>&1; then
    source "$_ENSURE_UV_DIR/dry-run.sh"
fi

UV_INSTALL_DIR="${UV_INSTALL_DIR:-$HOME/.local/bin}"
UV_CONF_DIR="${UV_CONF_DIR:-$HOME/.config/uv}"
UV_INDEX_MIRROR="${UV_INDEX_MIRROR:-https://pypi.tuna.tsinghua.edu.cn/simple}"

_uv_bin() { echo "${UV_INSTALL_DIR}/uv"; }

# 直连 PyPI 下载是否足够快（决定要不要配镜像）
# 背景：pypi.org 索引（/simple/）在国内通常可达，但 files.pythonhosted.org（wheel
# 实体）会掉到几十 KB/s。uvx 拉起 MCP（mineru 依赖 ~110MB）> Claude Code 的 30s
# 连接超时 → MCP 永远显示 ✘。索引可达 ≠ 能装包，必须实测下载速度。
_uv_direct_fast() {
    command -v curl &>/dev/null || return 1
    local spd
    spd=$(timeout 12 curl -sS -o /dev/null -w '%{speed_download}' -r 0-1000000 \
        "https://files.pythonhosted.org/packages/9e/c9/b2622292ea83fbb4ec318f5b9ab867d0a28ab43c5717bb85b0a5f6b3b0a4/networkx-3.6.1-py3-none-any.whl" \
        2>/dev/null) || return 1
    # 数字比较走 awk，避免 integer-only 的 bash [[ -lt ]] 踩浮点
    awk -v s="${spd:-0}" 'BEGIN{exit !(s>=300000)}'
}

# 配 uv 全局镜像（幂等；用户已自配 index 则不动）
configure_uv_index() {
    local conf="$UV_CONF_DIR/uv.toml"
    if [ -f "$conf" ] && grep -q '^\[\[index\]\]' "$conf" 2>/dev/null; then
        return 0
    fi
    if _uv_direct_fast; then
        return 0
    fi
    info "PyPI 直连下载过慢 → 配镜像: $UV_INDEX_MIRROR"
    if _dry_run_enabled; then
        would "write" "$conf"
        return 0
    fi
    mkdir -p -- "$UV_CONF_DIR"
    atomic_write "$conf" <<EOF
# uv 全局配置 — PyPI 走国内镜像（由 ccconfig/lib/ensure-uv.sh 写入）
# 直连 files.pythonhosted.org 会掉速，导致 uvx 拉 MCP 依赖超过 Claude Code 的
# 30s 连接超时。实测镜像 ~3MB/s。改回官方源：删本文件的 [[index]] 段。
[[index]]
url = "${UV_INDEX_MIRROR}"
default = true
EOF
    ok "已写 $conf"
}

ensure_uv() {
    # PATH 里没有但装在默认位置 → 补进当前 PATH（本进程）
    if ! command -v uv &>/dev/null && [ -x "$(_uv_bin)" ]; then
        export PATH="$UV_INSTALL_DIR:$PATH"
    fi

    if command -v uv &>/dev/null; then
        # uvx 应随 uv 一起存在；个别情况缺了用 uv tool run 兜底 alias 提示
        if command -v uvx &>/dev/null; then
            configure_uv_index
            return 0
        fi
        warn "uv 在但 uvx 缺失（异常）；重装: curl -LsSf https://astral.sh/uv/install.sh | sh"
    fi

    info "安装 uv（astral 官方安装器 → $UV_INSTALL_DIR，用户级免 sudo）"
    if ! command -v curl &>/dev/null; then
        err "缺 curl，无法下载 uv。手动: apt install curl"
        return 1
    fi

    # 官方安装器：默认落 ~/.local/bin，uv/uvx 一并带上
    if curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$UV_INSTALL_DIR" sh 2>&1 | tail -3; then
        export PATH="$UV_INSTALL_DIR:$PATH"
        hash -r 2>/dev/null || true
        if command -v uv &>/dev/null; then
            ok "uv 已装: $(uv --version)"
            configure_uv_index
            return 0
        else
            warn "uv 安装后仍不在 PATH，开新终端或 source ~/.bashrc"
            return 1
        fi
    else
        warn "uv 安装失败。手动: curl -LsSf https://astral.sh/uv/install.sh | sh"
        return 1
    fi
}

# CLI 直接调用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ensure_uv
fi

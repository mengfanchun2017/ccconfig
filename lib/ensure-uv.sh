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

UV_INSTALL_DIR="${UV_INSTALL_DIR:-$HOME/.local/bin}"

_uv_bin() { echo "${UV_INSTALL_DIR}/uv"; }

ensure_uv() {
    # PATH 里没有但装在默认位置 → 补进当前 PATH（本进程）
    if ! command -v uv &>/dev/null && [ -x "$(_uv_bin)" ]; then
        export PATH="$UV_INSTALL_DIR:$PATH"
    fi

    if command -v uv &>/dev/null; then
        # uvx 应随 uv 一起存在；个别情况缺了用 uv tool run 兜底 alias 提示
        if command -v uvx &>/dev/null; then
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

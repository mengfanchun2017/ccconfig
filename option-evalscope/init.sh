#!/bin/bash
# ccconfig/option-evalscope/init.sh — evalscope 可选组件
#   用 uv 建独立 py3.11 venv 装 evalscope（不污染系统 Python 3.14）
#
# 用法：
#   bash option-evalscope/init.sh                # 交互式
#   bash option-evalscope/init.sh --install      # 安装/重装
#   bash option-evalscope/init.sh --status       # 状态检查
#   bash option-evalscope/init.sh --remove       # 移除 venv

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_ROOT/lib/colors.sh"
source "$CCCONFIG_ROOT/lib/interact.sh"

VENV_DIR="$SCRIPT_DIR/.venv"
EVALSCOPE_BIN="$VENV_DIR/bin/evalscope"
PY_VER=3.11

_is_installed() {
    [[ -x "$EVALSCOPE_BIN" ]] && "$EVALSCOPE_BIN" --version >/dev/null 2>&1
}

do_install() {
    echo -e "${CYAN}── 安装 evalscope（独立 venv py$PY_VER）──${NC}"
    command -v uv >/dev/null 2>&1 || { err "未找到 uv（需要 uv 管理 venv）: 安装见 https://astral.sh/uv"; return 1; }

    if [[ ! -d "$VENV_DIR" ]]; then
        info "创建 venv (python $PY_VER)..."
        uv venv --python "$PY_VER" "$VENV_DIR"
    fi

    info "安装 evalscope（首次会下载较多依赖，需几分钟）..."
    if ! uv pip install --python "$VENV_DIR/bin/python" evalscope; then
        err "evalscope 安装失败"; return 1
    fi

    rm -rf "$VENV_DIR/__pycache__" 2>/dev/null || true
    ok "evalscope 安装完成（py$PY_VER）：$( "$EVALSCOPE_BIN" --version 2>&1 )"
}

do_remove() {
    if [[ -d "$VENV_DIR" ]]; then
        if confirm "删除 $VENV_DIR ?" n; then
            rm -rf "$VENV_DIR"
            ok "已移除 venv"
        else
            info "取消"
        fi
    else
        info "无 venv 可移除"
    fi
}

do_status() {
    if _is_installed; then
        local ver
        ver="$("$EVALSCOPE_BIN" --version 2>&1)"
        echo "OK evalscope $ver (venv py$PY_VER)"
    else
        echo "MISSING evalscope 未安装（bash option-evalscope/init.sh --install）"
    fi
}

show_menu() {
    echo ""
    echo -e "${CYAN}── evalscope 可选组件 ──${NC}"
    echo ""
    do_status
    echo ""
    echo "说明：按 llm.json preset 跑性能压测 / 精度评估"
    echo "  run-perf.sh --preset <name>   性能（并发/TPS/延迟）"
    echo "  run-eval.sh --preset <name>   精度（MMLU/GSM8K）"
    echo "  run-all.sh  --preset <name>   一键 性能+精度"
    echo ""
    local c; c=$(menu_select "evalscope 管理" \
        "安装/重装" "移除 venv" "返回")
    [[ -z "$c" ]] && return
    case "$c" in
        1) do_install ;;
        2) do_remove ;;
        3) return ;;
    esac
    echo ""; read -p "按回车返回..." dummy < /dev/tty || true
    show_menu
}

case "${1:-menu}" in
    --install) do_install ;;
    --remove)  do_remove ;;
    --status)  do_status ;;
    menu|"")   show_menu ;;
    *) echo "用法: $0 [--install|--remove|--status|menu]" ;;
esac
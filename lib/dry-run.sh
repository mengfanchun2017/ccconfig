#!/bin/bash
# ==============================================
# dry-run.sh — 统一 dry-run 助手
#
# 功能：
#   - CCC_DRY_RUN=1 或 --dry-run 自动启用模拟
#   - run() 包装任意命令：模拟时只打印，真跑时执行
#   - would(): 打印 "would: <verb> <target>"
#   - dry_run_banner() 开头提示
#   - dry_run_footer() 结尾提示
#
# 用法：
#   source "$LIB_DIR/dry-run.sh"
#   dry_run_banner
#   run npm install -g pkg1   # 真跑/模拟取决于开关
#   run cp a b
#   would "write" "/etc/foo"  # 只打印，不执行
#   dry_run_footer
#
# 测试：
#   CCC_DRY_RUN=1 bash your-script.sh     # 模拟模式
#   bash your-script.sh --dry-run          # 模拟模式
#   bash your-script.sh                    # 真跑
# ==============================================

# 检测 dry-run 状态（CCC_DRY_RUN=1 或 --dry-run 命令行参数）
_dry_run_enabled() {
    [[ "${CCC_DRY_RUN:-0}" == "1" ]] && return 0
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && return 0
    done
    return 1
}

# 把 --dry-run 从参数中剥离，避免传给底层命令
# 用法：args=("${_dry_run_strip[@]}" ...)
_dry_run_strip() {
    local out=()
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && continue
        out+=("$arg")
    done
    printf '%s\n' "${out[@]}"
}

# 打印 "would: <verb> <target>"
# 用法：would "install" "pkg1 pkg2"
would() {
    local verb="$1"
    shift
    printf 'would: %s %s\n' "$verb" "$*"
}

# 通用 run 包装
# 模拟时打印 would: 行；真跑时执行
# 接收 --dry-run 参数自动剥离
run() {
    if _dry_run_enabled "$@"; then
        local stripped
        stripped=$(_dry_run_strip "$@")
        local verb="${stripped%% *}"
        printf 'would: %s\n' "$stripped"
    else
        command "$@"
    fi
}

dry_run_banner() {
    if _dry_run_enabled; then
        echo "=========================================="
        echo "  DRY-RUN MODE (CCC_DRY_RUN=${CCC_DRY_RUN:-0})"
        echo "  No changes will be applied."
        echo "=========================================="
        echo ""
    fi
}

dry_run_footer() {
    if _dry_run_enabled; then
        echo ""
        echo "=========================================="
        echo "  === dry-run: no changes applied ==="
        echo "=========================================="
    fi
}

# 真跑/模拟分发的便捷函数
# 模拟时调用 dry_fn，真跑时调用 real_fn
# 用法：dispatch "real_install" "dry_install"
dispatch() {
    local real_fn="$1" dry_fn="${2:-_dry_default}"
    if _dry_run_enabled; then
        "$dry_fn" "${@:3}"
    else
        "$real_fn" "${@:3}"
    fi
}

_dry_default() {
    printf 'would: %s\n' "$*"
}

# 自检：source 即可
# 不会自动启用，仅暴露函数

#!/bin/bash
# shellcheck disable=SC2178,SC2128  # false positive: tmp in atomic_write is never an array
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
# 只认全局 CCC_DRY_RUN —— 不要把被包装命令自己的参数当开关：run rm -rf foo 里
# 的 "$@" 是 rm 的参数，从中找 --dry-run 永远找不到，而 run 的第一项常是
# rm/npm/apt 这类动词，本就不该被当作 dry-run 标志。
run() {
    if _dry_run_enabled; then
        printf 'would: %s\n' "$*"
    else
        command "$@"
    fi
}

# 把脚本自身的 --dry-run 命令行参数转成全局开关。
# 不靠各脚本记得调用：bash 的 source 不带参数，被 source 的文件直接继承调用者的 "$@"，
# 所以这里自动跑一次即覆盖全部 30 个 source 了 dry-run.sh 的入口脚本。
# 缺了这一步，「bash lib/x.sh --dry-run」把 --dry-run 当普通位置参数传下去，
# 真操作照跑（曾因此让 init-skill 的 sudo apt-get / npm -g 在"预览"下真装）。
dry_run_parse_argv() {
    local arg
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && export CCC_DRY_RUN=1
    done
    return 0
}

# bash/zsh source 时调用者参数不会进 $@，但调用者的 "$@" 仍可通过 ${BASH_ARGV}
# 或直接读进程参数拿到 —— 用 /proc 读自身，避开 shell 差异。
dry_run_parse_argv "$@"
if [ -r /proc/$$/cmdline ]; then
    _dry_args=$(tr '\0' '\n' < /proc/$$/cmdline 2>/dev/null | grep -x -- '--dry-run' || true)
    [ -n "$_dry_args" ] && export CCC_DRY_RUN=1
    unset _dry_args
fi

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

# ========== 原子写入 ==========
# 临时文件 → mv 原子重命名，防止写一半断掉
atomic_write() {
    # false positive: shellcheck 0.10.0 thinks tmp is an array
    local out="$1"
    local tmp; tmp=$(mktemp "${out}.XXXXXX") || return 1
    cat > "$tmp"
    chmod 0644 -- "$tmp" 2>/dev/null || true
    mv -f -- "$tmp" "$out"
}

# 自检：source 即可
# 不会自动启用，仅暴露函数

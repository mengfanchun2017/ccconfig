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

# ========== Idempotent Guards ==========
# 幂等操作封装，check-before-act 模式
# 适用：安装脚本 / 初始化脚本 / 配置脚本
# 规则：安全地重复执行，不会产生副作用

# 幂等创建目录（等价 mkdir -p，封装为 guard 语义）
guard_mkdir() {
    local dir="$1"
    [ -d "$dir" ] && return 0
    run mkdir -p -- "$dir"
}

# 幂等创建符号链接
guard_symlink() {
    local target="$1" link="$2"
    if [ -L "$link" ]; then
        local cur; cur=$(readlink "$link") || true
        [ "$cur" = "$target" ] && return 0
        run rm -f -- "$link"
    elif [ -e "$link" ]; then
        run rm -f -- "$link"
    fi
    run ln -s -- "$target" "$link"
}

# 幂等追加行到文件（行不存在才追加）
guard_append_line() {
    local file="$1" line="$2"
    [ -f "$file" ] && grep -qxF -- "$line" "$file" 2>/dev/null && return 0
    run printf '%s\n' "$line" >> "$file"
}

# 幂等写入文件（内容不同时才覆盖，原子写入）
guard_write_file() {
    local file="$1" content="$2"
    if [ -f "$file" ] && [ "$(cat "$file" 2>/dev/null)" = "$content" ]; then
        return 0
    fi
    atomic_write "$file" <<< "$content"
}

# 幂等检查命令存在
guard_command_exists() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
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

# safe-exit.sh — 统一 trap 清理函数
#
# 用法: source 后入口脚本注册 trap
#   source "$LIB_DIR/safe-exit.sh"
#   trap safe_exit INT TERM
#
# safe_exit: 临时文件/目录清理后退出
# _register_temp: 注册清理目标（可多次调）

SAFE_EXIT_TEMPS=()

_register_temp() {
    SAFE_EXIT_TEMPS+=("$1")
}

safe_exit() {
    local rc=${1:-$?}
    for t in "${SAFE_EXIT_TEMPS[@]}"; do
        [ -e "$t" ] && rm -rf -- "$t" 2>/dev/null
    done
    exit "$rc"
}

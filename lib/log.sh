# ==============================================
# log.sh — 统一日志助手
#
# 功能：
#   - log_info / log_warn / log_error / log_debug
#   - CCC_LOG=file 写日志到文件（同时 stdout）
#   - CCC_VERBOSE=1 显示 debug
#   - log_section "标题" 自动加横线
#   - 与 colors.sh 协同（被 source 时自动获取颜色）
#
# 用法：
#   source "$LIB_DIR/log.sh"
#   log_info "starting"     # 写日志+stdout
#   log_warn "deprecated"
#   log_section "Step 1"    # 加横线分隔
# ==============================================

# 颜色（colors.sh 可能没 source，这里兜底定义）
: "${RED:=$'\033[0;31m'}"
: "${GREEN:=$'\033[0;32m'}"
: "${YELLOW:=$'\033[1;33m'}"
: "${CYAN:=$'\033[0;36m'}"
: "${GRAY:=$'\033[0;90m'}"
: "${NC:=$'\033[0m'}"

_log_target() {
    if [[ -n "${CCC_LOG:-}" ]]; then
        printf '%s\n' "$1" >> "$CCC_LOG"
    fi
}

_log_ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    local msg="$*"
    _log_target "$(_log_ts) INFO  $msg"
    echo -e "${GREEN}[INFO]${NC} $msg"
}

log_warn() {
    local msg="$*"
    _log_target "$(_log_ts) WARN  $msg"
    echo -e "${YELLOW}[WARN]${NC} $msg" >&2
}

log_error() {
    local msg="$*"
    _log_target "$(_log_ts) ERROR $msg"
    echo -e "${RED}[ERROR]${NC} $msg" >&2
}

log_debug() {
    [[ "${CCC_VERBOSE:-0}" == "1" ]] || return 0
    local msg="$*"
    _log_target "$(_log_ts) DEBUG $msg"
    echo -e "${GRAY}[DEBUG]${NC} $msg"
}

log_section() {
    local title="$*"
    echo -e "\n${CYAN}=== $title ===${NC}"
    _log_target "=== $title ==="
}

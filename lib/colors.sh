# shellcheck shell=bash
# shellcheck disable=SC2034  # 颜色变量被 source 方消费
# 颜色变量 + 日志函数 — 所有脚本统一 source
# 使用: source "$SCRIPT_DIR/colors.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
LIGHT_BLUE='\033[96m'    # 状态/当前标记（亮青，深色终端可见）
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
BOLD_BLUE='\033[1;34m'   # 字母快捷专用（菜单 A/B/C 高亮）
BOLD_GREEN='\033[1;32m'  # 选项字母绿色高亮
BOLD_GRAY='\033[1;90m'   # 分类标题 --xxx--
GRAY='\033[0;90m'
DIM='\033[2m'
NC='\033[0m'

# non-tty（管道/命令替换捕获）时清空色变量：输出纯文本，避免 escape 脏进日志/文件
# 终端 tty 下色变量保留原样，无行为变化
# CCCONFIG_FORCE_COLOR=1 强制保留颜色 —— 供测试断言真实色码（bats `run` 会捕获 stdout），
# 以及用户想把带色输出重定向/管道给阅读器时使用。
if [ ! -t 1 ] && [ -z "${CCCONFIG_FORCE_COLOR:-}" ]; then
    RED='' GREEN='' LIGHT_BLUE='' YELLOW='' CYAN='' BLUE='' BOLD=''
    BOLD_BLUE='' BOLD_GREEN='' BOLD_GRAY='' GRAY='' DIM='' NC=''
fi

ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
err()   { echo -e "  ${RED}❌ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
info()  { echo -e "  ${GRAY}$1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
banner() { echo -e "${BOLD}━━━ $1 ━━━${NC}"; }
# 旧名别名（兼容）
good()  { ok "$@"; }
bad()   { err "$@"; }
success() { ok "$@"; }
error()   { err "$@"; }

# OSC 8 超链接：终端里 URL 被折行时，鼠标框选只能复制到一行 → 链接传一半。
# 包成 OSC 8 后点击即整条跳转，不受视觉折行影响。
#   参数: <url> [显示文本]   不传文本则显示 url 本身
# 非 tty 或 CCCONFIG_NO_HYPERLINK=1 时退化为纯文本（日志/管道里不留 escape）。
link() {
    local url="$1" text="${2:-$1}"
    if [ -t 1 ] && [ -z "${CCCONFIG_NO_HYPERLINK:-}" ]; then
        printf '\033]8;;%s\033\\%s\033]8;;\033\\\n' "$url" "$text"
    else
        printf '%s\n' "$url"
    fi
}

# 自备 fallback：当被非 tty 环境 source 时确保函数可用
# caller 不再需要写 2>/dev/null || { RED='...' ... }
if ! type ok &>/dev/null; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'
    BOLD_BLUE='\033[1;34m'; BOLD_GREEN='\033[1;32m'; LIGHT_BLUE='\033[96m'
    BOLD_GRAY='\033[1;90m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    ok()    { echo -e "  ${GREEN}$1${NC}"; }
    err()   { echo -e "  ${RED}$1${NC}"; }
    warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
    info()  { echo -e "  ${GRAY}$1${NC}"; }
    section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
    banner() { echo -e "${BOLD}━━━ $1 ━━━${NC}"; }
    link() {
        local url="$1" text="${2:-$1}"
        if [ -t 1 ] && [ -z "${CCCONFIG_NO_HYPERLINK:-}" ]; then
            printf '\033]8;;%s\033\\%s\033]8;;\033\\\n' "$url" "$text"
        else
            printf '%s\n' "$url"
        fi
    }
fi

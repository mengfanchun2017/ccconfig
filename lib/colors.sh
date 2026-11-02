# shellcheck shell=bash
# shellcheck disable=SC2034  # 颜色变量被 source 方消费
# 颜色变量 + 日志函数 — 所有脚本统一 source
# 使用: source "$SCRIPT_DIR/colors.sh"

# ── 为什么用 256 色索引而不是 16 色 ──
# 16 色（0;31 / 0;32 / 1;33 / 0;90 …）的实际颜色由**终端主题调色板**决定，
# 换主题、切亮/暗模式、进 tmux 之后同一个色号可能渲染成白色或近乎白 ——
# 这就是「有时候有颜色、有时候成功失败警告全是白的」的主因之一。
# 256 色索引（38;5;N）是固定色板，不受主题改写。色号统一选中等亮度，
# 避免 1;33（亮黄）、96（亮青）、196（纯红）那种刺眼档。
#
# 探测：CCCONFIG_COLOR_DEPTH 显式覆盖 → tput colors → 回落 16 色。
_ccconfig_color_depth() {
    if [ -n "${CCCONFIG_COLOR_DEPTH:-}" ]; then printf '%s' "$CCCONFIG_COLOR_DEPTH"; return; fi
    local n
    n=$(tput colors 2>/dev/null || printf 0)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -ge 256 ] 2>/dev/null; then printf 256; else printf 16; fi
}

if [ "$(_ccconfig_color_depth)" = "256" ]; then
    RED='\033[38;5;167m'        # 柔红 #d75f5f — 失败/中止
    GREEN='\033[38;5;71m'       # 柔绿 #5faf5f — 成功
    YELLOW='\033[38;5;179m'     # 琥珀 #d7af5f — 警告/重试中
    CYAN='\033[38;5;73m'        # 柔青 #5fafaf — 活动/进度
    BLUE='\033[38;5;67m'        # 深柔蓝
    LIGHT_BLUE='\033[38;5;110m' # 柔蓝 #87afd7 — 状态/区块标题
    GRAY='\033[38;5;245m'       # 中灰 — 次要信息
    TS_DIM='\033[38;5;242m'     # 暗灰 — 日志时间戳（只做锚点，不抢注意力）
    NOISE='\033[38;5;239m'      # 极暗灰 — 纯噪声行（already up to date）
    BOLD='\033[1m'
    BOLD_BLUE='\033[1;38;5;110m'
    BOLD_GREEN='\033[1;38;5;71m'
    BOLD_GRAY='\033[1;38;5;250m'
    DIM='\033[2m'
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'         # 非 bold：1;33 是最刺眼的档
    CYAN='\033[0;36m'
    BLUE='\033[0;34m'
    LIGHT_BLUE='\033[36m'
    GRAY='\033[0;90m'
    TS_DIM='\033[0;90m'
    NOISE='\033[0;90m'
    BOLD='\033[1m'
    BOLD_BLUE='\033[1;34m'
    BOLD_GREEN='\033[1;32m'
    BOLD_GRAY='\033[1;90m'
    DIM='\033[2m'
fi
NC='\033[0m'
unset -f _ccconfig_color_depth

# non-tty（管道/命令替换捕获）时清空色变量：输出纯文本，避免 escape 脏进日志/文件
# 终端 tty 下色变量保留原样，无行为变化
# 强制保留颜色的入口（任一满足即保留）：
#   CCCONFIG_FORCE_COLOR=1  旧入口，保留兼容（测试断言真实色码用）
#   CLICOLOR_FORCE=1        事实标准
#   FORCE_COLOR=1           npm/Node 生态事实标准
# 尊重 NO_COLOR（https://no-color.org）：设了非空值就一律不上色。
if [ -n "${NO_COLOR:-}" ] || { [ ! -t 1 ] && [ -z "${CCCONFIG_FORCE_COLOR:-}" ] \
        && [ -z "${CLICOLOR_FORCE:-}" ] && [ -z "${FORCE_COLOR:-}" ]; }; then
    RED='' GREEN='' LIGHT_BLUE='' YELLOW='' CYAN='' BLUE='' BOLD=''
    BOLD_BLUE='' BOLD_GREEN='' BOLD_GRAY='' GRAY='' DIM='' NC=''
    TS_DIM='' NOISE=''
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
error() { err "$@"; }

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
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'
    BOLD_BLUE='\033[1;34m'; BOLD_GREEN='\033[1;32m'; LIGHT_BLUE='\033[36m'
    BOLD_GRAY='\033[1;90m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    TS_DIM='\033[0;90m'; NOISE='\033[0;90m'
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

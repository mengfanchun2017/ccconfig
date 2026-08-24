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

ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
err()   { echo -e "  ${RED}❌ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
info()  { echo -e "  ${GRAY}$1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
# 旧名别名（兼容）
good()  { ok "$@"; }
bad()   { err "$@"; }
success() { ok "$@"; }
error()   { err "$@"; }

# 自备 fallback：当被非 tty 环境 source 时确保函数可用
# caller 不再需要写 2>/dev/null || { RED='...' ... }
if ! type ok &>/dev/null 2>/dev/null; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'
    BOLD_BLUE='\033[1;34m'; BOLD_GREEN='\033[1;32m'; LIGHT_BLUE='\033[96m'
    BOLD_GRAY='\033[1;90m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    ok()    { echo -e "  ${GREEN}$1${NC}"; }
    err()   { echo -e "  ${RED}$1${NC}"; }
    warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
    info()  { echo -e "  ${GRAY}$1${NC}"; }
    section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
fi

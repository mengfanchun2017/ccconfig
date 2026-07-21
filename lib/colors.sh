# 颜色变量 + 日志函数 — 所有脚本统一 source
# 使用: source "$SCRIPT_DIR/colors.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
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

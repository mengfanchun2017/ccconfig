#!/bin/bash
# maintain.sh — ccconfig 收尾 + 状态入口
#
# 双重角色：
#   1. 首次安装 Step 5：链接修复 → 状态检查 → 服务启动
#   2. 日常运维入口：状态检查、监控管理
#
# 用法：
#   bash maintain.sh                    # 收尾（链接修复 + status + 服务）
#   bash maintain.sh status             # 仅状态检查
#   bash maintain.sh monitor [start|stop|status|tail]
#   bash maintain.sh sync [--pull|--push] [repo]
#   bash maintain.sh update [all|python|<comp>]
#   bash maintain.sh deps               # 依赖检查
#   bash maintain.sh fix                # 自动修复
#
# 暗号：
#   hookstatus → bash maintain.sh status
#   pullff     → bash maintain.sh sync --pull

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; NC='\033[0m'
}

info()    { echo -e "  ${GRAY}$1${NC}"; }
ok()      { echo -e "  ${GREEN}✅ $1${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
err()     { echo -e "  ${RED}❌ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ── Step 5: 收尾 ──
do_finalize() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ccconfig 收尾 — 链接修复 + 状态检查 + 服务启动${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # 1. 修复符号链接
    section "1. 修复符号链接"
    bash "$LIB_DIR/setup-links.sh"

    local ccprivate_setup="${CCPRIVATE_HOME:-$HOME/git/ccprivate}/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        info "运行 ccprivate/setup.sh（私有链接）..."
        bash "$ccprivate_setup" 2>/dev/null && ok "私有链接已修复" || warn "私有链接部分失败"
    fi

    # 2. auto-sync 服务
    section "2. 启动 auto-sync"
    bash "$LIB_DIR/init-autostart.sh" enable 2>/dev/null && ok "auto-sync 已启动" || warn "auto-sync 启动失败（可手动: bash $LIB_DIR/monitor.sh start）"

    # 3. 状态检查（精简版）
    section "3. 状态总览"
    bash "$LIB_DIR/status.sh"

    # 4. 输出汇总
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ccconfig 就绪 🎉${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}日常命令:${NC}"
    echo ""
    echo -e "  ${CYAN}bash maintain.sh status${NC}    # 状态检查"
    echo -e "  ${CYAN}bash maintain.sh monitor${NC}   # 监控日志"
    echo -e "  ${CYAN}bash maintain.sh update all${NC} # 升级系统"
    echo -e "  ${CYAN}bash init-option.sh${NC}        # 装可选组件"
    echo ""
}

# ── 交互菜单 ──
show_menu() {
    echo ""
    echo -e "${CYAN}ccconfig 运维中心${NC}"
    echo ""
    echo "  1) 状态检查       status"
    echo "  2) Monitor 管理   日志，monitor start|stop|status"
    echo "  3) 同步           检查更新 → ff-only → 冲突时交互"
    echo "  4) 升级           update all"
    echo "  5) 依赖检查       deps"
    echo "  6) 自动修复       fix"
    echo "  0) 退出"
    echo ""
    read -p "选择 [0-6]: " c

    case "$c" in
        1) bash "$LIB_DIR/status.sh" ;;
        2) submenu_monitor ;;
        3) bash "$LIB_DIR/sync.sh" ;;
        4) bash "$LIB_DIR/update.sh" all ;;
        5) bash "$LIB_DIR/deps-check.sh" ;;
        6) bash "$LIB_DIR/setup-links.sh"
           if [ -f "$HOME/git/ccprivate/setup.sh" ]; then
               bash "$HOME/git/ccprivate/setup.sh"
           fi
           bash "$LIB_DIR/init-autostart.sh" enable ;;
        0) echo ""; exit 0 ;;
        *) show_menu ;;
    esac

    echo ""
    read -p "按回车返回..." dummy
    show_menu
}

submenu_monitor() {
    echo ""
    echo -e "${CYAN}── Monitor 管理 ──${NC}"
    echo "  1) 启动"
    echo "  2) 停止"
    echo "  3) 看状态"
    echo "  4) 看日志（默认）"
    echo "  0) 返回"
    echo ""
    read -p "选择 [0-4]: " c
    case "$c" in
        1) bash "$LIB_DIR/monitor.sh" start ;;
        2) bash "$LIB_DIR/monitor.sh" stop ;;
        3) bash "$LIB_DIR/monitor.sh" status ;;
        4) bash "$LIB_DIR/monitor.sh" ;;
        0) return ;;
        *) submenu_monitor ;;
    esac
}

# ── 入口 ──
case "${1:-finalize}" in
    finalize|first|init|"")  do_finalize ;;
    status)    bash "$LIB_DIR/status.sh" ;;
    monitor)   bash "$LIB_DIR/monitor.sh" "${2:-}" ;;
    sync)      shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    update)    shift; bash "$LIB_DIR/update.sh" "$@" ;;
    deps)      bash "$LIB_DIR/deps-check.sh" ;;
    fix)       bash "$LIB_DIR/setup-links.sh"
               if [ -f "$HOME/git/ccprivate/setup.sh" ]; then
                   bash "$HOME/git/ccprivate/setup.sh"
               fi
               bash "$LIB_DIR/init-autostart.sh" enable ;;
    menu)      show_menu ;;
    *)  echo "用法: bash maintain.sh [status|monitor|sync|update|deps|fix|menu]"; exit 1 ;;
esac

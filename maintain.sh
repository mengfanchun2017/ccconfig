#!/bin/bash
# maintain.sh — ccconfig 统一运维入口
#
# 用法：
#   bash maintain.sh                    # 交互式菜单
#   bash maintain.sh status             # 状态检查
#   bash maintain.sh monitor start|stop|status|tail  # auto-sync 管理
#   bash maintain.sh sync [--pull|--push] [repo]     # 同步
#   bash maintain.sh update [all|python|<comp>]       # 升级
#   bash maintain.sh deps               # 依赖检查
#   bash maintain.sh fix                # 自动修复
#
# 暗号（CLAUDE.md 中定义）：
#   hookstatus → bash maintain.sh status
#   pullff     → bash maintain.sh sync --pull

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; NC='\033[0m'

show_menu() {
    echo ""
    echo -e "${CYAN}ccconfig 运维中心${NC}"
    echo ""
    echo "  1) 状态检查       status"
    echo "  2) Monitor 管理   monitor → 日志，monitor start|stop|status"
    echo "  3) 同步           sync --pull"
    echo "  4) 升级           update all"
    echo "  5) 依赖检查       deps"
    echo "  6) 自动修复       fix"
    echo "  0) 退出"
    echo ""
    read -p "选择 [0-6]: " c

    case "$c" in
        1) bash "$LIB_DIR/status.sh"
           echo -e "${YELLOW}操作完成，按回车返回...${NC}"; read -r; show_menu ;;
        2) submenu_monitor ;;
        3) bash "$LIB_DIR/sync.sh" --pull
           echo -e "${YELLOW}操作完成，按回车返回...${NC}"; read -r; show_menu ;;
        4) bash "$LIB_DIR/update.sh" all
           echo -e "${YELLOW}操作完成，按回车返回...${NC}"; read -r; show_menu ;;
        5) bash "$LIB_DIR/deps-check.sh"
           echo -e "${YELLOW}操作完成，按回车返回...${NC}"; read -r; show_menu ;;
        6) bash "$LIB_DIR/setup-links.sh"
           bash "$LIB_DIR/init-autostart.sh" enable
           echo -e "${GREEN}修复完成${NC}"
           echo -e "${YELLOW}操作完成，按回车返回...${NC}"; read -r; show_menu ;;
        0) echo ""; exit 0 ;;
        *) show_menu ;;
    esac
}

submenu_monitor() {
    echo ""
    echo -e "${CYAN}── Monitor 管理 ──${NC}"
    echo "  1) 启动            monitor start"
    echo "  2) 停止            monitor stop"
    echo "  3) 看状态          monitor status"
    echo "  4) 看日志（默认）  monitor"
    echo "  0) 返回"
    echo ""
    read -p "选择 [0-4]: " c

    case "$c" in
        1) bash "$LIB_DIR/monitor.sh" start ;;
        2) bash "$LIB_DIR/monitor.sh" stop ;;
        3) bash "$LIB_DIR/monitor.sh" status ;;
        4) bash "$LIB_DIR/monitor.sh" ;;
        0) show_menu; return ;;
        *) submenu_monitor ;;
    esac
    echo -e "${YELLOW}操作完成，按回车返回...${NC}"; read -r; show_menu
}

# ========== 直接命令模式（暗号/脚本调用） ==========
case "${1:-}" in
    status)   bash "$LIB_DIR/status.sh" ;;
    monitor)  bash "$LIB_DIR/monitor.sh" "${2:-}" ;;
    sync)     shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    update)   shift; bash "$LIB_DIR/update.sh" "$@" ;;
    deps)     bash "$LIB_DIR/deps-check.sh" ;;
    fix)      bash "$LIB_DIR/setup-links.sh"; bash "$LIB_DIR/init-autostart.sh" enable
              echo "修复完成，运行 maintain.sh status 验证" ;;
    ""|menu)  show_menu ;;
    *)        echo "用法: bash maintain.sh [status|monitor|sync|update|deps|fix]"; exit 1 ;;
esac

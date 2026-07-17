#!/bin/bash
# maintain.sh — ccconfig 收尾 + 日常运维入口
#
# 用法：
#   bash maintain.sh                    # 收尾（首次安装）
#   bash maintain.sh status             # 状态检查
#   bash maintain.sh self [cc|skill|all]  # 自我更新（ccconfig + skill）
#   bash maintain.sh upgrade [comp]     # 升级组件版本
#   bash maintain.sh sync [--pull|--push] [repo]  # Git 同步
#   bash maintain.sh monitor [start|stop|status|tail]
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
    echo -e "  ${CYAN}bash maintain.sh self all${NC}   # 更新 ccconfig + skill"
    echo -e "  ${CYAN}bash maintain.sh upgrade all${NC} # 升级系统组件"
    echo -e "  ${CYAN}bash init-option.sh${NC}        # 装可选组件"
    echo ""
}

# ── 自我更新（ccconfig + skill）──
do_self() {
    local target="${1:-all}"
    case "$target" in
        cc|ccconfig)
            echo -e "${CYAN}── ccconfig 自更新 ──${NC}"
            git -C "$SCRIPT_DIR" fetch origin main 2>/dev/null || { warn "无法连接远程"; return 1; }
            local local_commit=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)
            git -C "$SCRIPT_DIR" pull --ff-only origin main 2>/dev/null && {
                local after=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
                [ "$local_commit" != "$after" ] && ok "ccconfig: $local_commit → $after" || ok "ccconfig 已是最新: $local_commit"
            } || { warn "ccconfig 拉取失败（有本地改动？）"; return 1; }
            echo ""
            bash "$LIB_DIR/setup-links.sh"
            ;;
        skill)
            echo -e "${CYAN}── Skill 同步 ──${NC}"
            bash "$LIB_DIR/init-skill.sh" sync
            ;;
        all|"")
            do_self cc
            echo ""
            do_self skill
            ;;
        *)
            err "未知 self 目标: $target（可用: cc, skill, all）"
            return 1
            ;;
    esac
}

# ── 交互菜单 ──
show_menu() {
    echo ""
    echo -e "${CYAN}ccconfig 运维中心${NC}"
    echo ""
    echo "  1) 状态检查"
    echo "  2) Monitor 管理"
    echo "  3) 自我更新（ccconfig + skill）"
    echo "  4) Git 同步其他仓库"
    echo "  5) 组件升级"
    echo "  6) 依赖检查"
    echo "  7) 自动修复（链接 + 服务）"
    echo "  0) 退出"
    echo ""
    read -p "选择 [0-7]: " c

    case "$c" in
        1) bash "$LIB_DIR/status.sh" ;;
        2) submenu_monitor ;;
        3) do_self all ;;
        4) bash "$LIB_DIR/sync.sh" ;;
        5) bash "$LIB_DIR/update.sh" menu ;;
        6) bash "$LIB_DIR/deps-check.sh" ;;
        7) bash "$LIB_DIR/setup-links.sh"
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
    self)      shift; do_self "${1:-all}" ;;
    upgrade)   shift; bash "$LIB_DIR/update.sh" "$@" ;;
    update)    shift; bash "$LIB_DIR/update.sh" "$@" ;;        # alias（旧名保留）
    sync)      shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    monitor)   bash "$LIB_DIR/monitor.sh" "${2:-}" ;;
    deps)      bash "$LIB_DIR/deps-check.sh" ;;
    fix)       bash "$LIB_DIR/setup-links.sh"
               if [ -f "$HOME/git/ccprivate/setup.sh" ]; then
                   bash "$HOME/git/ccprivate/setup.sh"
               fi
               bash "$LIB_DIR/init-autostart.sh" enable ;;
    example)   shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    menu)      show_menu ;;
    *)  echo "用法: bash maintain.sh [status|self|upgrade|sync|monitor|deps|fix|example|menu]"; exit 1 ;;
esac

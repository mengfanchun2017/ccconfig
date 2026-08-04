#!/bin/bash
# maintain.sh — ccconfig 运维入口（默认菜单）
#
# 用法：
#   bash maintain.sh                    # 交互菜单（推荐）
#   bash maintain.sh setup              # 一键收尾（首次安装/修复）
#   bash maintain.sh status [--quick]   # 状态检查（--quick 跳过慢检查）
#   bash maintain.sh self [cc|skill|all]  # 自我更新
#   bash maintain.sh upgrade [comp]     # 升级组件
#   bash maintain.sh sync [--pull|--push] [repo]  # Git 同步
#   bash maintain.sh monitor [start|stop|status|tail]
#   bash maintain.sh deps               # 依赖检查
#   bash maintain.sh fix                # 自动修复（= setup）
#
# 暗号：
#   hookstatus → bash maintain.sh status
#   pullff     → bash maintain.sh sync --pull

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CCCONFIG_DIR="$SCRIPT_DIR"

source "$LIB_DIR/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
    err()   { echo -e "  ${RED}❌ $1${NC}"; }
    warn()  { echo -e "  ${YELLOW}⚠  $1${NC}"; }
    info()  { echo -e "  ${GRAY}$1${NC}"; }
    section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
}

# ── Step 5: 收尾 ──
do_finalize() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ccconfig 收尾 — 链接修复 + 状态检查 + 服务启动${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    # 1. 修复符号链接（ccprivate/setup.sh 统一处理公私链接）
    section "1. 修复符号链接"
    local ccprivate_setup="$ccpriv/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        bash "$ccprivate_setup" 2>/dev/null && ok "符号链接已修复" || warn "符号链接部分失败"
    else
        bash "$LIB_DIR/setup-links.sh"
        info "ccprivate/setup.sh 不可用，仅修复了公开链接"
    fi

    # 1b. 补齐 ccprivate 缺失目录（空目录 git 不跟踪，clone 后不存在）
    local expected_dirs=("skill-config" "rules" "agents" "commands" "bin")
    local created=false
    for d in "${expected_dirs[@]}"; do
        if [[ ! -d "$ccpriv/$d" ]]; then
            mkdir -p "$ccpriv/$d"
            touch "$ccpriv/$d/.gitkeep"
            created=true
        fi
    done
    if $created; then
        ok "缺失 ccprivate 目录已补齐"
    fi

    # 2. auto-sync 服务
    section "2. 启动 auto-sync"
    if bash "$LIB_DIR/init-autostart.sh" enable; then
        ok "auto-sync 已启动"
    else
        warn "auto-sync 启动失败（可手动: bash $LIB_DIR/monitor.sh start）"
    fi

    # 3. Example 模板自动同步（静默，只复制新增/更新，不覆盖用户编辑过的）
    if [ -x "$LIB_DIR/example-sync.sh" ]; then
        section "3. Example 模板同步"
        bash "$LIB_DIR/example-sync.sh" sync 2>/dev/null && ok "模板已同步" || warn "模板同步跳过"
    fi

    # 4. 状态检查
    section "4. 状态总览"
    bash "$LIB_DIR/status.sh" --quick

    # 5. 输出汇总
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ccconfig 就绪 🎉${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}日常命令:${NC}"
    echo ""
    echo -e "  ${CYAN}bash maintain.sh${NC}             # 交互菜单（推荐）"
    echo -e "  ${CYAN}bash maintain.sh status --quick${NC}  # 快速状态"
    echo -e "  ${CYAN}bash maintain.sh status${NC}         # 全量状态"
    echo -e "  ${CYAN}bash maintain.sh self all${NC}       # 更新 ccconfig + skill"
    echo -e "  ${CYAN}bash maintain.sh upgrade all${NC}     # 升级系统组件"
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
    echo -e "${CYAN}━━━ ccconfig 运维中心 ━━━${NC}"
    echo ""
    echo "  1) 状态检查         ─ 全量状态（链接/依赖/同步/Git/飞书/Playwright/MCP）"
    echo "  2) Monitor 管理     ─ 启停/状态/日志/实时监控"
    echo "  3) 自我更新         ─ 拉取 ccconfig + skill 最新"
    echo "  4) Git 同步         ─ 多仓库菜单式同步"
    echo "  5) 组件升级         ─ Node.js / Claude / gh / uv / lark-cli ..."
    echo "  6) 依赖检查         ─ 必需/核心/功能/可选依赖"
    echo "  7) 一键修复         ─ 重建链接 + 启用 auto-sync（= setup）"
    echo "  8) 模板同步         ─ 默认正向（template → ccprivate），反向仅仓库所有者可用"
    echo "  9) ccprivate 升级    ─ 检测并修复 ccprivate 结构"
    echo "  10) Bill & Token     ─ 模型单价配置 + Claude Code 用量聚合（CSV / 飞书）"
    echo ""
    echo "  0) 退出"
    echo ""
    read -p "选择 [0-10]: " c

    case "$c" in
        1) bash "$LIB_DIR/status.sh" "$@" ;;
        2) submenu_monitor ;;
        3) do_self all ;;
        4) bash "$LIB_DIR/sync.sh" ;;
        5) bash "$LIB_DIR/update.sh" menu ;;
        6) bash "$LIB_DIR/deps-check.sh" ;;
        7) do_finalize ;;
        8) bash "$LIB_DIR/example-sync.sh" status
           echo ""
           echo "  d) 查看差异   f) 正向同步（默认）   r) 反向同步（需 push 权限）   0) 返回"
           read -p "选择 [d/f/r/0]: " choice
           case "$choice" in
             d) bash "$LIB_DIR/example-sync.sh" diff ;;
             f) bash "$LIB_DIR/example-sync.sh" promote ;;
             r) bash "$LIB_DIR/example-sync.sh" reverse ;;
             0) ;;
             *) ;;
           esac ;;
        9) bash "$LIB_DIR/ccprivate-upgrade.sh"
           echo ""
           read -p "按回车返回菜单..." dummy
           show_menu ;;
        10) while true; do
           echo ""
           echo "  ─ Bill & Token ─"
           echo "  1) Bill (配置模型 token 单价)"
           echo "  2) 用量统计 (总览)"
           echo "  3) 按日报告"
           echo "  4) 按天归档 (增量 → ccprivate/usage/)"
           echo "  5) 推飞书 (用配置 URL，弹提示输可临时覆盖)"
           echo "  6) timer 管理 (装/卸/状态/配置)"
           echo "  0) 返回"
           read -p "  选择 [0-6]: " choice
           case "$choice" in
             1) bash "$LIB_DIR/init-llm.sh" bill ;;
             2) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --stats ;;
             3) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --report ;;
             4) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ;;
             5)
                read -p "  飞书 URL (回车 = 用 config 默认): " url
                if [[ -n "$url" ]]; then
                   bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --feishu "$url"
                else
                   bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental
                fi
                ;;
             6) bash "$CCCONFIG_DIR/option-usage/init.sh" status
                echo ""
                echo "  ─ 操作 ─"
                echo "    i) 装 systemd timer"
                echo "    u) 卸 systemd timer"
                echo "    c) 配置 feishu_url / schedule / include_today"
                echo "    b) 返回"
                read -p "  选择 [i/u/c/b]: " sub
                case "$sub" in
                  i) bash "$CCCONFIG_DIR/option-usage/init.sh" install ;;
                  u) bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall ;;
                  c) bash "$CCCONFIG_DIR/option-usage/init.sh" config ;;
                esac
                ;;
             0) break ;;
             *) ;;
           esac
           echo ""
           echo "  按回车继续..."
           read -r dummy
           done ;;
        0) echo ""; exit 0 ;;
        *) show_menu ;;
    esac

    echo ""
    read -p "按回车返回菜单..." dummy
    show_menu
}

submenu_monitor() {
    echo ""
    echo -e "${CYAN}── Monitor 管理 ──${NC}"
    echo ""
    echo "  1) 启动             ─ 后台启动文件监控 + 自动提交推送"
    echo "  2) 停止             ─ 停止监控进程"
    echo "  3) 看状态           ─ 进程状态 + 各仓库待提交文件数"
    echo "  4) 实时追踪 (tail)  ─ 持续输出推送结果（Ctrl+C 退出）"
    echo "  5) 文件变更 (mon)   ─ 实时显示文件变更事件（Ctrl+C 退出）"
    echo ""
    echo "  0) 返回"
    echo ""
    read -p "选择 [0-5]: " c
    case "$c" in
        1) bash "$LIB_DIR/monitor.sh" start ;;
        2) bash "$LIB_DIR/monitor.sh" stop ;;
        3) bash "$LIB_DIR/monitor.sh" status ;;
        4) bash "$LIB_DIR/monitor.sh" tail ;;
        5) bash "$LIB_DIR/monitor.sh" monitor ;;
        0) return ;;
        *) submenu_monitor ;;
    esac
}

# ── 入口 ──
case "${1:-menu}" in
    menu|"")   show_menu ;;
    setup|finalize|first|init)  do_finalize ;;
    status)    shift; bash "$LIB_DIR/status.sh" "$@" ;;
    self)      shift; do_self "${1:-all}" ;;
    upgrade)   shift; bash "$LIB_DIR/update.sh" "$@" ;;
    update)    shift; bash "$LIB_DIR/update.sh" "$@" ;;        # alias（旧名保留）
    sync)      shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    monitor)   shift; bash "$LIB_DIR/monitor.sh" "${1:-}" ;;
    deps)      bash "$LIB_DIR/deps-check.sh" ;;
    fix)       do_finalize ;;
    example)   shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    upgrade-ccprivate|upgrade-ccpriv|ccpriv-upgrade)
        shift; bash "$LIB_DIR/ccprivate-upgrade.sh" "$@" ;;
    token|usage)
        shift; bash "$CCCONFIG_DIR/option-usage/token-usage.sh" "$@" ;;
    *)  echo "用法: bash maintain.sh [status|self|upgrade|sync|monitor|deps|fix|example|setup|upgrade-ccprivate|token|menu]"; exit 1 ;;
esac

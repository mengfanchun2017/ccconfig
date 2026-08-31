#!/bin/bash
# maintain.sh — ccconfig 运维入口（数据驱动菜单）
#
# 用法：
#   bash maintain.sh                  # 交互菜单
#   bash maintain.sh status           # 直接执行子命令
#   bash maintain.sh fix              # 一键修复
#
# 数据层: menu-data-maintain.sh
# 渲染/解析: interact.sh menu_loop
#

set -euo pipefail
# maintain.sh 在 ccconfig 根目录，SCRIPT_DIR 指向根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CCCONFIG_DIR="$SCRIPT_DIR"

source "$LIB_DIR/dry-run.sh"
source "$LIB_DIR/path-helper.sh" 2>/dev/null || true
export PATH="$HOME/.local/bin:$(find_node_bin 2>/dev/null || echo ""):$PATH"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/interact.sh"
source "$LIB_DIR/menu-data-maintain.sh"
source "$LIB_DIR/menu-feishu.sh"

# ========== 子菜单函数 ==========

_submenu_monitor() {
    local c; c=$(menu_select "Monitor" \
        "LLM 链路诊断" \
        "切 LLM 预设" \
        "模型单价配置" \
        "bridge 自愈" \
        "状态查看" \
        "启动" \
        "停止" \
        "重启" \
        "修复" \
        "返回")
    [[ -z "$c" || "$c" = "0" ]] && return
    case "$c" in
        1) bash "$SCRIPT_DIR/lib/init-llm.sh" status ;;
        2) bash "$SCRIPT_DIR/lib/init-llm.sh" ;;
        3) bash "$SCRIPT_DIR/lib/init-llm-bill.sh" ;;
        4) bash "$SCRIPT_DIR/lib/init-llm.sh" heal ;;
        5) bash "$LIB_DIR/monitor.sh" status ;;
        6) bash "$LIB_DIR/monitor.sh" start ;;
        7) bash "$LIB_DIR/monitor.sh" stop ;;
        8) bash "$LIB_DIR/monitor.sh" stop; sleep 1; bash "$LIB_DIR/monitor.sh" start ;;
        9) fix_monitor ;;
    esac
}

_submenu_usage() {
    local c; c=$(menu_select "用量统计" \
        "用量统计" \
        "按日报告" \
        "按天归档" \
        "推飞书" \
        "timer 管理" \
        "手动触发" \
        "返回")
    [[ -z "$c" || "$c" = "0" ]] && return
    case "$c" in
        1) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --stats ;;
        2) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --report ;;
        3) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ;;
        4) url=$(prompt "飞书 URL"); bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ${url:+--feishu "$url"} ;;
        5) bash "$CCCONFIG_DIR/option-usage/init.sh" status
           ts=$(menu_select "timer" \
 "安装" \
 "卸载" \
 "配置" \
 "返回")
           case "$ts" in 1) bash "$CCCONFIG_DIR/option-usage/init.sh" install;; 2) bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall;; 3) bash "$CCCONFIG_DIR/option-usage/init.sh" config;; 4|0|*) return;; esac ;;
        6) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
    esac
}

_submenu_getnote() {
    local sw="$CCCONFIG_DIR/option-getnote/getnote-switch.sh"
    local init="$CCCONFIG_DIR/option-getnote/init.sh"

    echo ""; section "getnote 账号"
    bash "$sw" --list 2>/dev/null || echo -e "  ${YELLOW}无 getnote 账号${NC}"
    echo ""
    local c; c=$(menu_select "配置调整" \
        "添加" \
        "删除" \
        "切换(session)" \
        "切换(持久化)" \
        "返回")
    [[ "$c" = "0" ]] && return 0
    case "$c" in
        1) bash "$init" add ;;
        2) bash "$init" remove ;;
        3) target=$(prompt "账号名"); [ -n "$target" ] && bash "$sw" "$target" ;;
        4) target=$(prompt "账号名"); [ -n "$target" ] && bash "$sw" "$target" -p ;;
    esac
}

_submenu_update_sync() {
    local c; c=$(menu_select "更新同步" \
        "自我更新" \
        "Git 同步" \
        "全部" \
        "返回")
    [[ -z "$c" || "$c" = "0" ]] && return
    case "$c" in
        1) do_self all ;;
        2) bash "$LIB_DIR/sync.sh" ;;
        3) do_self all && bash "$LIB_DIR/sync.sh" ;;
    esac
}

# ========== 主动能 ==========

do_finalize() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ccconfig 一键修复 — 符号链接 + 缺失目录 + auto-sync + 模板同步${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    section "1. 修复符号链接"
    local ccprivate_setup="$ccpriv/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        bash "$ccprivate_setup" 2>/dev/null && ok "符号链接已修复" || warn "符号链接部分失败"
    else
        bash "$LIB_DIR/setup-links.sh"
        info "ccprivate/setup.sh 不可用，仅修复了公开链接"
    fi

    local expected_dirs=("skill" "rules" "agents" "commands" "bin")
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

    section "2. 启动 auto-sync"
    if bash "$LIB_DIR/init-autostart.sh" enable; then
        ok "auto-sync 已启动"
    else
        warn "auto-sync 启动失败（可手动: bash $LIB_DIR/monitor.sh start）"
    fi

    section "3. 依赖检查"
    if bash "$LIB_DIR/deps-check.sh"; then
        ok "依赖完整"
    else
        warn "部分依赖缺失，详见上方输出"
    fi

    section "4. 状态总览"
    bash "$LIB_DIR/status.sh" --quick

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

do_self() {
    local target="${1:-all}"
    case "$target" in
        cc|ccconfig)
            echo -e "${CYAN}── ccconfig 自更新 ──${NC}"
            if ! git -C "$SCRIPT_DIR" fetch origin main 2>/dev/null; then
                warn "无法连接远程（网络不通），跳过自更新"
                return 1
            fi
            local local_commit=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)
            git -C "$SCRIPT_DIR" pull --ff-only origin main 2>/dev/null && {
                local after=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
                [ "$local_commit" != "$after" ] && ok "ccconfig: $local_commit → $after" || ok "ccconfig 已是最新: $local_commit"
            } || { warn "ccconfig 拉取失败（有本地改动？）"; return 1; }
            echo ""
            bash "$LIB_DIR/setup-links.sh" ;;
        skill)
            echo -e "${CYAN}── Skill 同步 ──${NC}"
            bash "$LIB_DIR/init-skill.sh" sync ;;
        all|"")
            do_self cc
            echo ""
            do_self skill ;;
        *) err "未知 self 目标: $target（可用: cc, skill, all）"; return 1 ;;
    esac
}

fix_monitor() {
    echo -e "${CYAN}━━━ Monitor 修复（inotify-tools + 重启）━━━${NC}"
    echo ""

    source "$LIB_DIR/install-inotify.sh"
    if ! install_inotify; then
        err "inotify-tools 装不上 — 手动: sudo apt install inotify-tools"
        return 1
    fi

    if bash "$LIB_DIR/monitor.sh" stop 2>/dev/null; then
        info "旧 monitor 已停止"
    fi
    pkill -f "inotifywait.*$HOME/git" 2>/dev/null || true

    if bash "$LIB_DIR/monitor.sh" start; then
        echo ""
        ok "Monitor 已修复并重启"
        bash "$LIB_DIR/monitor.sh" status
    else
        err "Monitor 启动失败"
        return 1
    fi
}

# ========== 入口 ==========

# 测试模式：source 时只加载函数/数据，不进交互菜单（仿 init-llm.sh TEST_MODE）
[[ "${MAINTAIN_TEST_MODE:-0}" == "1" ]] || case "${1:-menu}" in
    menu|"")
        menu_loop "ccconfig 运维中心"
        ;;
    status)  shift; bash "$LIB_DIR/status.sh" "$@" ;;
    self)    shift; do_self "${1:-all}" ;;
    setup|finalize|first|init|fix)
        shift
        case "${1:-all}" in
            monitor) fix_monitor ;;
            all|"")  do_finalize ;;
            *)       err "未知 fix 子命令: $1"; exit 1 ;;
        esac ;;
    upgrade) shift; bash "$LIB_DIR/update.sh" "$@" ;;
    sync)    shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    monitor) shift; bash "$LIB_DIR/monitor.sh" "${1:-}" ;;
    deps)    bash "$LIB_DIR/deps-check.sh" ;;
    llm)     shift; bash "$LIB_DIR/init-llm.sh" "$@" ;;
    llmswitch|llm-switch|gate)
        shift; bash "$CCCONFIG_DIR/option-llmswitch/init.sh" "$@" ;;
    mcp)     shift; bash "$LIB_DIR/mcp-manager.sh" "$@" ;;
    pat|pat-refresh|gh-auth)
        bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
    test|bootstrap|regression)
        shift; bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" "$@" ;;
    token|usage)
        shift; bash "$CCCONFIG_DIR/option-usage/token-usage.sh" "$@" ;;
    feishu)
        ccbridge_test="${CCBRIDGE_HOME:-$HOME/git/ccbridge}/tests/test-feishu.sh"
        if [ -f "$ccbridge_test" ]; then
            bash "$ccbridge_test" "$@"
        else
            info "ccbridge 未安装，测试跳过"
        fi ;;
    example)
        shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    upgrade-ccprivate|upgrade-ccpriv|ccpriv-upgrade)
        shift; bash "$LIB_DIR/ccprivate-upgrade.sh" "$@" ;;
    *)
        echo "用法: bash maintain.sh [status|self|upgrade|sync|monitor|deps|fix|...]"
        exit 1 ;;
esac

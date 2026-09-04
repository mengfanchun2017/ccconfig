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
    local c; c=$(menu_select "监控" \
        "状态" \
        "启动" \
        "停止" \
        "重启" \
        "追踪日志" \
        "修复 inotify" \
        "返回")
    [[ -z "$c" || "$c" = "0" || "$c" = "7" ]] && return
    case "$c" in
        1) bash "$LIB_DIR/monitor.sh" status ;;
        2) bash "$LIB_DIR/monitor.sh" start ;;
        3) bash "$LIB_DIR/monitor.sh" stop ;;
        4) bash "$LIB_DIR/monitor.sh" stop; sleep 1; bash "$LIB_DIR/monitor.sh" start ;;
        5) bash "$LIB_DIR/monitor.sh" tail ;;
        6) fix_monitor ;;
    esac
}

_submenu_usage() {
    local ini="$CCCONFIG_DIR/option-usage/init.sh"
    local tu="$CCCONFIG_DIR/option-usage/token-usage.sh"
    local cdir="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    # ── 状态横幅 ──
    local tstate schedule
    if systemctl is-active ccconfig-token-usage.timer 2>/dev/null | grep -q active; then
        tstate="${GREEN}✅ 运行中${NC}"
    else
        tstate="${YELLOW}⚠ 未启用${NC}"
    fi
    schedule=$(python3 -c "import json;d=json.load(open('$cdir/conf/token-usage.json'));print(d.get('schedule','12:01:00'))" 2>/dev/null || echo "12:01:00")
    section "Token 用量管理"
    echo -e "  Timer:   $tstate  (${schedule} 每日）"
    echo -e "  保存:    $cdir/usage/YYYY-MM-DD.csv"
    echo -e "  逻辑:    扫 ~/.claude jsonl → 按天${BOLD}写一次${NC}（历史 day 跳过）"
    echo -e "           今天不写（明天定稿）；跨天 session 按天分摊"
    echo -e "           关机补跑: Persistent=true + 全量重算自动补缺"
    echo ""

    local items=("用量统计（跨 LLM 总量）" "按日报告" "立即归档（增量，只写新 day）" "今日快照（含今天）" "强制重算全量（改 pricing/列后用）" "启用 timer" "停用 timer" "配置（时间/飞书/含今天）" "设置费用 pricing" "返回")
    local c; c=$(menu_select "用量管理" "${items[@]}")
    [[ -z "$c" || "$c" = "0" || "$c" = "${#items[@]}" ]] && return
    case "$c" in
        1) bash "$tu" --stats ;;
        2) bash "$tu" --report ;;
        3) bash "$tu" --by-day ;;
        4) bash "$tu" --by-day --include-today ;;
        5) bash "$tu" --by-day --force ;;
        6) bash "$ini" install ;;
        7) bash "$ini" uninstall ;;
        8) bash "$ini" config ;;
        9) bash "$LIB_DIR/init-llm-bill.sh" ;;
    esac
}

_submenu_getnote() {
    local sw="$CCCONFIG_DIR/option-getnote/getnote-switch.sh"
    local init="$CCCONFIG_DIR/option-getnote/init.sh"

    section "getnote 账号"
    bash "$sw" --list 2>/dev/null || echo -e "  ${YELLOW}无 getnote 账号${NC}"
    echo ""
    local c; c=$(menu_select "配置" \
        "添加账号" \
        "删除账号" \
        "切换(session)" \
        "切换(持久化)" \
        "返回")
    [[ -z "$c" || "$c" = "0" || "$c" = "5" ]] && return
    case "$c" in
        1) bash "$init" add ;;
        2) bash "$init" remove ;;
        3) target=$(prompt "账号名"); [ -n "$target" ] && bash "$sw" "$target" ;;
        4) target=$(prompt "账号名"); [ -n "$target" ] && bash "$sw" "$target" -p ;;
    esac
}

_submenu_update_sync() {
    local c; c=$(menu_select "更新配置" \
        "ccconfig 更新" \
        "ccprivate 升级" \
        "Git 同步" \
        "全部" \
        "返回")
    [[ -z "$c" || "$c" = "0" || "$c" = "5" ]] && return
    case "$c" in
        1) do_self all ;;
        2) bash "$LIB_DIR/ccprivate-upgrade.sh" ;;
        3) bash "$LIB_DIR/sync.sh" ;;
        4) do_self all && bash "$LIB_DIR/sync.sh" ;;
    esac
}

# ========== 主动能 ==========

do_setup() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  ccconfig 一键修复 — 符号链接 + 缺失目录 + auto-sync ${NC}"
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

    local expected_dirs=("skill" "skill-local" "rules" "agents" "commands" "bin" "usage" "workflow_local")
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

    section "3. 状态总览"
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
            echo -e "${CYAN}── ccconfig 更新 ──${NC}"
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
            all|"")  do_setup ;;
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
        echo "用法: bash maintain.sh [status|self|setup|upgrade|sync|monitor|llm|mcp|pat|token|feishu]"
        exit 1 ;;
esac

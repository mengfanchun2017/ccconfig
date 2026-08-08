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
#   bash maintain.sh llmswitch [start|stop|restart|status]   # LLM 网关代理
#   bash maintain.sh fix                # 自动修复（= setup）
#
# 暗号：
#   hookstatus → bash maintain.sh status
#   pullff     → bash maintain.sh sync --pull

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CCCONFIG_DIR="$SCRIPT_DIR"

source "$LIB_DIR/dry-run.sh"
source "$LIB_DIR/path-helper.sh" 2>/dev/null || true
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
    echo "  5) 组件升级         ─ Node.js / Claude / gh / uv / lark-cli / lark-channel-bridge ..."
    echo "  6) 依赖检查         ─ 必需/核心/功能/可选依赖"
    echo "  7) 一键修复         ─ 重建链接 + 启用 auto-sync（= setup）"
    echo "  8) 模板同步         ─ 默认正向（template → ccprivate），反向仅仓库所有者可用"
    echo "  9) ccprivate 升级    ─ 检测并修复 ccprivate 结构"
    echo "  10) Bill & Token     ─ 模型单价配置 + Claude Code 用量聚合（CSV / 飞书）"
	echo "  11) MCP 管理         ─ 注册/启停/状态/Key/项目配置"
    echo "  12) llmswitch        ─ LLM 网关代理（init-llm 自动管理，手动可看下面板）"
    echo "  13) 飞书管理         ─ 账号 / lark-cli / larkbridge（多账号多机器人）"
    echo ""
    echo "  0) 退出"
    echo ""
    read -p "选择 [0-13]: " c
    c=$(menu_num "$c")

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
        11) bash "$LIB_DIR/mcp-manager.sh" config
            read -p "按回车返回菜单..." dummy
            show_menu ;;
        12) submenu_llmswitch
            read -p "按回车返回菜单..." dummy
            show_menu ;;
        13) submenu_feishu
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
           echo "  7) 手动触发归档+推飞书 (按配置跑，不含今天)"
           echo "  0) 返回"
           read -p "  选择 [0-7]: " choice
           choice=$(menu_num "$choice")
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
             7) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
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
    c=$(menu_num "$c")
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

submenu_llmswitch() {
    echo ""
    echo -e "${CYAN}── llmswitch 网关代理 ──${NC}"
    echo -e "${GRAY}  由 init-llm 自动管理（按 provider 自动启/停）${NC}"
    echo ""
    echo "  1) 启动代理        ─ bash option-llmswitch/init.sh --start"
    echo "  2) 停止代理        ─ bash option-llmswitch/init.sh --stop"
    echo "  3) 重启代理        ─ bash option-llmswitch/init.sh --restart"
    echo "  4) 查看状态        ─ bash option-llmswitch/init.sh --status"
    echo "  5) 切换 LLM (推荐) ─ 自动按 provider 启/停（gate/minimax/...）"
    echo ""
    echo "  0) 返回"
    echo ""
    read -p "选择 [0-5]: " c
    c=$(menu_num "$c")
    case "$c" in
        1) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --start ;;
        2) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --stop ;;
        3) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --restart ;;
        4) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --status ;;
        5) bash "$LIB_DIR/init-llm.sh" ;;
        0) return ;;
        *) submenu_llmswitch ;;
    esac
}

# 读取 feishu.json 账号列表（一行一 JSON）
_feishu_list_apps() {
    local conf
    conf="$(resolve_conf feishu.json 2>/dev/null)" || true
    if [ -z "$conf" ] || [ ! -f "$conf" ]; then
        echo ""
        return 0
    fi
    python3 - "$conf" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for a in d.get('apps', []):
    print(json.dumps(a, ensure_ascii=False))
PYEOF
}

_feishu_current_account() {
    local marker="$HOME/.lark-cli-account"
    [ -f "$marker" ] && grep '^name=' "$marker" | cut -d'=' -f2
}

_feishu_current_profile() {
    [ -f "$HOME/.lark-channel/config.json" ] \
        && python3 -c "import json; print(json.load(open('$HOME/.lark-channel/config.json')).get('activeProfile',''))" 2>/dev/null
}

submenu_feishu() {
    local feishu_lb="$CCCONFIG_DIR/option-larkbridge/init.sh"
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"
    local lcb_ver; lcb_ver=$(lark-channel-bridge --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
    local lcc_ver; lcc_ver=$(lark-cli --version 2>/dev/null | head -1 | sed 's/^[^0-9]*//' || echo "?")

    local cur_acct; cur_acct="$(_feishu_current_account)"
    local cur_prof; cur_prof="$(_feishu_current_profile)"

    echo ""
    echo -e "${CYAN}── 飞书统一管理 ──${NC}"
    echo ""
    echo -e "  ${GRAY}lark-cli: v${lcc_ver}    活跃账号: ${cur_acct:-无}${NC}"
    echo -e "  ${GRAY}lark-channel-bridge: v${lcb_ver}    活跃 profile: ${cur_prof:-无}${NC}"
    echo ""
    echo "  1) 飞书账号          ─ feishu.json apps 列表 + 切换 lark-cli 活跃账号"
    echo "  2) lark-cli          ─ OAuth 授权 / 看授权状态 / 装包"
    echo "  3) larkbridge        ─ profile 列表 / 启停 / 日志 / 新增 / 删除"
    echo "  4) 一键升级飞书      ─ lark-cli + lark-channel-bridge (npm 最新)"
    echo ""
    echo "  0) 返回"
    echo ""
    read -p "选择 [0-4]: " c
    c=$(menu_num "$c")
    case "$c" in
        1) submenu_feishu_accounts ;;
        2)
            echo ""
            echo -e "${CYAN}── lark-cli ──${NC}"
            bash "$feishu_lc" --status
            echo ""
            echo "  a) 重置全部账号配置 (re-run init)"
            echo "  k) 看当前账号的 OAuth 状态"
            echo "  l) 列出全部账号"
            echo "  0) 返回"
            read -p "  选择 [a/k/l/0]: " sub
            case "$sub" in
                a|A) bash "$feishu_lc" ;;
                k|K) bash "$feishu_switch" ;;
                l|L) bash "$feishu_switch" --list ;;
                0) ;;
                *) ;;
            esac
            ;;
        3)
            echo ""
            bash "$feishu_lb" --status
            echo ""
            echo "  ─ 操作 ─"
            echo "    s) 启停/重启 profile  ─ select"
            echo "    n) 新增 profile       ─ add（ccprivate 配置 or 扫码）"
            echo "    r) 删除 profile       ─ remove"
            echo "    l) 实时日志           ─ logs <profile>"
            echo "    d) 设为默认           ─ default"
            echo "    0) 返回"
            read -p "  选择 [s/n/r/l/d/0]: " sub
            case "$sub" in
                s|S) bash "$feishu_lb" --start ;;
                n|N) bash "$feishu_lb" --profile add ;;
                r|R) bash "$feishu_lb" --profile remove ;;
                l|L) bash "$feishu_lb" --logs ;;
                d|D) bash "$feishu_lb" --profile default ;;
                0) ;;
                *) ;;
            esac
            ;;
        4)
            echo ""
            echo -e "${CYAN}── 一键升级飞书 ──${NC}"
            bash "$LIB_DIR/update.sh" lark
            echo ""
            bash "$LIB_DIR/update.sh" larkbridge
            echo ""
            echo "按回车继续..."
            read -r dummy
            ;;
        0) return ;;
        *) submenu_feishu ;;
    esac
}

submenu_feishu_accounts() {
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"
    local conf
    conf="$(resolve_conf feishu.json 2>/dev/null)" || { warn "找不到 feishu.json"; return 0; }

    while true; do
        local cur_acct; cur_acct="$(_feishu_current_account)"
        local -a lines names
        while IFS= read -r line; do
            [ -n "$line" ] && lines+=("$line")
        done < <(_feishu_list_apps)

        echo ""
        echo -e "${CYAN}── 飞书账号 (feishu.json apps[]) ──${NC}"
        echo -e "  ${GRAY}活跃账号: ${cur_acct:-无}    配置文件: ${conf}${NC}"
        echo ""

        if [ ${#lines[@]} -eq 0 ]; then
            warn "feishu.json 中无 app 配置"
            echo "  a) 添加新 app"
            echo "  0) 返回"
            read -p "  选择 [a/0]: " sel
            case "$sel" in
                a|A) bash "$feishu_lc" ;;
                0) return 0 ;;
            esac
            continue
        fi

        local i=1
        names=()
        for line in "${lines[@]}"; do
            local name; name=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
            local appid; appid=$(echo "$line" | python3 -c "import json,sys; a=json.load(sys.stdin)['appId']; print((a[:14]+'...') if len(a)>14 else a)" 2>/dev/null)
            local desc; desc=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" 2>/dev/null)
            local lcen; lcen=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print('Y' if d.get('larkCli',{}).get('enabled') else '.')" 2>/dev/null)
            local lben; lben=$(echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin).get('larkBridge',{}); print('Y' if d.get('enabled') else '.')" 2>/dev/null)
            local marker="  "
            [ "$name" = "$cur_acct" ] && marker="${GREEN}← 活跃${NC}"
            printf "  ${YELLOW}%d)${NC} %-14s appId=${GRAY}%-18s${NC} L=${lcen} B=${lben}  ${marker}\n" "$i" "$name" "$appid"
            [ -n "$desc" ] && printf "       ${GRAY}%s${NC}\n" "$desc"
            names+=("$name")
            i=$((i + 1))
        done
        echo ""
        echo "  a) 添加新 app"
        echo "  d) 删除 app"
        echo "  0) 返回"
        echo ""
        read -p "  选择 [0-${#lines[@]}/a/d]: " sel

        case "$sel" in
            0|q) return 0 ;;
            a|A) bash "$feishu_lc" ;;
            d|D)
                if [ ${#names[@]} -eq 0 ]; then continue; fi
                read -p "  输入要删除的 app 名: " dn
                local found=0
                for n in "${names[@]}"; do [ "$n" = "$dn" ] && found=1 && break; done
                [ "$found" -eq 1 ] && {
                    read -p "  确认从 feishu.json 删 '${dn}'? [y/N] " cf
                    if [[ "$cf" =~ ^[Yy]$ ]]; then
                        python3 - "$conf" "$dn" << 'PYEOF'
import json, sys
p, name = sys.argv[1], sys.argv[2]
with open(p) as f: d = json.load(f)
d['apps'] = [a for a in d.get('apps',[]) if a.get('name') != name]
with open(p,'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
                        info "已删除"
                    fi
                } || warn "未找到: $dn"
                continue
                ;;
        esac

        if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -lt 1 ] || [ "$sel" -gt ${#lines[@]} ]; then
            continue
        fi

        local target="${names[$((sel - 1))]}"
        echo ""
        echo -e "${CYAN}── 应用: ${target} ──${NC}"
        echo ""
        echo "  1) 切到此账号 (lark-cli 活跃)"
        echo "  2) OAuth 授权 (lark-cli auth login)"
        echo "  3) 看授权状态"
        echo "  4) 编辑 App ID / Secret"
        echo "  0) 返回"
        read -p "  选择 [0-4]: " sub
        case "$sub" in
            1) bash "$feishu_switch" "$target" ;;
            2)
                local cd="$HOME/.lark-cli-${target}"
                if [ -f "${cd}/config.json" ]; then
                    LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$feishu_lc" --auth-login "$target"
                else
                    warn "先选 4 编辑 App ID/Secret，再走 lark-cli init"
                fi
                ;;
            3)
                local cd="$HOME/.lark-cli-${target}"
                if [ -f "${cd}/config.json" ]; then
                    LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>&1 \
                        | grep -v '^\[lark-cli\]' | sed 's/^/  /'
                else
                    warn "config.json 不存在"
                fi
                ;;
            4) bash "$feishu_lc" --auth-login "$target" 2>&1 || true
               warn "手动编辑: vim $conf"
               ;;
            0) ;;
            *) ;;
        esac
    done
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
    token-run)
        bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill --include-today ;;
    mcp)     shift; bash "$LIB_DIR/mcp-manager.sh" "$@" ;;
    llmswitch|llm-switch|gate)
        shift; bash "$CCCONFIG_DIR/option-llmswitch/init.sh" "$@" ;;
    *)  echo "用法: bash maintain.sh [status|self|upgrade|sync|monitor|deps|fix|example|setup|upgrade-ccprivate|token|mcp|llmswitch|menu]"; exit 1 ;;
esac

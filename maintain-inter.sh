#!/bin/bash
# maintain-inter.sh — ccconfig 运维入口（interact.sh 改造版）
#
# 与 maintain.sh 功能完全一致，但菜单/交互全部用 lib/interact.sh
# 有 gum 自动用 gum TUI，无 gum 退化纯 sh
#
# 用法:
#   bash maintain-inter.sh              # 交互菜单
#   bash maintain-inter.sh status       # 直跑子命令
#   bash maintain-inter.sh setup        # 收尾
#   全部子命令同 maintain.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CCCONFIG_DIR="$SCRIPT_DIR"

source "$LIB_DIR/dry-run.sh"
source "$LIB_DIR/path-helper.sh" 2>/dev/null || true
export PATH="$HOME/.local/bin:$(find_node_bin 2>/dev/null || echo ""):$PATH"
source "$LIB_DIR/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; DIM='\033[2m'; NC='\033[0m'
    ok() { echo -e "  ${GREEN}✅ $1${NC}"; }
    err() { echo -e "  ${RED}❌ $1${NC}"; }
    warn() { echo -e "  ${YELLOW}⚠  $1${NC}"; }
    info() { echo -e "  ${GRAY}$1${NC}"; }
    section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
}
source "$LIB_DIR/interact.sh"

# ===== 收尾 =====
do_finalize() {
    section "ccconfig 收尾 — 链接修复 + 状态检查 + 服务启动"
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    # 1. 修复符号链接
    section "1. 修复符号链接"
    local ccprivate_setup="$ccpriv/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        bash "$ccprivate_setup" 2>/dev/null && ok "符号链接已修复" || warn "符号链接部分失败"
    else
        bash "$LIB_DIR/setup-links.sh"
        info "ccprivate/setup.sh 不可用，仅修复了公开链接"
    fi

    # 1b. 补齐 ccprivate 缺失目录
    local expected_dirs=("skill-config" "rules" "agents" "commands" "bin") created=false
    for d in "${expected_dirs[@]}"; do
        if [[ ! -d "$ccpriv/$d" ]]; then
            mkdir -p "$ccpriv/$d"; touch "$ccpriv/$d/.gitkeep"; created=true
        fi
    done; $created && ok "缺失 ccprivate 目录已补齐"

    # 2. auto-sync
    section "2. 启动 auto-sync"
    bash "$LIB_DIR/init-autostart.sh" enable 2>/dev/null && ok "auto-sync 已启动" || warn "auto-sync 启动失败"

    # 3. 模板同步
    section "3. Example 模板同步"
    if [ -x "$LIB_DIR/example-sync.sh" ]; then
        bash "$LIB_DIR/example-sync.sh" sync 2>/dev/null && ok "模板已同步" || warn "模板同步跳过"
    fi

    # 4. 状态
    section "4. 状态总览"
    bash "$LIB_DIR/status.sh" --quick

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ccconfig 就绪 🎉${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}日常命令:${NC}"
    echo "  bash maintain-inter.sh"
    echo "  bash maintain-inter.sh status --quick"
    echo "  bash maintain-inter.sh self all"
    echo "  bash maintain-inter.sh upgrade all"
    echo ""
}

# ===== Monitor 修复 =====
fix_monitor() {
    section "Monitor 修复（inotify-tools + 重启）"
    source "$LIB_DIR/install-inotify.sh"
    install_inotify || { err "inotify-tools 装不上"; return 1; }
    bash "$LIB_DIR/monitor.sh" stop 2>/dev/null; pkill -f "inotifywait.*$HOME/git" 2>/dev/null || true
    bash "$LIB_DIR/monitor.sh" start && { ok "Monitor 已修复并重启"; bash "$LIB_DIR/monitor.sh" status; } || { err "Monitor 启动失败"; return 1; }
}

# ===== 自我更新 =====
do_self() {
    local target="${1:-all}"
    case "$target" in
        cc|ccconfig)
            section "ccconfig 自更新"
            git -C "$SCRIPT_DIR" fetch origin main 2>/dev/null || { warn "无法连接远程"; return 1; }
            local before=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)
            git -C "$SCRIPT_DIR" pull --ff-only origin main 2>/dev/null && {
                local after=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
                [ "$before" != "$after" ] && ok "ccconfig: $before → $after" || ok "ccconfig 已是最新: $before"
            } || { warn "拉取失败"; return 1; }
            bash "$LIB_DIR/setup-links.sh"
            ;;
        skill) section "Skill 同步"; bash "$LIB_DIR/init-skill.sh" sync ;;
        all|"") do_self cc; echo ""; do_self skill ;;
        *) err "未知 self 目标: $target"; return 1 ;;
    esac
}

# ===== 菜单 =====
show_menu() {
    # 主菜单直接用 menu_select
    items=(
        "1) 状态检查"
        "2) Monitor 管理"
        "3) 自我更新"
        "4) Git 同步"
        "5) 组件升级"
        "6) 依赖检查"
        "7) 一键修复"
        "8) 模板同步"
        "9) ccprivate 升级"
        "10) Bill & Token"
        "11) MCP 管理"
        "12) llmswitch"
        "13) 飞书管理"
        "14) 回归测试"
        "15) GitHub PAT"
        "16) LLM 切换"
        "17) getnote 账号"
        "0) 退出"
    )

    # menu_select 返回选中文本，取数字
    local selected
    selected=$(menu_select "ccconfig 运维中心" "${items[@]}")
    [[ -z "$selected" ]] && { show_menu; return; }

    local c="${selected:0:1}"  # "1)" → "1"
    c="${c%%[!0-9]*}"

    case "$c" in
        0) echo ""; exit 0 ;;
        1) bash "$LIB_DIR/status.sh" ;;
        2) submenu_monitor ;;
        3) do_self all ;;
        4) bash "$LIB_DIR/sync.sh" ;;
        5) bash "$LIB_DIR/update.sh" menu ;;
        6) bash "$LIB_DIR/deps-check.sh" ;;
        7) do_finalize ;;
        8) submenu_example ;;
        9) bash "$LIB_DIR/ccprivate-upgrade.sh" ;;
        10) submenu_bill_token ;;
        11) bash "$LIB_DIR/mcp-manager.sh" config ;;
        12) submenu_llmswitch ;;
        13) submenu_feishu ;;
        14) bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" ;;
        15) bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
        16) bash "$LIB_DIR/init-llm.sh" ;;
        17) submenu_getnote ;;
        *) ;;
    esac

    echo ""
    read -p "按回车返回菜单..." dummy
    show_menu
}

submenu_monitor() {
    local selected
    selected=$(menu_select "Monitor 管理" \
        "1) 启动" "2) 停止" "3) 看状态" "4) 实时追踪" "5) 文件变更" "6) 修复" "0) 返回")
    [[ -z "$selected" ]] && return
    local c="${selected:0:1}"
    case "$c" in
        1) bash "$LIB_DIR/monitor.sh" start ;;
        2) bash "$LIB_DIR/monitor.sh" stop ;;
        3) bash "$LIB_DIR/monitor.sh" status ;;
        4) bash "$LIB_DIR/monitor.sh" tail ;;
        5) bash "$LIB_DIR/monitor.sh" monitor ;;
        6) fix_monitor ;;
        0) return ;;
    esac
    echo ""; read -p "按回车返回..." dummy; submenu_monitor
}

submenu_llmswitch() {
    local selected
    selected=$(menu_select "llmswitch 网关代理" \
        "1) 启动" "2) 停止" "3) 重启" "4) 状态" "5) 切换 LLM" "0) 返回")
    [[ -z "$selected" ]] && return
    local c="${selected:0:1}"
    case "$c" in
        1) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --start ;;
        2) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --stop ;;
        3) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --restart ;;
        4) bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --status ;;
        5) bash "$LIB_DIR/init-llm.sh" ;;
        0) return ;;
    esac
    echo ""; read -p "按回车返回..." dummy; submenu_llmswitch
}

submenu_example() {
    section "模板同步"
    bash "$LIB_DIR/example-sync.sh" status
    echo ""
    local choice
    choice=$(menu_select "操作" "d) 查看差异" "f) 正向同步" "r) 反向同步" "0) 返回")
    [[ -z "$choice" ]] && return
    case "${choice:0:1}" in
        d) bash "$LIB_DIR/example-sync.sh" diff ;;
        f) bash "$LIB_DIR/example-sync.sh" promote ;;
        r) bash "$LIB_DIR/example-sync.sh" reverse ;;
        0) return ;;
    esac
}

submenu_bill_token() {
    local selected
    selected=$(menu_select "Bill & Token" \
        "1) Bill (配置模型单价)" \
        "2) 用量统计" \
        "3) 按日报告" \
        "4) 按天归档" \
        "5) 推飞书" \
        "6) timer 管理" \
        "7) 手动触发归档+推飞书" \
        "0) 返回")
    [[ -z "$selected" ]] && return
    local c="${selected:0:1}"
    case "$c" in
        1) bash "$LIB_DIR/init-llm.sh" bill ;;
        2) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --stats ;;
        3) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --report ;;
        4) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ;;
        5)
            local url; url=$(prompt "飞书 URL" "")
            if [[ -n "$url" ]]; then
                bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --feishu "$url"
            else
                bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental
            fi
            ;;
        6) submenu_token_timer ;;
        7) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
        0) return ;;
    esac
    echo ""; read -p "按回车返回..." dummy; submenu_bill_token
}

submenu_token_timer() {
    bash "$CCCONFIG_DIR/option-usage/init.sh" status
    echo ""
    local choice
    choice=$(menu_select "timer 操作" "i) 安装" "u) 卸载" "c) 配置" "b) 返回")
    [[ -z "$choice" ]] && return
    case "${choice:0:1}" in
        i) bash "$CCCONFIG_DIR/option-usage/init.sh" install ;;
        u) bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall ;;
        c) bash "$CCCONFIG_DIR/option-usage/init.sh" config ;;
        b) return ;;
    esac
}

submenu_getnote() {
    local sw="$CCCONFIG_DIR/option-getnote/getnote-switch.sh"
    local init="$CCCONFIG_DIR/option-getnote/init.sh"

    while true; do
        echo ""; section "getnote 账号"
        bash "$sw" --list 2>/dev/null || echo -e "  ${YELLOW}无 getnote 账号${NC}"
        echo ""

        local choice
        choice=$(menu_select "操作" "1) 添加" "2) 删除" "3) 切换(session)" "4) 切换(持久化)" "0) 返回")
        [[ -z "$choice" ]] && break
        local c="${choice:0:1}"
        case "$c" in
            1) bash "$init" add ;;
            2) bash "$init" remove ;;
            3) local t; t=$(prompt "账号名"); [ -n "$t" ] && bash "$sw" "$t" ;;
            4) local t; t=$(prompt "账号名"); [ -n "$t" ] && bash "$sw" "$t" -p ;;
            0) break ;;
        esac
        echo ""; read -p "按回车返回..." dummy
    done
}

# ===== 飞书子菜单 =====
_feishu_list_apps() {
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || true
    [ -z "$conf" ] || [ ! -f "$conf" ] && return 0
    python3 - "$conf" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    for a in json.load(f).get('apps', []):
        print(json.dumps(a, ensure_ascii=False))
PYEOF
}

_feishu_current_account() {
    local m="$HOME/.lark-cli-account"; [ -f "$m" ] && grep '^name=' "$m" | cut -d'=' -f2
}

_feishu_current_profile() {
    [ -f "$HOME/.lark-channel/config.json" ] && python3 -c "import json; print(json.load(open('$HOME/.lark-channel/config.json')).get('activeProfile',''))" 2>/dev/null
}

source "$LIB_DIR/feishu-perms.sh" 2>/dev/null || true

_feishu_perms_menu() {
    local apps; apps="$(_feishu_list_apps)"
    local i=1 labels=()
    echo ""; section "申请 larkbridge 权限"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local n; n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        local lb; lb=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('larkbridge',{}).get('enabled',False))" 2>/dev/null)
        [ "$lb" = "True" ] && { echo "  $((i++))) $n"; labels+=("$n"); }
    done < <(echo "$apps")
    [ ${#labels[@]} -eq 0 ] && { warn "没有启用 larkbridge 的 app"; return 0; }
    local sel; sel=$(menu_select "选择 app" "${labels[@]}" "0) 返回")
    [[ -z "$sel" ]] && return 0
    local c="${sel:0:1}"; [ "$c" = "0" ] && return 0
    local idx=$((c-1)); [ "$idx" -ge 0 ] && [ "$idx" -lt "${#labels[@]}" ] && _feishu_open_perms_for_app "${labels[$idx]}"
    read -p "按回车返回..." dummy
}

submenu_feishu() {
    local feishu_lb="$CCCONFIG_DIR/option-larkbridge/init.sh"
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"

    while true; do
        local lcb_ver; lcb_ver=$(lark-channel-bridge --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        local lcc_ver; lcc_ver=$(lark-cli --version 2>/dev/null | head -1 | sed 's/^[^0-9]*//' || echo "?")
        local cur_acct; cur_acct="$(_feishu_current_account)"
        local cur_prof; cur_prof="$(_feishu_current_profile)"

        echo ""; section "飞书统一管理"
        echo -e "  ${GRAY}lark-cli: v${lcc_ver}    活跃账号: ${cur_acct:-无}${NC}"
        echo -e "  ${GRAY}lark-channel-bridge: v${lcb_ver}    活跃 profile: ${cur_prof:-无}${NC}"
        echo ""

        local choice
        choice=$(menu_select "操作" \
            "1) 飞书账号" \
            "2) lark-cli" \
            "3) larkbridge" \
            "4) 发测试消息" \
            "5) 装 lark-cli" \
            "6) 装 larkbridge" \
            "7) 申请权限" \
            "0) 返回主菜单")
        [[ -z "$choice" ]] && return 0
        local c="${choice:0:1}"
        case "$c" in
            1) submenu_feishu_accounts ;;
            2) submenu_feishu_larkcli ;;
            3) submenu_feishu_larkbridge ;;
            4) _feishu_send_test_message ;;
            5)
                if ! command -v lark-cli &>/dev/null; then bash "$CCCONFIG_DIR/option-larkcli/init.sh"
                else bash "$LIB_DIR/update.sh" lark; fi ;;
            6)
                if ! command -v lark-channel-bridge &>/dev/null; then bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --run 2>&1 | head -5 || true
                else bash "$LIB_DIR/update.sh" larkbridge; fi ;;
            7) _feishu_perms_menu ;;
            0) return 0 ;;
        esac
    done
}

submenu_feishu_larkcli() {
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"

    while true; do
        echo ""; section "lark-cli"
        bash "$feishu_lc" --status
        echo ""
        local choice
        choice=$(menu_select "操作" "a) 重置配置" "k) OAuth 状态" "l) 列出账号" "0) 返回")
        [[ -z "$choice" ]] && return 0
        case "${choice:0:1}" in
            a) bash "$feishu_lc" ;;
            k) bash "$feishu_switch" ;;
            l) bash "$feishu_switch" --list ;;
            0) return 0 ;;
        esac
    done
}

submenu_feishu_larkbridge() {
    local feishu_lb="$CCCONFIG_DIR/option-larkbridge/init.sh"

    while true; do
        echo ""; bash "$feishu_lb" --status 2>&1 | grep -v '^$'
        echo ""
        local choice
        choice=$(menu_select "操作" \
            "1) 前台启动" "2) 后台启动" "3) 停止" "4) 重启" \
            "5) 看日志" "6) 日志目录" \
            "n) 新增 profile" "r) 删除" "d) 设为默认" \
            "0) 返回")
        [[ -z "$choice" ]] && return 0
        local c="${choice:0:1}"
        case "$c" in
            1) bash "$feishu_lb" --run ;;
            2) bash "$feishu_lb" --bg ;;
            3) bash "$feishu_lb" --stop ;;
            4) bash "$feishu_lb" --restart ;;
            5) bash "$feishu_lb" --logs ;;
            6) echo ""; info "日志目录: $HOME/.lark-channel/profiles/"; ls -lt "$HOME/.lark-channel/profiles/"*/logs/*.jsonl 2>/dev/null || warn "暂无日志"; read -p "按回车返回..." dummy ;;
            n|N) bash "$feishu_lb" --profile add ;;
            r|R) bash "$feishu_lb" --profile remove ;;
            d|D) bash "$feishu_lb" --profile default ;;
            0) return 0 ;;
        esac
    done
}

_feishu_default_openid() {
    local prof; prof="$(_feishu_current_profile)"
    [ -z "$prof" ] && return 0
    local root_cfg="$HOME/.lark-channel/config.json"
    [ -f "$root_cfg" ] || return 0
    python3 - "$root_cfg" "$prof" << 'PYEOF' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
users = d.get('profiles',{}).get(sys.argv[2],{}).get('access',{}).get('allowedUsers',[])
if users: print(users[0])
PYEOF
}

_feishu_resolve_recipient() {
    local target="$1"
    local oid; oid="$(_feishu_default_openid)"
    [ -n "$oid" ] && { echo "$oid"; return 0; }
    {
      warn "活跃 profile 没有 allowedUsers"
      echo ""; info "输入你的 open_id（bot 默认只收自己消息）"
    } >&2
    local input_oid; input_oid=$(prompt "open_id")
    [ -z "$input_oid" ] && { warn "跳过" >&2; return 1; }

    local root_cfg="$HOME/.lark-channel/config.json"
    local prof; prof="$(_feishu_current_profile)"
    python3 - "$root_cfg" "$prof" "$input_oid" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
users = d.setdefault('profiles',{}).setdefault(sys.argv[2],{}).setdefault('access',{}).setdefault('allowedUsers',[])
if sys.argv[3] not in users: users.append(sys.argv[3])
with open(sys.argv[1],'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
    {
      good "已写入 allowedUsers"
      local feishu_conf; feishu_conf="$(resolve_conf feishu.json 2>/dev/null)" || true
      if [ -n "$feishu_conf" ] && [ -f "$feishu_conf" ]; then
        python3 - "$feishu_conf" "$target" "$input_oid" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
for a in d.get('apps', []):
    if a.get('name') == sys.argv[2]:
        ids = a.setdefault('larkbridge',{}).setdefault('adminOpenIds',[])
        if sys.argv[3] not in ids: ids.append(sys.argv[3])
        break
with open(sys.argv[1],'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
        good "已回写 feishu.json"
      fi
    } >&2
    echo "$input_oid"
}

_feishu_send_test_message() {
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || { warn "找不到 feishu.json"; return 0; }
    local -a names; local i=1
    echo ""; section "发测试消息"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local n; n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        [ -z "$n" ] && continue
        echo "  $((i++))) $n"; names+=("$n")
    done < <(_feishu_list_apps)
    [ ${#names[@]} -eq 0 ] && { warn "无 app 配置"; return 0; }
    local sel; sel=$(menu_select "选择 app" "${names[@]}")
    [[ -z "$sel" ]] && return 0
    local target="$sel"

    _feishu_send_to_app "$target"
}

_feishu_send_to_app() {
    local target="$1"
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || return 0
    local app_json; app_json=$(python3 - "$conf" "$target" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    for a in json.load(f).get('apps', []):
        if a.get('name') == sys.argv[2]: print(json.dumps(a, ensure_ascii=False)); break
PYEOF
    )
    [ -z "$app_json" ] && { bad "找不到 app: $target"; return 0; }
    local app_id; app_id=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appId'])" 2>/dev/null)
    local app_secret; app_secret=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appSecret'])" 2>/dev/null)
    [[ "$app_id" == *"请填入"* ]] || [[ "$app_secret" == *"请填入"* ]] || [ -z "$app_id" ] || [ -z "$app_secret" ] && { warn "appId/Secret 未配置"; return 0; }

    local oid; oid="$(_feishu_resolve_recipient "$target")"
    [ -n "$oid" ] || return 0
    local msg_text="ccconfig 测试消息 ✅ from $target"
    {
      info "→ $target → $oid: $msg_text"
      confirm "发送？" y || { info "取消"; return 0; }

      local token; token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
      [ -z "$token" ] && { bad "拿 access_token 失败"; return 0; }

      local resp; resp=$(curl -s --connect-timeout 5 --max-time 15 -X POST \
        "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id" \
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        -d "$(python3 -c "import json; print(json.dumps({'receive_id':'$oid','msg_type':'text','content': json.dumps({'text':'$msg_text'})}))")" 2>/dev/null)
      local code; code=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code',-1))" 2>/dev/null)
      [ "$code" = "0" ] && good "已发送" || { warn "发送失败 (code=$code)"; echo "$resp" | python3 -m json.tool 2>/dev/null | sed 's/^/    /'; }
    } >&2
}

submenu_feishu_accounts() {
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || { warn "找不到 feishu.json"; return 0; }

    while true; do
        local cur_acct; cur_acct="$(_feishu_current_account)"
        local -a lines names
        while IFS= read -r line; do [ -n "$line" ] && lines+=("$line"); done < <(_feishu_list_apps)

        echo ""; section "飞书账号"
        echo -e "  ${GRAY}活跃: ${cur_acct:-无}${NC}"; echo ""

        [ ${#lines[@]} -eq 0 ] && {
            warn "无 app 配置"
            if confirm "添加新 app？" y; then bash "$feishu_lc"; fi
            return 0
        }

        local i=1; names=()
        for line in "${lines[@]}"; do
            local n; n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
            names+=("$n")
            echo "  $((i++))) $n $([ "$n" = "$cur_acct" ] && echo '← 活跃')"
        done
        echo ""

        local choice
        choice=$(menu_select "操作" "${names[@]}" "a) 添加" "d) 删除" "0) 返回")
        [[ -z "$choice" ]] && continue
        local c="${choice:0:1}"
        case "$c" in
            0) return 0 ;;
            a) bash "$feishu_lc" ;;
            d)
                local dn; dn=$(prompt "输入要删除的 app 名")
                [ -n "$dn" ] && confirm "确认删除 $dn?" n && {
                    python3 - "$conf" "$dn" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
d['apps'] = [a for a in d.get('apps',[]) if a.get('name') != sys.argv[2]]
with open(sys.argv[1],'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
                    info "已删除"
                }
                ;;
            *)
                [[ "$c" =~ ^[0-9]+$ ]] || continue
                local idx=$((c-1)); [ "$idx" -lt 0 ] || [ "$idx" -ge "${#names[@]}" ] && continue
                local target="${names[$idx]}"
                echo ""; section "应用: $target"
                local sub; sub=$(menu_select "操作" \
                    "1) 切换账号" "2) OAuth 授权" "3) 看授权" "4) 编辑 App ID/Secret" "5) 发测试消息" "0) 返回")
                local sc="${sub:0:1}"
                case "$sc" in
                    1) bash "$feishu_switch" "$target" ;;
                    2) local cd="$HOME/.lark-cli-${target}"; [ -f "${cd}/config.json" ] && LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$feishu_lc" --auth-login "$target" || warn "先编辑 App ID/Secret" ;;
                    3) local cd="$HOME/.lark-cli-${target}"; [ -f "${cd}/config.json" ] && LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>&1 | grep -v '^\[lark-cli\]' | sed 's/^/  /' || warn "config.json 不存在" ;;
                    4) warn "手动: vim $conf" ;;
                    5) _feishu_send_to_app "$target" ;;
                esac
                ;;
        esac
    done
}

# ===== 入口 =====
case "${1:-menu}" in
    menu|"") show_menu ;;
    setup|finalize|first|init) do_finalize ;;
    status) shift; bash "$LIB_DIR/status.sh" "$@" ;;
    self) shift; do_self "${1:-all}" ;;
    upgrade) shift; bash "$LIB_DIR/update.sh" "$@" ;;
    sync) shift; bash "$LIB_DIR/sync.sh" "$@" ;;
    monitor) shift; bash "$LIB_DIR/monitor.sh" "${1:-}" ;;
    deps) bash "$LIB_DIR/deps-check.sh" ;;
    fix) shift; case "${1:-all}" in monitor) fix_monitor ;; all|"") do_finalize ;; *) err "未知 fix 子命令: $1"; exit 1 ;; esac ;;
    example) shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    upgrade-ccprivate|upgrade-ccpriv|ccpriv-upgrade) shift; bash "$LIB_DIR/ccprivate-upgrade.sh" "$@" ;;
    token|usage) shift; bash "$CCCONFIG_DIR/option-usage/token-usage.sh" "$@" ;;
    token-run) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill --include-today ;;
    mcp) shift; bash "$LIB_DIR/mcp-manager.sh" "$@" ;;
    llmswitch|llm-switch|gate) shift; bash "$CCCONFIG_DIR/option-llmswitch/init.sh" "$@" ;;
    llm|llm-init|switch-llm) shift; bash "$LIB_DIR/init-llm.sh" "$@" ;;
    pat|pat-refresh|gh-auth) bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
    test|bootstrap|regression) shift; bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" "$@" ;;
    *) echo "用法: bash maintain-inter.sh [status|self|upgrade|sync|monitor|deps|fix|example|setup|token|pat|mcp|llm|test|menu]"; exit 1 ;;
esac
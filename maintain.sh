#!/bin/bash
# maintain2.sh — ccconfig 运维入口（数据驱动菜单）
#
# 用法：
#   bash maintain2.sh                  # 交互菜单
#   bash maintain2.sh status           # 直接执行子命令
#   bash maintain2.sh fix              # 一键修复
#
# 数据层: menu-data-maintain.sh
# 渲染/解析: interact.sh menu_loop
#

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 保持 maintain2.sh 在 ccconfig 根目录，SCRIPT_DIR 指向根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CCCONFIG_DIR="$SCRIPT_DIR"

source "$LIB_DIR/dry-run.sh"
source "$LIB_DIR/path-helper.sh" 2>/dev/null || true
export PATH="$HOME/.local/bin:$(find_node_bin 2>/dev/null || echo ""):$PATH"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/interact.sh"
source "$LIB_DIR/menu-data-maintain.sh"

# ========== 子菜单函数 ==========

_submenu_monitor() {
    local c; c=$(menu_select "Monitor" \
        "LLM 链路诊断" \
        "状态查看" \
        "启动" \
        "停止" \
        "重启" \
        "修复" \
        "返回")
    [[ -z "$c" || "$c" = "0" ]] && return
    case "$c" in
        1) bash "$SCRIPT_DIR/lib/init-llm.sh" status ;;
        2) bash "$LIB_DIR/monitor.sh" status ;;
        3) bash "$LIB_DIR/monitor.sh" start ;;
        4) bash "$LIB_DIR/monitor.sh" stop ;;
        5) bash "$LIB_DIR/monitor.sh" stop; sleep 1; bash "$LIB_DIR/monitor.sh" start ;;
        6) fix_monitor ;;
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
           case "$ts" in i) bash "$CCCONFIG_DIR/option-usage/init.sh" install;; u) bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall;; c) bash "$CCCONFIG_DIR/option-usage/init.sh" config;; 0|*) return;; esac ;;
        6) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
    esac
}

_submenu_feishu() {
    local c; c=$(menu_select "飞书管理" \
        "飞书账号" \
        "lark-cli" \
        "返回")
    [[ -z "$c" || "$c" = "0" ]] && return
    case "$c" in
        1) _submenu_feishu_accounts ;;
        2) _submenu_feishu_larkcli ;;
    esac
}

_submenu_feishu_accounts() {
    # 从 maintain.sh 搬过来的飞书账号逻辑
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || { warn "找不到 feishu.json"; return 0; }

    local cur_acct=""
    local marker="$HOME/.lark-cli-account"
    [ -f "$marker" ] && cur_acct=$(grep '^name=' "$marker" | cut -d'=' -f2)

    local -a lines names
    while IFS= read -r line; do
        [ -n "$line" ] && lines+=("$line")
    done < <(
        python3 - "$conf" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for a in d.get('apps', []):
    print(json.dumps(a, ensure_ascii=False))
PYEOF
    )

    echo ""
    echo -e "${CYAN}── 飞书账号 (feishu.json apps[]) ──${NC}"
    echo -e "  ${GRAY}活跃账号: ${cur_acct:-无}    配置文件: ${conf}${NC}"
    echo ""

    local i=1
    names=()
    for line in "${lines[@]}"; do
        local name appid desc lc_on lb_on
        IFS=$'\t' read -r name appid desc lc_on lb_on < <(echo "$line" | python3 -c "
import json, sys
a = json.load(sys.stdin)
i = a.get('appId','')
lb = a.get('larkbridge') or a.get('larkBridge') or {}
print('\t'.join([
    a.get('name','?'),
    (i[:14] + '…') if len(i) > 14 else i,
    a.get('description',''),
    'Y' if a.get('larkCli',{}).get('enabled') else 'N',
    'Y' if lb.get('enabled') else 'N',
]))" 2>/dev/null)
        local mark="  "
        [ "$name" = "$cur_acct" ] && mark="${GREEN}← 活跃${NC}"
        local lc_disp="${GRAY}✗ lark-cli${NC}"; [ "$lc_on" = "Y" ] && lc_disp="${GREEN}✓ lark-cli${NC}"
        local lb_disp="${GRAY}✗ larkbridge${NC}"; [ "$lb_on" = "Y" ] && lb_disp="${GREEN}✓ larkbridge${NC}"
        printf "  ${YELLOW}%d)${NC} %-14s appId=${GRAY}%-18s${NC} %b  %b  ${mark}\n" "$i" "$name" "$appid" "$lc_disp" "$lb_disp"
        [ -n "$desc" ] && printf "       ${GRAY}%s${NC}\n" "$desc"
        names+=("$name")
        i=$((i + 1))
    done

    local sel
    if [ ${#names[@]} -eq 0 ]; then
        warn "feishu.json 中无 app 配置"
        sel=$(menu_select "选择" "添加新 app" "返回飞书菜单")
        [[ "$sel" = "0" ]] && return 0
        case "$sel" in 1) bash "$feishu_lc" ;; esac
        return 0
    fi

    sel=$(menu_select "飞书账号" "${names[@]}" "添加" "删除" "返回")
    [[ "$sel" = "0" ]] && return 0
    case "$sel" in
        $((${#names[@]} + 3))) return 0 ;;
        $((${#names[@]} + 1))) bash "$feishu_lc" ;;
        $((${#names[@]} + 2)))
            local dn; dn=$(prompt "要删除的 app 名")
            local found=0
            for n in "${names[@]}"; do [ "$n" = "$dn" ] && found=1 && break; done
            if [ "$found" -eq 1 ] && confirm "确认删除 ${dn}？" n; then
                python3 - "$conf" "$dn" << 'PYEOF'
import json, sys
p, name = sys.argv[1], sys.argv[2]
with open(p) as f: d = json.load(f)
d['apps'] = [a for a in d.get('apps',[]) if a.get('name') != name]
with open(p,'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
                info "已删除"
            fi ;;
        *)
            if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#names[@]} )); then
                local target="${names[$((sel - 1))]}"
                _submenu_feishu_app_menu "$target"
            fi ;;
    esac
}

_submenu_feishu_app_menu() {
    local target="$1"
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || return 0

    echo ""
    echo -e "${CYAN}── 应用: ${target} ──${NC}"
    local sub; sub=$(menu_select "应用: $target" \
        "切换" \
        "OAuth" \
        "看授权" \
        "编辑" \
        "发测试" \
        "返回")
    [[ "$sub" = "0" ]] && return 0
    case "$sub" in
        1) bash "$feishu_switch" "$target" ;;
        2)
            local cd="$HOME/.lark-cli-${target}"
            if [ -f "${cd}/config.json" ]; then
                LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$feishu_lc" --auth-login "$target"
            else
                warn "先选 4 编辑 App ID/Secret，再走 lark-cli init"
            fi ;;
        3)
            local cd="$HOME/.lark-cli-${target}"
            if [ -f "${cd}/config.json" ]; then
                LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>&1 \
                    | grep -v '^\[lark-cli\]' | sed 's/^/  /'
            else
                warn "config.json 不存在"
            fi ;;
        4) warn "手动编辑: vim $conf" ;;
        5) _submenu_feishu_send_test "$target" ;;
    esac
}

_submenu_feishu_larkcli() {
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"

    echo ""
    echo -e "${CYAN}── lark-cli ──${NC}"
    bash "$feishu_lc" --status
    echo ""
    local sub; sub=$(menu_select "lark-cli" \
        "重置配置" \
        "OAuth 状态" \
        "列出账号" \
        "返回")
    [[ "$sub" = "0" ]] && return 0
    case "$sub" in
        1) bash "$feishu_lc" ;;
        2) bash "$feishu_switch" ;;
        3) bash "$feishu_switch" --list ;;
    esac
}

_submenu_feishu_send_test() {
    local target="$1"
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || return 0
    local app_json
    app_json=$(python3 - "$conf" "$target" << 'PYEOF' 2>/dev/null
import json, sys
p, name = sys.argv[1], sys.argv[2]
with open(p) as f: d = json.load(f)
for a in d.get('apps', []):
    if a.get('name') == name:
        print(json.dumps(a, ensure_ascii=False))
        break
PYEOF
    )
    [ -z "$app_json" ] && { bad "找不到 app: $target"; return 0; }
    local app_id; app_id=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appId'])" 2>/dev/null)
    local app_secret; app_secret=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appSecret'])" 2>/dev/null)

    if [[ "$app_id" == *"请填入"* ]] || [[ "$app_secret" == *"请填入"* ]] || [ -z "$app_id" ] || [ -z "$app_secret" ]; then
        warn "appId/appSecret 未配置"
        return 0
    fi

    local oid rc
    # 解析收件人
    local root_cfg="$HOME/.lark-channel/config.json"
    oid=""
    [ -f "$root_cfg" ] && oid=$(python3 - "$root_cfg" << 'PYEOF' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
prof = d.get('config', {}).get('activeProfile', '') or list(d.get('profiles', {}).keys())[0]
p = d.get('profiles', {}).get(prof, {})
users = p.get('access', {}).get('allowedUsers', [])
if users: print(users[0])
PYEOF
    )

    [ -z "$oid" ] && { warn "取消（未设置收件人）"; return 0; }

    local msg_text="ccconfig 飞书测试消息 ✅ from $target"
    echo ""
    info "  → 目标 app: $target"
    info "  → 收件人: $oid"
    info "  → 内容: $msg_text"
    confirm "发送？" y || { info "取消"; return 0; }

    info "  拿 tenant_access_token..." >&2
    local token
    token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
    [ -z "$token" ] && { warn "  拿 access_token 失败"; return 0; }

    info "  发消息..." >&2
    local body
    body=$(python3 -c "
import json, sys
print(json.dumps({'receive_id': sys.argv[1], 'msg_type':'text', 'content': json.dumps({'text': sys.argv[2]})}, ensure_ascii=False))
" "$oid" "$msg_text")
    local resp
    resp=$(curl -s --connect-timeout 5 --max-time 15 -X POST \
        "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null)
    local code msg_id
    code=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code',-1))" 2>/dev/null)
    msg_id=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('message_id',''))" 2>/dev/null)
    if [ "$code" = "0" ]; then
        good "  ✅ 已发送（message_id: ${msg_id:-?}）"
    else
        warn "  发送失败"
        local err_msg; err_msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('msg',''))" 2>/dev/null || echo "")
        [ -n "$err_msg" ] && echo "    $err_msg"
    fi
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

    if [ -x "$LIB_DIR/example-sync.sh" ]; then
        section "3. Example 模板同步"
        bash "$LIB_DIR/example-sync.sh" sync 2>/dev/null && ok "模板已同步" || warn "模板同步跳过"
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

case "${1:-menu}" in
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
        local ccbridge_test="${CCBRIDGE_HOME:-$HOME/git/ccbridge}/tests/test-feishu.sh"
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
        echo "用法: bash maintain2.sh [status|self|upgrade|sync|monitor|deps|fix|...]"
        exit 1 ;;
esac

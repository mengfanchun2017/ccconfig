# menu-feishu.sh — 飞书子菜单（从 maintain.sh 抽出）
#
# 依赖: colors.sh, interact.sh（调用方已 source）
# 在 maintain.sh 中 source 后调用 _submenu_feishu

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

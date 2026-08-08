#!/bin/bash
# lib/feishu-perms.sh — 飞书 larkbridge 必备权限申请 + 检测
#
# 用途：被 option-larkbridge/init.sh 和 maintain.sh 共用
# 功能：
#   _feishu_open_perms_url <app_id>    输出飞书开放平台一键申请 URL
#   _feishu_open_perms_for_app <name>  显示清单 + 自动调浏览器
#   _feishu_check_perms <id> <secret>  检测应用当前缺哪些 scope（99991672 错误码）
#
# 调用方需已 source colors.sh（提供 info/warn/good）

# larkbridge 必备 tenant scopes（合并用户导出 + 错误日志实测）
# 来源：ccprivate 导出的 5 个 + bridge 日志 99991672 报缺 4 个
_LCB_TENANT_SCOPES="im:message,im:message:send,im:message:send_as_bot,im:message:send_multi_depts,im:message:send_multi_users,im:message:send_sys_msg,im:message.p2p_msg:readonly,im:message.reactions:write_only,im:chat:readonly,admin:app.info:readonly,application:application:self_manage,cardkit:card:write"

# 一键申请 URL（飞书开放平台会预选这些 scope）
_feishu_open_perms_url() {
    local app_id="$1"
    echo "https://open.feishu.cn/app/${app_id}/auth?q=${_LCB_TENANT_SCOPES}&op_from=openapi&token_type=tenant"
}

# 显示清单 + 自动打开浏览器
# 用法: _feishu_open_perms_for_app <app_name> [app_id]
_feishu_open_perms_for_app() {
    local target="$1"
    local app_id="${2:-}"

    if [ -z "$app_id" ]; then
        # 自动从 ccprivate feishu.json 读
        local feishu_conf
        feishu_conf="$(resolve_conf feishu.json 2>/dev/null)" || true
        if [ -z "$feishu_conf" ] || [ ! -f "$feishu_conf" ]; then
            warn "找不到 feishu.json"
            return 1
        fi
        app_id=$(python3 - "$feishu_conf" "$target" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
for a in d.get('apps', []):
    if a.get('name') == sys.argv[2]:
        print(a.get('appId','')); break
PYEOF
)
    fi

    if [[ "$app_id" == *"请填入"* ]] || [ -z "$app_id" ]; then
        warn "appId 未配置: $target"
        return 1
    fi

    local url; url="$(_feishu_open_perms_url "$app_id")"
    echo ""
    info "app: $target (appId=$app_id)"
    info "必备权限 (lark-channel-bridge):"
    echo "  接收事件:"
    echo "    • im:message              — 接收用户消息事件"
    echo "  发送消息 (任一即可):"
    echo "    • im:message:send              — app 身份发消息"
    echo "    • im:message:send_as_bot       — bot 主动发消息"
    echo "    • im:message:send_multi_depts  — 多部门批量发"
    echo "    • im:message:send_multi_users  — 多用户批量发"
    echo "    • im:message:send_sys_msg      — 系统消息"
    echo "    • im:message.p2p_msg:readonly  — p2p 消息读取"
    echo "  消息功能:"
    echo "    • im:message.reactions:write_only — 写消息表情回应"
    echo "    • cardkit:card:write              — 写消息卡片"
    echo "  资源访问:"
    echo "    • im:chat:readonly                — 读群列表"
    echo "    • admin:app.info:readonly         — 读 app 自身信息"
    echo "    • application:application:self_manage — 列 scopes"
    echo ""
    info "申请 URL（飞书开放平台已预选权限）："
    echo -e "  ${CYAN}${url}${NC}"
    echo ""
    info "提醒：开通后必须创建版本并发布，否则线上不生效"

    # 自动打开浏览器
    local opener
    if command -v xdg-open &>/dev/null; then
        opener="xdg-open"
    elif command -v wslview &>/dev/null; then
        opener="wslview"
    elif command -v open &>/dev/null; then
        opener="open"
    elif command -v cmd.exe &>/dev/null; then
        opener="wsl_cmd"
    elif command -v powershell.exe &>/dev/null; then
        opener="wsl_powershell"
    else
        warn "找不到浏览器命令（xdg-open/wslview/open/cmd.exe）"
        warn "手动复制上面的 URL 到浏览器"
        return 0
    fi
    case "$opener" in
        wsl_cmd)       cmd.exe /c start "" "$url" &>/dev/null ;;
        wsl_powershell) powershell.exe /c "Start-Process '$url'" &>/dev/null ;;
        *)             "$opener" "$url" &>/dev/null ;;
    esac
    if [ $? -eq 0 ]; then
        good "✓ 浏览器已打开（${opener}）"
        info "勾选权限 → 「申请开通」→ 创建版本 → 发布到线上"
    else
        warn "${opener} 打开失败，手动复制 URL"
    fi
}

# 检测当前应用缺哪些 scope
# 返回 0 = 全部 OK，1 = 缺权限（输出缺哪些）
# 用法: _feishu_check_perms <app_id> <app_secret>
_feishu_check_perms() {
    local app_id="$1" app_secret="$2"
    local token
    token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
    [ -z "$token" ] && { echo "ERR: 取 token 失败"; return 2; }

    # 用一个低风险的读操作探测：im/v1/chats（读群列表）
    local resp
    resp=$(curl -s --connect-timeout 5 --max-time 10 \
        "https://open.feishu.cn/open-apis/im/v1/chats?page_size=1" \
        -H "Authorization: Bearer $token" 2>/dev/null)
    local code
    code=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code',-1))" 2>/dev/null)

    if [ "$code" = "0" ]; then
        return 0
    fi

    # 提取 99991672 错误里要求的 scope
    local missing
    missing=$(echo "$resp" | python3 -c "
import json, sys, re
d = json.load(sys.stdin)
msg = d.get('msg', '')
m = re.search(r'required: \[([^\]]+)\]', msg)
if m:
    print(','.join(s.strip().strip('\"').strip() for s in m.group(1).split(',')))
" 2>/dev/null)
    echo "MISSING: $missing"
    return 1
}
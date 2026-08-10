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

# 权限组：组内「任一即可」，组间必须都满足
# 分隔：组用 ;，组内 scope 用 ,，scope 与中文说明用 =
# 来源：bridge 日志 99991672 的 "One of the following scopes is required: [...]" 实测分组
_LCB_SCOPE_GROUPS="im:message:send,im:message,im:message:send_as_bot=发消息;im:message,im:message.reactions:write_only=消息表情回应;im:chat:readonly,im:chat,im:chat:read=读群列表;admin:app.info:readonly,application:application:self_manage=读 app 自身信息;cardkit:card:write=流式卡片（markdown 流式输出必需）"

# _feishu_check_perms 检测后写入：缺的 scope（逗号分隔，每组取首选）
_LCB_MISSING_SCOPES=""

# 一键申请 URL（飞书开放平台会预选这些 scope）
# 用法: _feishu_open_perms_url <app_id> [scopes_csv]  省略 scopes 则预选全部必备
_feishu_open_perms_url() {
    local app_id="$1"
    local scopes="${2:-$_LCB_TENANT_SCOPES}"
    echo "https://open.feishu.cn/app/${app_id}/auth?q=${scopes}&op_from=openapi&token_type=tenant"
}

# 显示清单 + 自动打开浏览器
# 用法: _feishu_open_perms_for_app <app_name> [app_id] [missing_scopes_csv]
#   给了 missing_scopes_csv 则 URL 只预选缺的那几项，不给则预选全部必备
_feishu_open_perms_for_app() {
    local target="$1"
    local app_id="${2:-}"
    local missing="${3:-}"

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

    local url; url="$(_feishu_open_perms_url "$app_id" "$missing")"
    echo ""
    info "app: $target (appId=$app_id)"
    if [ -n "$missing" ]; then
        info "只缺这些（URL 已只预选它们）："
        echo "  ${missing//,/$'\n  '}" | sed 's/^/    • /'
    else
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
        echo "    • cardkit:card:write              — 流式卡片（markdown 流式输出必需）"
        echo "  资源访问:"
        echo "    • im:chat:readonly                — 读群列表"
        echo "    • admin:app.info:readonly         — 读 app 自身信息"
        echo "    • application:application:self_manage — 列 scopes"
    fi
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
# 返回 0 = 全部 OK，1 = 缺权限，2 = 检测失败（ERR: 开头）
# 缺权限时 stdout 最后一行是 MISSING:<csv>，调用方自己 sed 提取
# （不能用全局变量回传——调用方都是 $(...) 子 shell，赋值出不来）
# 用法: result="$(_feishu_check_perms <id> <secret>)"; rc=$?
_feishu_check_perms() {
    local app_id="$1" app_secret="$2"
    local token
    token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
    [ -z "$token" ] && { echo "ERR: 取 token 失败"; return 2; }

    # 直接列 app 已开通的 scope，逐组比对
    # 不能只探单个接口——旧版只探 im/v1/chats，im:chat:readonly 一过就报「权限齐全」，
    # 结果 cardkit:card:write 缺失直到发消息才 400（99991672）
    local resp
    resp=$(curl -s --connect-timeout 5 --max-time 10 \
        "https://open.feishu.cn/open-apis/application/v6/scopes" \
        -H "Authorization: Bearer $token" 2>/dev/null)

    local out rc
    out=$(_LCB_RESP="$resp" python3 - "$_LCB_SCOPE_GROUPS" "$_LCB_TENANT_SCOPES" <<'PYEOF'
import json, os, sys
groups_raw, all_scopes = sys.argv[1], sys.argv[2]
try:
    d = json.loads(os.environ['_LCB_RESP'])
except Exception:
    print("ERR: scopes 接口返回不可解析"); sys.exit(2)

if d.get('code') != 0:
    # 连 scopes 接口都调不动 → 缺 admin:app.info:readonly / application:application:self_manage
    print("ERR: 读权限列表失败 (%s) %s" % (d.get('code'), d.get('msg','')))
    print("MISSING:" + all_scopes)
    sys.exit(2)

granted = {s['scope_name'] for s in d.get('data', {}).get('scopes', [])
           if s.get('scope_type') == 'tenant' and s.get('grant_status') == 1}

missing = []
for g in groups_raw.split(';'):
    scopes, _, label = g.partition('=')
    alts = scopes.split(',')
    if not any(a in granted for a in alts):
        missing.append((alts[0], label, alts))

if not missing:
    print("OK: 已开通 %d 个 tenant scope，必备权限组全覆盖" % len(granted))
    sys.exit(0)

print("缺 %d 项（每项组内任一即可）:" % len(missing))
for first, label, alts in missing:
    print("  ✗ %s → %s" % (label, ' 或 '.join(alts)))
print("MISSING:" + ','.join(m[0] for m in missing))
sys.exit(1)
PYEOF
)
    rc=$?
    [ $rc -eq 0 ] || echo "$out"
    return $rc
}
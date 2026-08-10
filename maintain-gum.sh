#!/bin/bash
# maintain-gum.sh — ccconfig 运维入口（gum 原生版）
#
# 与 maintain.sh 功能一致，但整体 UI 用 gum 的 TUI 部件
# 不依赖 colors.sh/interact.sh，直接调 gum
#
# 前置: gum 已安装
# 用法:
#   bash maintain-gum.sh              # 交互菜单
#   bash maintain-gum.sh status       # 直跑子命令

set -euo pipefail

if ! command -v gum &>/dev/null; then
    echo "❌ gum 未装，先: bash lib/option-*/init.sh 安装"
    echo "   或: sudo apt install gum（需 sudo）"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CCCONFIG_DIR="$SCRIPT_DIR"

source "$LIB_DIR/path-helper.sh" 2>/dev/null || true
export PATH="$HOME/.local/bin:$(find_node_bin 2>/dev/null || echo ""):$PATH"

# gum 风格的日志辅助（不依赖 colors.sh）
_section() { echo ""; gum style --border normal --padding "0 1" --margin "0 0" --foreground 99 " $1 "; }
_ok() { gum style --foreground 42 "  ✓ $1"; }
_err() { gum style --foreground 196 "  ✗ $1"; }
_warn() { gum style --foreground 214 "  ⚠ $1"; }
_info() { gum style --foreground 245 "  $1"; }
clear=""

# ===== 收尾 =====
do_finalize() {
    gum style --border double --padding "1 2" --foreground 99 "ccconfig 收尾 — 链接修复 + 状态检查 + 服务启动"
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"

    _section "1. 修复符号链接"
    local ccprivate_setup="$ccpriv/setup.sh"
    if [[ -x "$ccprivate_setup" ]]; then
        bash "$ccprivate_setup" 2>/dev/null && _ok "符号链接已修复" || _warn "符号链接部分失败"
    else
        bash "$LIB_DIR/setup-links.sh"; _info "仅修复了公开链接"
    fi

    local expected_dirs=("skill-config" "rules" "agents" "commands" "bin") created=false
    for d in "${expected_dirs[@]}"; do
        if [[ ! -d "$ccpriv/$d" ]]; then
            mkdir -p "$ccpriv/$d"; touch "$ccpriv/$d/.gitkeep"; created=true
        fi
    done; $created && _ok "缺失目录已补齐"

    _section "2. 启动 auto-sync"
    bash "$LIB_DIR/init-autostart.sh" enable 2>/dev/null && _ok "已启动" || _warn "启动失败"

    _section "3. 模板同步"
    [ -x "$LIB_DIR/example-sync.sh" ] && bash "$LIB_DIR/example-sync.sh" sync 2>/dev/null && _ok "已同步" || _warn "跳过"

    _section "4. 状态总览"
    bash "$LIB_DIR/status.sh" --quick

    echo ""
    gum style --border double --padding "1 2" --foreground 42 "ccconfig 就绪 🎉"
    echo "  bash maintain-gum.sh          # 交互菜单"
    echo "  bash maintain-gum.sh status   # 状态"
}

# ===== Monitor 修复 =====
fix_monitor() {
    _section "Monitor 修复"
    source "$LIB_DIR/install-inotify.sh"
    install_inotify || { _err "inotify-tools 装不上"; return 1; }
    bash "$LIB_DIR/monitor.sh" stop 2>/dev/null; pkill -f "inotifywait.*$HOME/git" 2>/dev/null || true
    bash "$LIB_DIR/monitor.sh" start && { _ok "已修复并重启"; bash "$LIB_DIR/monitor.sh" status; } || { _err "启动失败"; return 1; }
}

# ===== 自我更新 =====
do_self() {
    local target="${1:-all}"
    case "$target" in
        cc|ccconfig)
            _section "ccconfig 自更新"
            git -C "$SCRIPT_DIR" fetch origin main 2>/dev/null || { _warn "无法连接远程"; return 1; }
            local before=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)
            git -C "$SCRIPT_DIR" pull --ff-only origin main 2>/dev/null && {
                local after=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
                [ "$before" != "$after" ] && _ok "$before → $after" || _ok "已是最新: $before"
            } || { _warn "拉取失败"; return 1; }
            bash "$LIB_DIR/setup-links.sh"
            ;;
        skill) _section "Skill 同步"; bash "$LIB_DIR/init-skill.sh" sync ;;
        all|"") do_self cc; echo ""; do_self skill ;;
        *) _err "未知 self: $target"; return 1 ;;
    esac
}

# ===== 主菜单（gum filter）=====
show_menu() {
    local items=(
        "status      状态检查"
        "monitor     Monitor 管理"
        "self        自我更新"
        "sync        Git 同步"
        "upgrade     组件升级"
        "deps        依赖检查"
        "setup       一键修复"
        "example     模板同步"
        "ccpriv-up   ccprivate 升级"
        "bill        Bill & Token"
        "mcp         MCP 管理"
        "llmswitch   llmswitch"
        "feishu      飞书管理"
        "test        回归测试"
        "pat         GitHub PAT"
        "llm         LLM 切换"
        "getnote     getnote 账号"
        "exit        退出"
    )

    local selected
    selected=$(gum filter --header "ccconfig 运维中心" --placeholder "搜索或选择..." --width 60 "${items[@]}" 2>/dev/null) || { echo ""; exit 0; }
    local cmd="${selected%% *}"

    case "$cmd" in
        exit) echo ""; exit 0 ;;
        status) bash "$LIB_DIR/status.sh" ;;
        monitor) submenu_monitor ;;
        self) do_self all ;;
        sync) bash "$LIB_DIR/sync.sh" ;;
        upgrade) bash "$LIB_DIR/update.sh" menu ;;
        deps) bash "$LIB_DIR/deps-check.sh" ;;
        setup) do_finalize ;;
        example|ccpriv-up|bill|mcp|llmswitch|feishu|test|pat|llm|getnote)
            submenu_dispatch "$cmd" ;;
        *) _warn "未知: $selected"; ;;
    esac

    echo ""; read -p "按回车返回菜单..." dummy; show_menu
}

submenu_dispatch() {
    case "$1" in
        example)
            bash "$LIB_DIR/example-sync.sh" status; echo ""
            local a; a=$(gum choose "查看差异" "正向同步" "反向同步" "返回" 2>/dev/null)
            case "$a" in "查看差异") bash "$LIB_DIR/example-sync.sh" diff;; "正向同步") bash "$LIB_DIR/example-sync.sh" promote;; "反向同步") bash "$LIB_DIR/example-sync.sh" reverse;; esac ;;
        bill) submenu_bill_token ;;
        mcp) bash "$LIB_DIR/mcp-manager.sh" config ;;
        llmswitch) submenu_llmswitch ;;
        feishu) submenu_feishu ;;
        test) bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" ;;
        pat) bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
        llm) bash "$LIB_DIR/init-llm.sh" ;;
        getnote) submenu_getnote ;;
    esac
}

submenu_monitor() {
    local a; a=$(gum choose "启动" "停止" "看状态" "实时追踪" "文件变更" "修复" "返回" 2>/dev/null)
    case "$a" in "启动") bash "$LIB_DIR/monitor.sh" start;; "停止") bash "$LIB_DIR/monitor.sh" stop;; "看状态") bash "$LIB_DIR/monitor.sh" status;; "实时追踪") bash "$LIB_DIR/monitor.sh" tail;; "文件变更") bash "$LIB_DIR/monitor.sh" monitor;; "修复") fix_monitor;; esac
    echo ""; read -p "按回车返回..." dummy; submenu_monitor
}

submenu_llmswitch() {
    local a; a=$(gum choose "启动" "停止" "重启" "状态" "切换 LLM" "返回" 2>/dev/null)
    case "$a" in "启动") bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --start;; "停止") bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --stop;; "重启") bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --restart;; "状态") bash "$CCCONFIG_DIR/option-llmswitch/init.sh" --status;; "切换 LLM") bash "$LIB_DIR/init-llm.sh";; esac
    echo ""; read -p "按回车返回..." dummy; submenu_llmswitch
}

submenu_bill_token() {
    local a
    a=$(gum choose "Bill 配置" "用量统计" "按日报告" "按天归档" "推飞书" "timer 管理" "手动触发" "返回" 2>/dev/null)
    case "$a" in
        "Bill 配置") bash "$LIB_DIR/init-llm.sh" bill ;;
        "用量统计") bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --stats ;;
        "按日报告") bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --report ;;
        "按天归档") bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ;;
        "推飞书") local url=$(gum input --placeholder "飞书 URL"); bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental ${url:+--feishu "$url"} ;;
        "timer 管理") submenu_token_timer ;;
        "手动触发") bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill ;;
    esac
    echo ""; read -p "按回车返回..." dummy; submenu_bill_token
}

submenu_token_timer() {
    bash "$CCCONFIG_DIR/option-usage/init.sh" status; echo ""
    local a; a=$(gum choose "安装 timer" "卸载 timer" "配置" "返回" 2>/dev/null)
    case "$a" in "安装 timer") bash "$CCCONFIG_DIR/option-usage/init.sh" install;; "卸载 timer") bash "$CCCONFIG_DIR/option-usage/init.sh" uninstall;; "配置") bash "$CCCONFIG_DIR/option-usage/init.sh" config;; esac
}

submenu_getnote() {
    local sw="$CCCONFIG_DIR/option-getnote/getnote-switch.sh"
    local init="$CCCONFIG_DIR/option-getnote/init.sh"
    while true; do
        _section "getnote 账号"
        bash "$sw" --list 2>/dev/null || gum style --foreground 214 "  无 getnote 账号"
        echo ""
        local a; a=$(gum choose "添加" "删除" "切换(session)" "切换(持久化)" "返回" 2>/dev/null)
        case "$a" in
            "添加") bash "$init" add ;;
            "删除") bash "$init" remove ;;
            "切换(session)") local t=$(gum input --placeholder "账号名"); [ -n "$t" ] && bash "$sw" "$t" ;;
            "切换(持久化)") local t=$(gum input --placeholder "账号名"); [ -n "$t" ] && bash "$sw" "$t" -p ;;
            "返回") break ;;
        esac
        echo ""; read -p "按回车返回..." dummy
    done
}

submenu_feishu() {
    local feishu_lb="$CCCONFIG_DIR/option-larkbridge/init.sh"
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"

    while true; do
        _section "飞书统一管理"
        local a; a=$(gum choose \
            "账号管理" "lark-cli" "larkbridge" "发测试消息" "装 lark-cli" "装 larkbridge" "申请权限" "返回主菜单" 2>/dev/null)
        case "$a" in
            "账号管理") submenu_feishu_accounts ;;
            "lark-cli") submenu_feishu_larkcli ;;
            "larkbridge") submenu_feishu_larkbridge ;;
            "发测试消息") _feishu_send_test_message ;;
            "装 lark-cli") command -v lark-cli &>/dev/null && bash "$LIB_DIR/update.sh" lark || bash "$CCCONFIG_DIR/option-larkcli/init.sh" ;;
            "装 larkbridge") command -v lark-channel-bridge &>/dev/null && bash "$LIB_DIR/update.sh" larkbridge || bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --run 2>&1 | head -5 || true ;;
            "申请权限") _feishu_perms_menu ;;
            "返回主菜单") return 0 ;;
        esac
    done
}

submenu_feishu_larkcli() {
    while true; do
        _section "lark-cli"
        bash "$CCCONFIG_DIR/option-larkcli/init.sh" --status; echo ""
        local a; a=$(gum choose "重置配置" "OAuth 状态" "列出账号" "返回" 2>/dev/null)
        case "$a" in "重置配置") bash "$CCCONFIG_DIR/option-larkcli/init.sh";; "OAuth 状态") bash "$CCCONFIG_DIR/option-larkcli/lark-switch.sh";; "列出账号") bash "$CCCONFIG_DIR/option-larkcli/lark-switch.sh" --list;; "返回") return 0;; esac
    done
}

submenu_feishu_larkbridge() {
    while true; do
        echo ""; bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --status 2>&1 | grep -v '^$'; echo ""
        local a; a=$(gum choose "前台启动" "后台启动" "停止" "重启" "看日志" "日志目录" "新增profile" "删除" "设为默认" "返回" 2>/dev/null)
        case "$a" in
            "前台启动") bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --run;;
            "后台启动") bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --bg;;
            "停止") bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --stop;;
            "重启") bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --restart;;
            "看日志") bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --logs;;
            "日志目录") echo ""; ls -lt "$HOME/.lark-channel/profiles/"*/logs/*.jsonl 2>/dev/null || echo "  暂无日志"; read -p "按回车返回..." dummy;;
            "新增profile") bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --profile add;;
            "删除") bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --profile remove;;
            "设为默认") bash "$CCCONFIG_DIR/option-larkbridge/init.sh" --profile default;;
            "返回") return 0;;
        esac
    done
}

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

source "$LIB_DIR/feishu-perms.sh" 2>/dev/null || true

_feishu_perms_menu() {
    local apps; apps="$(_feishu_list_apps)"
    local labels=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local n; n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        local lb; lb=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('larkbridge',{}).get('enabled',False))" 2>/dev/null)
        [ "$lb" = "True" ] && labels+=("$n")
    done < <(echo "$apps")
    [ ${#labels[@]} -eq 0 ] && { _warn "没有启用 larkbridge 的 app"; return 0; }
    local sel; sel=$(gum choose --header "选择 app" "${labels[@]}" 2>/dev/null) || return 0
    _feishu_open_perms_for_app "$sel"
    read -p "按回车返回..." dummy
}

_feishu_default_openid() {
    local prof; prof="$(_feishu_current_account)"
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
    _warn "活跃 profile 没有 allowedUsers" >&2
    local input_oid; input_oid=$(gum input --placeholder "输入 open_id" 2>/dev/null)
    [ -z "$input_oid" ] && { _warn "跳过" >&2; return 1; }
    local root_cfg="$HOME/.lark-channel/config.json"
    local prof; prof="$(_feishu_current_account)"
    python3 - "$root_cfg" "$prof" "$input_oid" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
users = d.setdefault('profiles',{}).setdefault(sys.argv[2],{}).setdefault('access',{}).setdefault('allowedUsers',[])
if sys.argv[3] not in users: users.append(sys.argv[3])
with open(sys.argv[1],'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
    _ok "已写入 allowedUsers" >&2
    echo "$input_oid"
}

_feishu_send_test_message() {
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || { _warn "找不到 feishu.json"; return 0; }
    local -a names
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local n; n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        [ -z "$n" ] || names+=("$n")
    done < <(_feishu_list_apps)
    [ ${#names[@]} -eq 0 ] && { _warn "无 app 配置"; return 0; }
    local target; target=$(gum choose --header "选择 app" "${names[@]}" 2>/dev/null) || return 0
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
    [ -z "$app_json" ] && { _err "找不到 app: $target"; return 0; }
    local app_id; app_id=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appId'])" 2>/dev/null)
    local app_secret; app_secret=$(echo "$app_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['appSecret'])" 2>/dev/null)
    [[ "$app_id" == *"请填入"* ]] || [[ "$app_secret" == *"请填入"* ]] || [ -z "$app_id" ] || [ -z "$app_secret" ] && { _warn "appId/Secret 未配置"; return 0; }

    local oid; oid="$(_feishu_resolve_recipient "$target")"
    [ -n "$oid" ] || return 0
    local msg_text="ccconfig 测试 ✅ from $target"
    {
      _info "→ $target → $oid: $msg_text"
      gum confirm "发送？" 2>/dev/null || { _info "取消"; return 0; }
      local token; token=$(curl -s --connect-timeout 5 --max-time 10 -X POST \
        "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
        -H "Content-Type: application/json" \
        -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
      [ -z "$token" ] && { _err "拿 access_token 失败"; return 0; }
      local resp; resp=$(curl -s --connect-timeout 5 --max-time 15 -X POST \
        "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id" \
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        -d "$(python3 -c "import json; print(json.dumps({'receive_id':'$oid','msg_type':'text','content': json.dumps({'text':'$msg_text'})}))")" 2>/dev/null)
      local code; code=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code',-1))" 2>/dev/null)
      [ "$code" = "0" ] && _ok "已发送" || { _warn "发送失败 (code=$code)"; echo "$resp" | python3 -m json.tool 2>/dev/null | sed 's/^/    /'; }
    } >&2
}

submenu_feishu_accounts() {
    local feishu_lc="$CCCONFIG_DIR/option-larkcli/init.sh"
    local feishu_switch="$CCCONFIG_DIR/option-larkcli/lark-switch.sh"
    local conf; conf="$(resolve_conf feishu.json 2>/dev/null)" || { _warn "找不到 feishu.json"; return 0; }

    while true; do
        local cur_acct; cur_acct="$(_feishu_current_account)"
        local -a lines names
        while IFS= read -r line; do [ -n "$line" ] && lines+=("$line"); done < <(_feishu_list_apps)
        _section "飞书账号 (feishu.json)"

        [ ${#lines[@]} -eq 0 ] && {
            _warn "无 app 配置"; gum confirm "添加新 app？" 2>/dev/null && bash "$feishu_lc"
            return 0
        }

        names=(); local i=1
        for line in "${lines[@]}"; do
            local n; n=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
            names+=("$n")
        done

        local sel; sel=$(gum choose --header "活跃: ${cur_acct:-无}" "${names[@]}" "添加 app" "删除 app" "返回" 2>/dev/null) || break
        case "$sel" in
            "添加 app") bash "$feishu_lc" ;;
            "删除 app")
                local dn; dn=$(gum input --placeholder "输入要删除的 app 名" 2>/dev/null)
                [ -n "$dn" ] && gum confirm "确认删除 $dn?" 2>/dev/null && {
                    python3 - "$conf" "$dn" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
d['apps'] = [a for a in d.get('apps',[]) if a.get('name') != sys.argv[2]]
with open(sys.argv[1],'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
                    _ok "已删除"
                }
                ;;
            "返回") break ;;
            *)
                local target="$sel"
                _section "应用: $target"
                local sub; sub=$(gum choose "切换账号" "OAuth 授权" "看授权状态" "编辑 App ID/Secret" "发测试消息" "返回" 2>/dev/null)
                case "$sub" in
                    "切换账号") bash "$feishu_switch" "$target" ;;
                    "OAuth 授权") local cd="$HOME/.lark-cli-${target}"; [ -f "${cd}/config.json" ] && LARKSUITE_CLI_CONFIG_DIR="$cd" bash "$feishu_lc" --auth-login "$target" || _warn "先编辑 App ID/Secret" ;;
                    "看授权状态") local cd="$HOME/.lark-cli-${target}"; [ -f "${cd}/config.json" ] && LARKSUITE_CLI_CONFIG_DIR="$cd" lark-cli auth status 2>&1 | grep -v '^\[lark-cli\]' | sed 's/^/  /' || _warn "config.json 不存在" ;;
                    "编辑 App ID/Secret") _warn "手动编辑: vim $conf" ;;
                    "发测试消息") _feishu_send_to_app "$target" ;;
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
    fix) shift; case "${1:-all}" in monitor) fix_monitor ;; all|"") do_finalize ;; *) _err "未知 fix 子命令: $1"; exit 1 ;; esac ;;
    example) shift; bash "$LIB_DIR/example-sync.sh" "$@" ;;
    upgrade-ccprivate|upgrade-ccpriv|ccpriv-upgrade) shift; bash "$LIB_DIR/ccprivate-upgrade.sh" "$@" ;;
    token|usage) shift; bash "$CCCONFIG_DIR/option-usage/token-usage.sh" "$@" ;;
    token-run) bash "$CCCONFIG_DIR/option-usage/token-usage.sh" --by-day --incremental --auto-backfill --include-today ;;
    mcp) shift; bash "$LIB_DIR/mcp-manager.sh" "$@" ;;
    llmswitch|llm-switch|gate) shift; bash "$CCCONFIG_DIR/option-llmswitch/init.sh" "$@" ;;
    llm|llm-init|switch-llm) shift; bash "$LIB_DIR/init-llm.sh" "$@" ;;
    pat|pat-refresh|gh-auth) bash "$CCCONFIG_DIR/bin/refresh-gh-auth.sh" ;;
    test|bootstrap|regression) shift; bash "$CCCONFIG_DIR/bin/test-bootstrap.sh" "$@" ;;
    *)
        gum style --foreground 196 "用法: bash maintain-gum.sh [status|self|upgrade|sync|monitor|deps|fix|example|setup|token|pat|mcp|llm|test|menu]"
        exit 1 ;;
esac
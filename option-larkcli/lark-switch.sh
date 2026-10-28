#!/bin/bash
# 飞书账号切换脚本
# 功能：切换 lark-cli 使用的飞书账号，支持持久化到 ccprivate
# 配置：从 ../conf/feishu.json 读取 apps 数组
#
# 使用：
#   bash ccconfig/option-larkcli/lark-switch.sh <name>       # 切换到指定账号（仅本 session）
#   bash ccconfig/option-larkcli/lark-switch.sh <name> -p    # 切换并持久化（写入 ccprivate/link/.lark-default-account，跨机器生效）
#   bash ccconfig/option-larkcli/lark-switch.sh               # 显示当前账号
#   bash ccconfig/option-larkcli/lark-switch.sh --list        # 列出所有账号

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/dry-run.sh"
source "$CCCONFIG_DIR/lib/path-helper.sh"
FEISHU_CONF="$(resolve_conf feishu.json)" || exit 1
MARKER_FILE="$HOME/.lark-cli-account"
# 跨机器默认账号 → symlink 到 ccprivate/link/.lark-default-account
DEFAULT_FILE="$HOME/.lark-default-account"

# 颜色（colors.sh 可选 source，缺失时 fallback）
source "$CCCONFIG_DIR/lib/colors.sh"

# ========== 真实授权状态 ==========
# config.json 里的 users[] 是「登录过的用户记录」，token 过期后仍残留，
# 拿它判授权会永远报"已授权"（假阳性）。唯一可信来源是 auth status 的
# identities.user.available。$1=config 目录；echo yes/no/unknown
lark_user_authorized() {
    local cfg_dir="$1" raw
    raw=$(LARKSUITE_CLI_CONFIG_DIR="$cfg_dir" lark-cli auth status 2>/dev/null || true)
    [ -z "$raw" ] && { echo "unknown"; return; }
    printf '%s' "$raw" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('unknown'); sys.exit()
u = d.get('identities', {}).get('user', {})
print('yes' if u.get('available') else 'no')
" 2>/dev/null || echo "unknown"
}

# ========== 从 feishu.json apps[] 读取账号列表 ==========
get_apps() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    apps = data.get('apps', [])
    for app in apps:
        lark = app.get('larkCli', {})
        if lark.get('enabled', False):
            print(json.dumps({
                'name': app.get('name', ''),
                'brand': app.get('brand', 'feishu'),
                'appId': app.get('appId', ''),
                'appSecret': app.get('appSecret', ''),
                'configDir': lark.get('configDir', '~/.lark-cli'),
                'description': app.get('description', '')
            }))
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# 解析单行 app JSON
parse_app() {
    python3 -c "
import json,sys
d=json.load(sys.stdin)
print('|'.join([
    d.get('name',''),
    d.get('brand','feishu'),
    d.get('appId',''),
    d.get('appSecret',''),
    d.get('configDir','~/.lark-cli'),
    d.get('description','')
]))
" 2>/dev/null
}

# ========== 检测当前活跃账号 ==========
detect_current() {
    local current_dir="${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}"
    current_dir="${current_dir/#\~/$HOME}"

    # 优先从 marker 文件读
    if [ -f "$MARKER_FILE" ]; then
        local marker_name
        marker_name=$(grep '^name=' "$MARKER_FILE" 2>/dev/null | cut -d'=' -f2)
        if [ -n "$marker_name" ]; then
            echo "$marker_name"
            return
        fi
    fi

    # 回退：从 configDir 匹配
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name config_dir
        IFS='|' read -r name _ _ _ config_dir _ <<< "$(echo "$line" | parse_app)"
        config_dir="${config_dir:-$HOME/.lark-cli}"
        config_dir="${config_dir/#\~/$HOME}"
        if [ "$config_dir" = "$current_dir" ]; then
            echo "$name"
            return
        fi
    done < <(get_apps)

    # 回退：按 appId 匹配（configDir 不匹配时，从 config.json 读 appId）
    local cfg="${current_dir}/config.json"
    if [ -f "$cfg" ]; then
        local cfg_app_id
        cfg_app_id=$(python3 -c "import json; d=json.load(open('$cfg')); print(d.get('apps',[{}])[0].get('appId',''))" 2>/dev/null)
        if [ -n "$cfg_app_id" ]; then
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                local name app_id
                IFS='|' read -r name _ app_id _ _ _ <<< "$(echo "$line" | parse_app)"
                if [ "$app_id" = "$cfg_app_id" ]; then
                    echo "$name"
                    return
                fi
            done < <(get_apps)
        fi
    fi

    echo ""
}

# ========== 显示当前账号 ==========
show_current() {
    local current_name current_dir
    current_name=$(detect_current)
    # 优先从 env var，回退到 marker 文件，再回退到默认
    if [ -n "${LARKSUITE_CLI_CONFIG_DIR:-}" ]; then
        current_dir="${LARKSUITE_CLI_CONFIG_DIR/#\~/$HOME}"
    elif [ -f "$MARKER_FILE" ]; then
        current_dir=$(grep '^configDir=' "$MARKER_FILE" 2>/dev/null | cut -d'=' -f2)
        current_dir="${current_dir:-$HOME/.lark-cli}"
    else
        current_dir="$HOME/.lark-cli"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${CYAN}  lark-cli 当前账号${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo ""

    if [ -n "$current_name" ]; then
        echo -e "  账号:   ${GREEN}${current_name}${NC}"
    else
        echo -e "  账号:   ${YELLOW}未匹配到已知账号${NC}"
    fi
    echo -e "  配置目录: ${GRAY}${current_dir}${NC}"

    # 检查授权状态
    if command -v lark-cli &>/dev/null; then
        local config_file="${current_dir}/config.json"
        if [ -f "$config_file" ]; then
            local app_id
            app_id=$(python3 -c "import json; d=json.load(open('$config_file')); apps=d.get('apps',[]); print(apps[0].get('appId','?'))" 2>/dev/null || echo "?")
            echo -e "  appId:  ${GRAY}${app_id}${NC}"

            local has_user
            has_user=$(lark_user_authorized "$current_dir")
            case "$has_user" in
                yes) echo -e "  授权:   ${GREEN}已授权${NC}" ;;
                unknown) echo -e "  授权:   ${GRAY}未知（lark-cli auth status 无输出）${NC}" ;;
                *) echo -e "  授权:   ${YELLOW}未授权${NC}" ;;
            esac
            # 未授权时当场给出口 —— 此前只提示"未授权"，没有可执行的动作，
            # 用户找不到地方补授权（只能去翻文档）。这里直接问要不要现在授权。
            if [ "$has_user" != "yes" ] && [[ "${NONINTERACTIVE:-false}" != "true" ]] && [[ -r /dev/tty ]]; then
                echo ""
                if confirm "现在授权 ${current_name}？（浏览器/飞书扫码，1 分钟）" y; then
                    bash "$SCRIPT_DIR/init.sh" --auth-login "$current_name"
                    return $?
                fi
                info "已跳过。稍后可在此菜单重跑本项，或: bash option-larkcli/init.sh --auth-login ${current_name}"
            fi
        else
            echo -e "  状态:   ${YELLOW}未初始化${NC}"
        fi
    fi

    # 持久化状态：~/.lark-default-account 是 ccprivate link 文件
    if [ -f "$DEFAULT_FILE" ]; then
        local persisted
        persisted=$(head -n1 "$DEFAULT_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$persisted" ]; then
            echo -e "  ccprivate 默认: ${GREEN}${persisted}${NC}"
            if [ "$persisted" = "$current_name" ]; then
                echo -e "  持久化:         ${GREEN}已写入 ccprivate（与当前一致）${NC}"
            else
                echo -e "  持久化:         ${YELLOW}ccprivate=${persisted}，当前=${current_name}（不同步？）${NC}"
            fi
        else
            echo -e "  持久化:         ${GRAY}仅当前 session（加 -p 写入 ccprivate）${NC}"
        fi
    else
        echo -e "  持久化:         ${GRAY}仅当前 session（加 -p 写入 ccprivate）${NC}"
    fi

    echo ""
    echo -e "${GRAY}切换:  bash ccconfig/option-larkcli/lark-switch.sh <name> [-p]${NC}"
    echo -e "${GRAY}列表:  bash ccconfig/option-larkcli/lark-switch.sh --list${NC}"
    echo ""
}

# ========== 列出所有账号 ==========
list_accounts() {
    local current_name
    current_name=$(detect_current)

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${CYAN}  飞书账号列表${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo ""

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name brand app_id app_secret config_dir desc
        IFS='|' read -r name brand app_id app_secret config_dir desc <<< "$(echo "$line" | parse_app)"
        name="${name:-}"
        brand="${brand:-feishu}"
        app_id="${app_id:-}"
        app_secret="${app_secret:-}"
        config_dir="${config_dir:-$HOME/.lark-cli}"
        config_dir="${config_dir/#\~/$HOME}"
        desc="${desc:-}"

        # 授权态：唯一可信来源是 auth status 的 identities.user.available。
        # 列表里就报出来 —— 否则"选哪个账号"这个决定缺了最关键的一列信息。
        local auth_mark
        case "$(lark_user_authorized "$config_dir")" in
            yes) auth_mark="${GREEN}已授权${NC}" ;;
            no)  auth_mark="${YELLOW}未授权${NC}" ;;
            *)   auth_mark="${GRAY}未知${NC}" ;;
        esac

        if [ "$name" = "$current_name" ] && [ -n "$current_name" ]; then
            echo -e "${GREEN} ▶ ${name}${NC} ${GRAY}(当前)${NC}"
        else
            echo -e "   ${CYAN}${name}${NC}"
        fi
        echo -e "     ${GRAY}appId:${NC} ${app_id}"
        echo -e "     ${GRAY}配置:${NC} ${config_dir}"
        echo -e "     ${GRAY}授权:${NC} ${auth_mark}"
        if [ -n "$desc" ]; then
            echo -e "     ${GRAY}说明:${NC} ${desc}"
        fi
        echo ""
    done < <(get_apps)
}

# ========== 选择账号（5B）==========
# 5A 列出什么，这里就选什么 —— 同一份数据源（get_apps），不额外维护一份名单。
# 非交互环境（NONINTERACTIVE / 无 /dev/tty）退化为打印列表 + 提示走命令行。
pick_account() {
    local current_name
    current_name=$(detect_current)

    local -a names=() items=()
    local line name desc
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        IFS='|' read -r name _ _ _ _ desc <<< "$(echo "$line" | parse_app)"
        [ -z "$name" ] && continue
        names+=("$name")
        if [ "$name" = "$current_name" ]; then
            items+=("${name}（当前）")
        else
            items+=("${name}${desc:+ — $desc}")
        fi
    done < <(get_apps)

    if [ ${#names[@]} -eq 0 ]; then
        warn "feishu.json 里没有启用的 lark-cli 账号"
        return 1
    fi

    if [ ${#names[@]} -eq 1 ]; then
        info "只有一个账号：${names[0]}"
        switch_account "${names[0]}"
        return $?
    fi

    if [[ "${NONINTERACTIVE:-false}" == "true" ]] || [[ ! -r /dev/tty ]]; then
        warn "非交互环境，无法选择账号。可用:"
        printf '    %s\n' "${names[@]}"
        info "  命令行: bash option-larkcli/lark-switch.sh <账号名> -p"
        return 1
    fi

    source "$CCCONFIG_DIR/lib/interact.sh"
    local choice
    choice=$(menu_select "选择账号（切换并持久化）" "${items[@]}") || return 1
    [[ -z "$choice" || "$choice" = "0" ]] && { info "已取消"; return 0; }

    switch_account "${names[$((choice-1))]}" -p
}

# ========== 切换账号 ==========
switch_account() {
    local target_name="$1"
    local do_persist=false

    # 检查第二个参数是否为 -p/--persist
    if [ "${2:-}" = "-p" ] || [ "${2:-}" = "--persist" ]; then
        do_persist=true
    fi

    # 查找目标账号
    local target_line=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name
        IFS='|' read -r name _ _ _ _ _ <<< "$(echo "$line" | parse_app)"
        if [ "$name" = "$target_name" ]; then
            target_line="$line"
            break
        fi
    done < <(get_apps)

    if [ -z "$target_line" ]; then
        echo -e "${RED}✗ 未找到账号: ${target_name}${NC}"
        echo ""
        echo "可用账号："
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local n
            IFS='|' read -r n _ _ _ _ _ <<< "$(echo "$line" | parse_app)"
            echo "  - ${n:-}"
        done < <(get_apps)
        return 1
    fi

    local brand app_id app_secret config_dir desc
    IFS='|' read -r _ brand app_id app_secret config_dir desc <<< "$(echo "$target_line" | parse_app)"
    brand="${brand:-feishu}"
    app_id="${app_id:-}"
    app_secret="${app_secret:-}"
    config_dir="${config_dir:-$HOME/.lark-cli}"
    config_dir="${config_dir/#\~/$HOME}"
    desc="${desc:-}"

    # 创建配置目录
    mkdir -p "$config_dir"

    # 设置环境变量（当前 session）
    export LARKSUITE_CLI_CONFIG_DIR="$config_dir"
    export PATH="$HOME/.local/bin:$PATH"

    # 初始化配置（如果需要）
    local config_file="${config_dir}/config.json"
    if [ ! -f "$config_file" ]; then
        echo -e "${GRAY}首次使用 ${target_name}，正在初始化配置...${NC}"
        if echo "$app_secret" | lark-cli config init --app-id "$app_id" --app-secret-stdin --brand "$brand" 2>&1; then
            echo -e "${GREEN}✓ 配置初始化成功${NC}"
        else
            echo -e "${RED}✗ 配置初始化失败${NC}"
            return 1
        fi
    fi

    # 检查授权状态（查真实 token，非 config 里的 users 记录）
    local auth_status="not_authorized"
    local _auth="$(lark_user_authorized "$config_dir")"
    [ "$_auth" = "yes" ] && auth_status="authorized"

    # 写 marker 文件
    cat > "$MARKER_FILE" << EOF
name=$target_name
configDir=$config_dir
switchedAt=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    # 持久化到 ccprivate：写 ~/.lark-default-account（symlink → ccprivate/link/）
    if $do_persist; then
        mkdir -p "$(dirname "$DEFAULT_FILE")"
        printf '%s\n' "$target_name" > "$DEFAULT_FILE"
        echo -e "${GREEN}✓ 已持久化到 ccprivate（~/.lark-default-account → auto-sync 上传）${NC}"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  账号切换成功${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo ""
    echo -e "  账号:     ${GREEN}${target_name}${NC}"
    echo -e "  appId:    ${GRAY}${app_id}${NC}"
    echo -e "  配置目录: ${GRAY}${config_dir}${NC}"

    if [ "$auth_status" = "authorized" ]; then
        echo -e "  授权:     ${GREEN}已授权${NC}"
    else
        echo -e "  授权:     ${YELLOW}未授权${NC}"
        echo ""
        echo -e "  ${YELLOW}⚠ 需要 OAuth 授权才能以用户身份操作飞书：${NC}"
        echo -e "  ${CYAN}bash option-larkcli/init.sh --auth-login ${target_name}${NC}"
        echo ""
        echo -e "  ${GRAY}config init = 配置 app 凭证（已完成）${NC}"
        echo -e "  ${GRAY}auth login  = OAuth 用户授权（待完成）← 编辑文档必须${NC}"
    fi

    if $do_persist; then
        echo -e "  ccprivate: ${GREEN}已写入 ~/.lark-default-account${NC}"
    else
        echo -e "  ccprivate: ${GRAY}未持久化（加 -p 写入 ccprivate 跨机器生效）${NC}"
    fi
    echo ""
}

# ========== 主程序 ==========
main() {
    local arg="${1:-}"

    case "$arg" in
        --list|-l)
            list_accounts
            ;;
        --pick|-p-select)
            pick_account
            ;;
        --help|-h)
            echo "用法: lark-switch.sh [name] [-p] [--list|--pick]"
            echo ""
            echo "  name        切换到指定账号（仅当前 session）"
            echo "  name -p     切换并持久化到 ccprivate/link/.lark-default-account"
            echo "  --list      列出所有账号（5A）"
            echo "  --pick      交互式选择账号并持久化（5B）"
            echo "  (无参数)    显示当前账号，未授权时可直接授权（5C）"
            ;;
        "")
            show_current
            ;;
        *)
            switch_account "$@"
            ;;
    esac
}

main "$@"

#!/bin/bash
# 飞书账号切换脚本
# 功能：切换 lark-cli 使用的飞书账号，支持持久化
# 配置：从 ../conf/feishu.json 读取 apps 数组
#
# 使用：
#   bash ccconfig/option-bridge/lark-switch.sh <name>       # 切换到指定账号
#   bash ccconfig/option-bridge/lark-switch.sh <name> -p    # 切换并持久化（写入 ~/.bashrc）
#   bash ccconfig/option-bridge/lark-switch.sh               # 显示当前账号
#   bash ccconfig/option-bridge/lark-switch.sh --list        # 列出所有账号

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEISHU_CONF="$SCRIPT_DIR/../conf/feishu.json"
MARKER_FILE="$HOME/.lark-cli-account"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

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
    current_dir="$(eval echo "$current_dir")"

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
        config_dir=$(eval echo "${config_dir:-$HOME/.lark-cli}")
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
        current_dir="$(eval echo "$LARKSUITE_CLI_CONFIG_DIR")"
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
            has_user=$(python3 -c "import json; d=json.load(open('$config_file')); print('yes' if d.get('apps',[{}])[0].get('users') else 'no')" 2>/dev/null || echo "?")
            if [ "$has_user" = "yes" ]; then
                echo -e "  授权:   ${GREEN}已授权${NC}"
            else
                echo -e "  授权:   ${YELLOW}未授权 — lark-cli auth login --recommend${NC}"
            fi
        else
            echo -e "  状态:   ${YELLOW}未初始化${NC}"
        fi
    fi

    # 持久化状态
    if grep -q "LARKSUITE_CLI_CONFIG_DIR" "$HOME/.bashrc" 2>/dev/null; then
        echo -e "  持久化: ${GREEN}已写入 ~/.bashrc${NC}"
    else
        echo -e "  持久化: ${GRAY}仅当前 session${NC}"
    fi

    echo ""
    echo -e "${GRAY}切换:  bash ccconfig/option-bridge/lark-switch.sh <name>${NC}"
    echo -e "${GRAY}列表:  bash ccconfig/option-bridge/lark-switch.sh --list${NC}"
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
        config_dir=$(eval echo "${config_dir:-$HOME/.lark-cli}")
        desc="${desc:-}"

        local marker="  "
        if [ "$name" = "$current_name" ] && [ -n "$current_name" ]; then
            echo -e "${GREEN} ▶ ${name}${NC} ${GRAY}(当前)${NC}"
        else
            echo -e "   ${CYAN}${name}${NC}"
        fi
        echo -e "     ${GRAY}appId:${NC} ${app_id}"
        echo -e "     ${GRAY}配置:${NC} ${config_dir}"
        if [ -n "$desc" ]; then
            echo -e "     ${GRAY}说明:${NC} ${desc}"
        fi
        echo ""
    done < <(get_apps)
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
    config_dir=$(eval echo "${config_dir:-$HOME/.lark-cli}")
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

    # 检查授权状态
    local auth_status="unknown"
    if [ -f "$config_file" ]; then
        if python3 -c "import json; d=json.load(open('$config_file')); exit(0 if d.get('apps',[{}])[0].get('users') else 1)" 2>/dev/null; then
            auth_status="authorized"
        else
            auth_status="not_authorized"
        fi
    fi

    # 写 marker 文件
    cat > "$MARKER_FILE" << EOF
name=$target_name
configDir=$config_dir
switchedAt=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    # 持久化到 ~/.bashrc
    if $do_persist; then
        local bashrc="$HOME/.bashrc"
        local export_line="export LARKSUITE_CLI_CONFIG_DIR=$config_dir"

        if grep -q "^export LARKSUITE_CLI_CONFIG_DIR=" "$bashrc" 2>/dev/null; then
            sed -i "s|^export LARKSUITE_CLI_CONFIG_DIR=.*|$export_line|" "$bashrc"
        else
            echo "" >> "$bashrc"
            echo "# lark-cli 飞书账号（由 lark-switch.sh 管理）" >> "$bashrc"
            echo "$export_line" >> "$bashrc"
        fi
        echo -e "${GREEN}✓ 已持久化到 ~/.bashrc${NC}"
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
        echo -e "  ${CYAN}lark-cli auth login --recommend${NC}"
        echo ""
        echo -e "  ${GRAY}config init = 配置 app 凭证（已完成）${NC}"
        echo -e "  ${GRAY}auth login  = OAuth 用户授权（待完成）← 编辑文档必须${NC}"
    fi

    if $do_persist; then
        echo -e "  持久化:   ${GREEN}新终端自动生效${NC}"
    else
        echo -e "  持久化:   ${YELLOW}仅当前 session（加 -p 持久化）${NC}"
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
        --help|-h)
            echo "用法: lark-switch.sh [name] [-p] [--list]"
            echo ""
            echo "  name        切换到指定账号"
            echo "  name -p     切换并持久化到 ~/.bashrc"
            echo "  --list      列出所有账号"
            echo "  (无参数)    显示当前账号"
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

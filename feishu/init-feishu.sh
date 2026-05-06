#!/bin/bash
# 飞书初始化脚本
# 功能：安装配置 lark-cli（文档/日历/任务写操作）
# 配置：从 ../conf/feishu.json 读取
# 目的：新 Ubuntu/WSL 环境配置飞书基础能力（所有环境都跑）
#
# 多账号支持：
#   bash ccconfig/feishu/init-feishu.sh                    # 初始化默认账号（向后兼容）
#   bash ccconfig/feishu/init-feishu.sh --account <name>  # 初始化指定账号
#   bash ccconfig/feishu/init-feishu.sh --list            # 列出所有账号
#
# 注意：cc-connect (Bridge) 相关在 init-cconnect.sh 中

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEISHU_CONF="$SCRIPT_DIR/../conf/feishu.json"

# 动态路径解析，替代硬编码 node 路径
source "$SCRIPT_DIR/../lib/path-helper.sh"
export PATH="$(find_node_bin):${HOME}/.local/bin:$PATH"
# 避免 lark-cli 警告 "requests will transit through proxy"
export LARK_CLI_NO_PROXY=1

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

title() { echo -e "\n========================================\n$1\n========================================\n${CYAN}"; }
section() { echo -e "\n【$1】${YELLOW}"; }
good() { echo -e "$1${GREEN}"; }
bad() { echo -e "$1${RED}"; }
info() { echo -e "$1${GRAY}"; }
warn() { echo -e "$1${YELLOW}"; }

# ========== JSON 读取 ==========
get_lark_field() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    key = sys.argv[2]
    lark = data.get('lark', {})
    print(lark.get(key, ''))
except:
    print('')
PYEOF
}

get_account_by_name() {
    local name="$1"
    python3 - "$FEISHU_CONF" << PYEOF
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    name = sys.argv[2]
    for acc in data.get('accounts', []):
        if acc.get('name') == name:
            print(json.dumps(acc))
            break
    else:
        for acc in data.get('accounts', []):
            if acc.get('name') == 'default':
                print(json.dumps(acc))
                break
except:
    pass
PYEOF
}

get_all_account_names() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    accounts = data.get('accounts', [])
    if not accounts:
        lark = data.get('lark', {})
        if lark.get('appId'):
            accounts = [{'name': 'default'}]
    for acc in accounts:
        print(acc.get('name', 'unknown'))
except:
    pass
PYEOF
}

# ========== 检查前置环境 ==========
check_prerequisites() {
    title "检查前置环境"

    local missing=0

    if ! command -v node &> /dev/null; then
        bad "❌ Node.js 未安装"
        missing=1
    else
        good "✓ Node.js $(node --version)"
    fi

    if ! command -v npm &> /dev/null; then
        bad "❌ npm 未安装"
        missing=1
    else
        good "✓ npm $(npm --version)"
    fi

    if [ ! -f "$FEISHU_CONF" ]; then
        bad "❌ 配置文件不存在: $FEISHU_CONF"
        exit 1
    fi
    good "✓ 配置文件: $FEISHU_CONF"

    if [ $missing -eq 1 ]; then
        echo ""
        warn "请先运行 ubuntuinit.sh 完成基础环境配置"
        exit 1
    fi
}

# ========== 安装 lark-cli ==========
install_lark_cli() {
    title "安装 lark-cli"

    export PATH="$HOME/.local/bin:$PATH"

    if command -v lark-cli &> /dev/null; then
        good "✓ lark-cli 已安装: $(lark-cli --version 2>/dev/null || lark-cli version 2>/dev/null || echo 'unknown')"
        return 0
    fi

    section "npm 全局安装"
    echo -n "安装 @larksuite/cli ... "
    if npm install -g @larksuite/cli 2>&1; then
        good "✅ 安装成功"
    else
        bad "❌ 安装失败"
        return 1
    fi

    mkdir -p "$HOME/.local/bin"

    local npm_global_root
    npm_global_root=$(npm root -g 2>/dev/null || echo "$(dirname "$(find_node_bin)")/lib/node_modules")
    local lark_src="$npm_global_root/@larksuite/cli/bin/lark-cli.js"

    if [ ! -f "$lark_src" ]; then
        lark_src="$npm_global_root/@larksuite/cli/bin/cli.js"
    fi
    if [ ! -f "$lark_src" ]; then
        lark_src="$npm_global_root/@larksuite/cli/scripts/run.js"
    fi

    if [ -f "$lark_src" ]; then
        rm -f "$HOME/.local/bin/lark-cli"
        ln -sf "$lark_src" "$HOME/.local/bin/lark-cli"
    fi

    echo -n "验证安装 ... "
    if command -v lark-cli &> /dev/null; then
        good "✅ lark-cli 已可用"
    else
        bad "❌ lark-cli 不可用"
        return 1
    fi
}

# ========== 配置并授权单个账号 ==========
setup_account() {
    local name="$1"
    local brand="$2"
    local app_id="$3"
    local app_secret="$4"
    local config_dir="$5"
    local is_interactive="${6:-true}"

    section "账号: ${name}"

    config_dir=$(eval echo "$config_dir")
    mkdir -p "$config_dir"

    export LARKSUITE_CLI_CONFIG_DIR="$config_dir"
    export PATH="$HOME/.local/bin:$PATH"

    echo "配置目录: ${config_dir}"
    echo "appId: ${app_id}"

    local config_file="${config_dir}/config.json"
    if [ -f "$config_file" ]; then
        good "✓ 已配置 (跳过初始化)"
    else
        echo -n "初始化配置 ... "
        if echo "$app_secret" | lark-cli config init --app-id "$app_id" --app-secret-stdin --brand "$brand" 2>&1; then
            good "✅ 配置成功"
        else
            bad "❌ 配置失败"
            return 1
        fi
    fi

    local auth_ok=false
    if lark-cli auth status 2>/dev/null | grep -q "Authorized"; then
        good "✓ 已授权"
        auth_ok=true
    else
        warn "○ 未授权"
    fi

    if [ "$is_interactive" = "true" ] && [ "$auth_ok" = "false" ]; then
        echo ""
        echo -e "${YELLOW}需要 OAuth 授权才能使用此账号${NC}"
        echo ""
        read -p "是否现在执行授权? [y/N]: " confirm || true
        confirm="${confirm:-n}"
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            lark-cli auth login --recommend || warn "授权可能需要浏览器完成"
        else
            info "后续手动授权: LARKSUITE_CLI_CONFIG_DIR=${config_dir} lark-cli auth login --recommend"
        fi
    fi
}

# ========== 列出所有账号 ==========
list_accounts() {
    title "可用账号列表"

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        echo -e "  ${CYAN}- ${name}${NC}"
    done < <(get_all_account_names)

    echo ""
    info "使用 --account <name> 初始化指定账号"
}

# ========== 主程序 ==========
main() {
    local target_account=""
    local is_interactive=true

    while [ $# -gt 0 ]; do
        case "$1" in
            --account|-a)
                target_account="$2"
                shift 2
                ;;
            --list|-l)
                list_accounts
                exit 0
                ;;
            --non-interactive|-y)
                is_interactive=false
                shift
                ;;
            --help|-h)
                echo "用法: $0 [--account <name>] [--list] [--non-interactive]"
                echo ""
                echo "  --account <name>  初始化指定账号"
                echo "  --list            列出所有可用账号"
                echo "  --non-interactive 跳过授权确认"
                echo "  (无参数)          初始化默认账号（向后兼容）"
                exit 0
                ;;
            *)
                bad "❌ 未知参数: $1"
                exit 1
                ;;
        esac
    done

    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         飞书初始化 - Feishu Init               ║"
    echo "║    安装配置 lark-cli（文档/日历/任务）         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"

    check_prerequisites
    install_lark_cli

    if [ -n "$target_account" ]; then
        local acc_json
        acc_json=$(get_account_by_name "$target_account")
        if [ -z "$acc_json" ]; then
            bad "❌ 未找到账号: ${target_account}"
            list_accounts
            exit 1
        fi

        local brand app_id app_secret config_dir
        brand=$(echo "$acc_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('brand','feishu'))" 2>/dev/null || echo "feishu")
        app_id=$(echo "$acc_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('appId',''))" 2>/dev/null || echo "")
        app_secret=$(echo "$acc_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('appSecret',''))" 2>/dev/null || echo "")
        config_dir=$(echo "$acc_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('configDir','~/.lark-cli'))" 2>/dev/null || echo "~/.lark-cli")

        setup_account "$target_account" "$brand" "$app_id" "$app_secret" "$config_dir" "$is_interactive"

    else
        title "初始化默认账号（向后兼容）"

        local brand app_id app_secret config_dir
        brand=$(get_lark_field "brand" || echo "feishu")
        app_id=$(get_lark_field "appId")
        app_secret=$(get_lark_field "appSecret")
        config_dir=$(get_lark_field "configDir" || echo "~/.lark-cli")

        if [ -z "$app_id" ]; then
            bad "❌ 配置文件中也未找到默认账号"
            exit 1
        fi

        setup_account "default" "$brand" "$app_id" "$app_secret" "$config_dir" "$is_interactive"
    fi

    echo ""
    title "✅ 飞书初始化完成"
    echo ""
    echo "提示："
    echo "- 多账号切换: bash ccconfig/feishu/lark-switch.sh <account-name>"
    echo "- cc-connect (Bridge): bash ccconfig/cconnect/init-cconnect.sh"
    echo ""
}

main "$@"

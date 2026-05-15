#!/bin/bash
# 飞书账号切换脚本
# 功能：在当前 session 中切换 lark-cli 使用的飞书账号
# 配置：从 ../conf/feishu.json 读取 accounts 数组
#
# 使用：
#   bash ccconfig/option-bridge/lark-switch.sh <account-name>   # 切换到指定账号
#   bash ccconfig/option-bridge/lark-switch.sh                   # 显示当前账号
#   bash ccconfig/option-bridge/lark-switch.sh --list             # 列出所有账号

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEISHU_CONF="$SCRIPT_DIR/../conf/feishu.json"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

good() { echo -e "$1${GREEN}"; }
bad() { echo -e "$1${RED}"; }
info() { echo -e "$1${GRAY}"; }
warn() { echo -e "$1${YELLOW}"; }

# ========== JSON 读取函数 ==========
get_accounts() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    accounts = data.get('accounts', [])
    if not accounts:
        # 兼容：没有 accounts 时用 lark 字段模拟一个默认账号
        lark = data.get('lark', {})
        if lark.get('appId'):
            accounts = [{
                'name': 'default',
                'brand': lark.get('brand', 'feishu'),
                'appId': lark.get('appId'),
                'appSecret': lark.get('appSecret'),
                'configDir': lark.get('configDir', '~/.lark-cli')
            }]
    for acc in accounts:
        print(json.dumps(acc))
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

get_default_account() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    lark = data.get('lark', {})
    if lark.get('appId'):
        print(json.dumps({
            'name': 'default',
            'brand': lark.get('brand', 'feishu'),
            'appId': lark.get('appId'),
            'appSecret': lark.get('appSecret'),
            'configDir': lark.get('configDir', '~/.lark-cli')
        }))
except:
    pass
PYEOF
}

# 解析单行 account JSON，输出 | 分隔字段: name|brand|appId|appSecret|configDir
parse_account() {
    python3 -c "
import json,sys
d=json.load(sys.stdin)
print('|'.join([
    d.get('name',''),
    d.get('brand','feishu'),
    d.get('appId',''),
    d.get('appSecret',''),
    d.get('configDir','~/.lark-cli')
]))
" 2>/dev/null
}

# ========== 显示当前账号 ==========
show_current() {
    local current_dir="${LARKSUITE_CLI_CONFIG_DIR:-~/.lark-cli}"

    echo "========================================"
    echo "  lark-cli 账号切换器"
    echo "========================================"
    echo ""
    echo -e "${CYAN}当前 session 账号信息：${NC}"
    echo "  LARKSUITE_CLI_CONFIG_DIR: ${current_dir}"

    # 尝试从 config 读取当前账号
    local config_file="${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}/config.json"
    if [ -f "$config_file" ]; then
        local app_id
        app_id=$(python3 - "$config_file" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    apps = data.get('apps', [])
    if apps:
        print(apps[0].get('appId', 'unknown'))
    else:
        print('not configured')
except:
    print('unknown')
PYEOF
)
        echo "  当前 appId: ${app_id}"
    fi

    # 查找对应的账号名
    local found=0
    while IFS= read -r line; do
        local name config_dir
        IFS='|' read -r name _ _ config_dir <<< "$(echo "$line" | parse_account)"
        name="${name:-}"
        config_dir="${config_dir:-~/.lark-cli}"
        config_dir=$(eval echo "$config_dir")
        if [ "$config_dir" = "$current_dir" ] || [ "$current_dir" = "$config_dir" ]; then
            echo -e "  账号名称: ${GREEN}${name}${NC}"
            found=1
        fi
    done < <(get_accounts)

    if [ $found -eq 0 ]; then
        echo -e "  账号名称: ${YELLOW}未匹配到已知账号${NC}"
    fi

    echo ""
}

# ========== 列出所有账号 ==========
list_accounts() {
    echo "========================================"
    echo "  可用账号列表"
    echo "========================================"
    echo ""

    local current_dir="${LARKSUITE_CLI_CONFIG_DIR:-~/.lark-cli}"

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name brand app_id config_dir
        IFS='|' read -r name brand app_id config_dir <<< "$(echo "$line" | parse_account)"
        name="${name:-}"
        brand="${brand:-feishu}"
        app_id="${app_id:-}"
        config_dir="${config_dir:-~/.lark-cli}"

        config_dir=$(eval echo "$config_dir")

        local marker=""
        if [ "$config_dir" = "$current_dir" ] || [ "$current_dir" = "$config_dir" ]; then
            marker="${GREEN}[当前]${NC}"
        else
            marker="${GRAY}[    ]${NC}"
        fi

        echo -e "$marker ${CYAN}${name}${NC} - ${description}"
        echo -e "      appId: ${app_id}..."
        echo -e "      配置目录: ${config_dir}"
        echo ""
    done < <(get_accounts)
}

# ========== 切换账号 ==========
switch_account() {
    local target_name="$1"

    # 查找目标账号
    local target_line=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name
        IFS='|' read -r name _ _ _ _ <<< "$(echo "$line" | parse_account)"
        name="${name:-}"
        if [ "$name" = "$target_name" ]; then
            target_line="$line"
            break
        fi
    done < <(get_accounts)

    if [ -z "$target_line" ]; then
        bad "❌ 未找到账号: ${target_name}"
        echo ""
        echo "可用账号："
        list_accounts 2>/dev/null || get_accounts | while IFS= read -r line; do
            local n
            IFS='|' read -r n _ _ _ _ <<< "$(echo "$line" | parse_account)"
            echo "  - ${n:-}"
        done
        exit 1
    fi

    local brand app_id app_secret config_dir
    IFS='|' read -r _ brand app_id app_secret config_dir <<< "$(echo "$target_line" | parse_account)"
    brand="${brand:-feishu}"
    app_id="${app_id:-}"
    app_secret="${app_secret:-}"
    config_dir="${config_dir:-~/.lark-cli}"
    config_dir=$(eval echo "$config_dir")

    # 创建配置目录
    mkdir -p "$config_dir"

    # 设置环境变量（当前 session）
    export LARKSUITE_CLI_CONFIG_DIR="$config_dir"

    # 初始化配置（如果需要）
    export PATH="$HOME/.local/bin:$PATH"

    local config_file="${config_dir}/config.json"
    if [ ! -f "$config_file" ]; then
        info "📋 首次使用，正在初始化配置 ..."
        if echo "$app_secret" | lark-cli config init --app-id "$app_id" --app-secret-stdin --brand "$brand" 2>&1; then
            good "✅ 配置初始化成功"
        else
            bad "❌ 配置初始化失败"
            exit 1
        fi
    fi

    # 检查授权状态
    local auth_status
    auth_status=$(lark-cli auth status 2>/dev/null | head -1 || echo "unknown")

    echo ""
    echo "========================================"
    echo -e "  ${GREEN}账号切换成功${NC}"
    echo "========================================"
    echo ""
    echo -e "${CYAN}账号名称:${NC} ${target_name}"
    echo -e "${CYAN}appId:${NC} ${app_id}"
    echo -e "${CYAN}配置目录:${NC} ${config_dir}"
    echo -e "${CYAN}授权状态:${NC} ${auth_status}"
    echo ""
    echo -e "${YELLOW}当前 session 已激活此账号${NC}"
    echo -e "${GRAY}下次打开新窗口需重新运行: bash ccconfig/option-bridge/lark-switch.sh ${target_name}${NC}"
    echo ""

    # 提示授权
    if ! echo "$auth_status" | grep -q "Authorized"; then
        warn "⚠️ 尚未授权，请运行以下命令完成 OAuth："
        echo ""
        echo -e "  ${CYAN}lark-cli auth login --recommend${NC}"
        echo ""
    fi
}

# ========== 主程序 ==========
main() {
    local arg="${1:-}"

    if [ "$arg" = "--list" ] || [ "$arg" = "-l" ]; then
        list_accounts
    elif [ -z "$arg" ]; then
        show_current
    else
        switch_account "$arg"
    fi
}

main "$@"

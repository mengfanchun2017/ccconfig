#!/bin/bash
# Claude MCP 管理脚本
# 功能：安装并配置 MCP 服务器
#
# 数据分离：
#   - mcplist.json: MCP 元信息（名称、描述、安装命令）
#   - mcpidentity.json: 鉴权信息（Key/Token）
#
# 使用：
#   bash claude-config/scripts/bash/claudeMCP.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_LIST_FILE="$REPO_DIR/config/mcplist.json"
MCP_IDENTITY_FILE="$REPO_DIR/config/mcpidentity.json"

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
read_mcp_list() {
    python3 - "$MCP_LIST_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    for m in data.get('mcp', []):
        name = m.get('name', '')
        desc = m.get('description', '')
        install = m.get('install', '')
        install_local = m.get('install_local', '')
        command = m.get('command', '')
        args = ' '.join(m.get('args', [])) if isinstance(m.get('args', []), list) else ''
        print(f"{name}|{desc}|{install}|{install_local}|{command}|{args}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

read_mcp_identity() {
    python3 - "$MCP_IDENTITY_FILE" "$1" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    mcp_name = sys.argv[2].lower()
    for identity in data.get('mcp_identities', []):
        if identity.get('name', '').lower() == mcp_name:
            print(f"{identity.get('keyEnv','')}|{identity.get('keyValue','')}|{identity.get('keyEnv2','')}|{identity.get('keyValue2','')}")
            sys.exit(0)
    print("|||")
except:
    print("|||")
PYEOF
}

# ========== MCP 检查 ==========
CLAUDE_JSON="$HOME/.claude.json"

is_registered() {
    python3 - "$CLAUDE_JSON" "$1" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    mcp_name = sys.argv[2].lower()
    mcp_servers = data.get('mcpServers', {})
    print('true' if mcp_name in mcp_servers else 'false')
except:
    print('false')
PYEOF
}

# ========== 注册 MCP ==========
register_mcp() {
    local name="$1"
    local cmd="$2"
    local args="$3"

    echo -n "注册 $name ... "
    if claude mcp add -s user "$name" -- $cmd $args 2>&1 | grep -q "error\|Error\|failed\|Failed"; then
        bad "❌"
        return 1
    else
        good "✅"
        return 0
    fi
}

# ========== 配置 Key ==========
configure_key() {
    local name="$1"
    local key_env="$2"
    local key_value="$3"
    local key_env2="$4"
    local key_value2="$5"

    python3 - "$CLAUDE_JSON" "$name" "$key_env" "$key_value" "$key_env2" "$key_value2" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    mcp_name = sys.argv[2]
    key_env = sys.argv[3]
    key_value = sys.argv[4]
    key_env2 = sys.argv[5] if len(sys.argv) > 5 else ''
    key_value2 = sys.argv[6] if len(sys.argv) > 6 else ''

    if 'mcpServers' not in data:
        data['mcpServers'] = {}
    if mcp_name not in data['mcpServers']:
        data['mcpServers'][mcp_name] = {'command': 'echo', 'args': ['placeholder']}
    if 'env' not in data['mcpServers'][mcp_name]:
        data['mcpServers'][mcp_name]['env'] = {}

    data['mcpServers'][mcp_name]['env'][key_env] = key_value
    if key_env2 and key_value2:
        data['mcpServers'][mcp_name]['env'][key_env2] = key_value2

    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2)
    print('ok')
except Exception as e:
    print(f'error: {e}')
PYEOF
}

# ========== 主程序 ==========
if [ ! -f "$MCP_LIST_FILE" ]; then
    bad "❌ 未找到 mcplist.json"
    exit 1
fi

if [ ! -f "$MCP_IDENTITY_FILE" ]; then
    bad "❌ 未找到 mcpidentity.json"
    exit 1
fi

export PATH="$HOME/.local/bin:$PATH"

if ! command -v claude &> /dev/null; then
    bad "❌ Claude Code 未安装"
    exit 1
fi

title "Claude MCP 管理"

# 显示 MCP 列表
section "MCP 服务器"
McpNames=$(read_mcp_list)
while IFS='|' read -r name desc install install_local command args; do
    [[ -z "$name" ]] && continue
    if [[ "$(is_registered "$name")" == "true" ]]; then
        good "✓ $name [已注册]"
    else
        warn "○ $name [未注册]"
    fi
done <<< "$McpNames"

echo ""
section "操作选项"
echo "1) 安装所有缺失的 MCP"
echo "2) 配置所有 Key"
echo "3) 交互式安装"
echo "0) 退出"
echo ""

read -p "请输入 [0]: " choice
choice="${choice:-0}"

case "$choice" in
    1)
        title "安装 MCP"
        while IFS='|' read -r name desc install install_local command args; do
            [[ -z "$name" ]] && continue
            if [[ "$(is_registered "$name")" == "true" ]]; then
                info "跳过 $name: 已注册"
                continue
            fi

            echo -e "\n安装 $name ($desc)..."
            if [[ -n "$install_local" ]]; then
                eval "$install_local" &>/dev/null || true
            fi

            if [[ -n "$command" ]]; then
                register_mcp "$name" "$command" "$args"
            else
                register_mcp "$name" "$install" ""
            fi
        done <<< "$McpNames"
        ;;

    2)
        title "配置 Key"
        while IFS='|' read -r name desc install install_local command args; do
            [[ -z "$name" ]] && continue
            [[ "$(is_registered "$name")" != "true" ]] && continue

            identity=$(read_mcp_identity "$name")
            IFS='|' read -r key_env key_value key_env2 key_value2 <<< "$identity"

            if [[ -z "$key_value" ]]; then
                info "$name: 无需配置或 Key 为空"
                continue
            fi

            echo -n "配置 $name ... "
            result=$(configure_key "$name" "$key_env" "$key_value" "$key_env2" "$key_value2")
            if [[ "$result" == "ok" ]]; then
                good "✅"
            else
                bad "❌"
            fi
        done <<< "$McpNames"
        ;;

    3)
        title "交互式安装"
        idx=1
        declare -a McpArr=()
        while IFS='|' read -r name desc install install_local command args; do
            [[ -z "$name" ]] && continue
            status="[未注册]"
            [[ "$(is_registered "$name")" == "true" ]] && status="[已注册]"
            echo "$idx) $name $status - $desc"
            McpArr+=("$name|$install_local|$command|$args")
            ((idx++))
        done <<< "$McpNames"

        echo ""
        read -p "输入编号安装（空格分隔）: " sel
        [[ -z "$sel" ]] && exit 0

        for i in $sel; do
            idx=$((i-1))
            [[ $idx -lt 0 || $idx -ge ${#McpArr[@]} ]] && continue
            IFS='|' read -r name install_local command args <<< "${McpArr[$idx]}"
            [[ "$(is_registered "$name")" == "true" ]] && continue

            echo -e "\n安装 $name..."
            [[ -n "$install_local" ]] && eval "$install_local" &>/dev/null || true
            register_mcp "$name" "$command" "$args"
        done
        ;;

    *)
        info "已退出"
        exit 0
        ;;
esac

echo ""
title "✅ 完成"
echo "提示: claude mcp list 查看注册状态"

#!/bin/bash
# Claude MCP 管理脚本
# 功能：安装并配置 MCP 服务器
# 配置：从 mcpconf.json 读取（整合 mcplist + mcpidentity）
#
# 使用：
#   bash claude-config/scripts/claudemcp.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_CONF_FILE="$REPO_DIR/config/mcpconf.json"

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
    python3 - "$MCP_CONF_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    for m in data.get('mcp_servers', []):
        name = m.get('name', '')
        desc = m.get('description', '')
        mtype = m.get('type', '')
        command = m.get('command', '')
        args = m.get('args', [])
        env = m.get('env', {})
        # 将 args 列表转为字符串
        args_str = ' '.join(args) if isinstance(args, list) else str(args)
        # 将 env 字典转为 JSON 字符串
        env_str = json.dumps(env) if env else '{}'
        print(f"{name}|{desc}|{mtype}|{command}|{args_str}|{env_str}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
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

# ========== 配置 MCP env ==========
configure_mcp_env() {
    local name="$1"
    local env_json="$2"

    python3 - "$CLAUDE_JSON" "$name" "$env_json" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    mcp_name = sys.argv[2]
    env_json = sys.argv[3]

    if 'mcpServers' not in data:
        data['mcpServers'] = {}
    if mcp_name not in data['mcpServers']:
        return

    env = json.loads(env_json) if env_json and env_json != '{}' else {}
    data['mcpServers'][mcp_name]['env'] = env

    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2)
    print('ok')
except Exception as e:
    print(f'error: {e}')
PYEOF
}

# ========== 主程序 ==========
if [ ! -f "$MCP_CONF_FILE" ]; then
    bad "❌ 未找到 mcpconf.json"
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
while IFS='|' read -r name desc mtype command args_str env_str; do
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

read -p "请输入 [1]: " choice || true
choice="${choice:-1}"

case "$choice" in
    1)
        title "安装 MCP"
        while IFS='|' read -r name desc mtype command args_str env_str; do
            [[ -z "$name" ]] && continue
            if [[ "$(is_registered "$name")" == "true" ]]; then
                info "跳过 $name: 已注册"
                continue
            fi

            echo -e "\n安装 $name ($desc)..."
            if [[ -n "$command" ]] && [[ -n "$args_str" ]]; then
                register_mcp "$name" "$command" "$args_str"
                configure_mcp_env "$name" "$env_str"
            else
                warn "跳过 $name: 配置不完整"
            fi
        done <<< "$McpNames"
        ;;

    2)
        title "配置 Key"
        while IFS='|' read -r name desc mtype command args_str env_str; do
            [[ -z "$name" ]] && continue
            [[ "$(is_registered "$name")" != "true" ]] && continue

            if [[ -n "$env_str" ]] && [[ "$env_str" != "{}" ]]; then
                echo -n "配置 $name env ... "
                result=$(configure_mcp_env "$name" "$env_str")
                if [[ "$result" == "ok" ]]; then
                    good "✅"
                else
                    bad "❌"
                fi
            else
                info "$name: 无需配置 env"
            fi
        done <<< "$McpNames"
        ;;

    3)
        title "交互式安装"
        idx=1
        declare -a McpArr=()
        while IFS='|' read -r name desc mtype command args_str env_str; do
            [[ -z "$name" ]] && continue
            status="[未注册]"
            [[ "$(is_registered "$name")" == "true" ]] && status="[已注册]"
            echo "$idx) $name $status - $desc"
            McpArr+=("$name|$command|$args_str|$env_str")
            ((idx++))
        done <<< "$McpNames"

        echo ""
        read -p "输入编号安装（空格分隔）: " sel || true
        [[ -z "$sel" ]] && exit 0

        for i in $sel; do
            idx=$((i-1))
            [[ $idx -lt 0 || $idx -ge ${#McpArr[@]} ]] && continue
            IFS='|' read -r name command args_str env_str <<< "${McpArr[$idx]}"
            [[ "$(is_registered "$name")" == "true" ]] && continue

            echo -e "\n安装 $name..."
            if [[ -n "$command" ]] && [[ -n "$args_str" ]]; then
                register_mcp "$name" "$command" "$args_str"
                configure_mcp_env "$name" "$env_str"
            fi
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

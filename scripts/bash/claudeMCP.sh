#!/bin/bash
# Claude Code MCP 初始化脚本
# 功能：安装并配置 MCP 服务器，使用 mcpidentity.json 管理鉴权信息
#
# ============================================================
# 使用流程：
#   init01git → init02claude → init03env → initMCP
# ============================================================
#
# 核心逻辑：
#   1. 读取 mcplist.json 获取 MCP 元信息
#   2. 读取 mcpidentity.json 获取鉴权信息
#   3. 检测并安装 MCP 服务器
#   4. 配置 API Key/Token
#   5. 注册到 Claude Code
#
# 重要说明：
#   - mcpidentity.json 存储敏感信息（Key/Token），不参与 Git 同步
#   - mcplist.json 只记录 MCP 元信息，无敏感数据
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_LIST_FILE="$REPO_DIR/config/mcplist.json"
MCP_IDENTITY_FILE="$REPO_DIR/config/mcpidentity.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

title() { echo -e "\n========================================\n$1\n========================================\n${CYAN}"; }
section() { echo -e "\n【$1】${YELLOW}"; }
item() { echo -e "$1${NC}"; }
good() { echo -e "$1${GREEN}"; }
bad() { echo -e "$1${RED}"; }
info() { echo -e "$1${GRAY}"; }
warn() { echo -e "$1${YELLOW}"; }

# ========== 环境检测函数 ==========
check_command() {
    command -v "$1" &> /dev/null
}

check_python_module() {
    python3 -c "import $1" 2>/dev/null
}

# ========== JSON 读取函数 ==========
read_mcp_list() {
    python3 - "$MCP_LIST_FILE" << 'PYTHON_EOF'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    for m in data.get('mcp', []):
        name = m.get('name', '')
        desc = m.get('description', '')
        mtype = m.get('type', 'stdio')
        install = m.get('install', '')
        install_local = m.get('install_local', '')
        needs_key = str(m.get('needsKey', False)).lower()
        key_env = m.get('keyEnv', '')
        key_url = m.get('keyUrl', '')
        command = m.get('command', '')
        args = ' '.join(m.get('args', [])) if isinstance(m.get('args', []), list) else ''
        env = json.dumps(m.get('env', {})) if m.get('env') else ''
        print(f"{name}|{desc}|{mtype}|{install}|{install_local}|{needs_key}|{key_env}|{key_url}|{command}|{args}|{env}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
}

read_mcp_identity() {
    python3 - "$MCP_IDENTITY_FILE" "$1" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)

    mcp_name = sys.argv[2].lower()

    # 查找匹配的 MCP 身份
    for identity in data.get('mcp_identities', []):
        if identity.get('name', '').lower() == mcp_name:
            key_env = identity.get('keyEnv', '')
            key_value = identity.get('keyValue', '')
            key_env2 = identity.get('keyEnv2', '')
            key_value2 = identity.get('keyValue2', '')
            print(f"{key_env}|{key_value}|{key_env2}|{key_value2}")
            sys.exit(0)

    # 检查 claude_api
    if mcp_name == 'claude_api':
        claude_api = data.get('claude_api', {})
        print(f"ANTHROPIC_AUTH_TOKEN|{claude_api.get('ANTHROPIC_AUTH_TOKEN', '')}||")
        sys.exit(0)

    print("||")
except Exception as e:
    print(f"||")
PYEOF
}

update_mcp_identity() {
    python3 - "$MCP_IDENTITY_FILE" "$1" "$2" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)

    mcp_name = sys.argv[2].lower()
    key_value = sys.argv[3] if len(sys.argv) > 3 else ''

    # 更新 MCP 身份
    for identity in data.get('mcp_identities', []):
        if identity.get('name', '').lower() == mcp_name:
            identity['keyValue'] = key_value
            with open(sys.argv[1], 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            print('ok')
            sys.exit(0)

    # 更新 claude_api
    if mcp_name == 'claude_api':
        data['claude_api']['ANTHROPIC_AUTH_TOKEN'] = key_value
        with open(sys.argv[1], 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print('ok')
        sys.exit(0)

    print('not_found')
except Exception as e:
    print(f'error: {e}')
    sys.exit(1)
PYEOF
}

# ========== 检查 MCP 是否已注册 ==========
CLAUDE_JSON="$HOME/.claude.json"

is_mcp_registered() {
    python3 - "$CLAUDE_JSON" "$1" << 'PYEOF'
import json
import sys
import os

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    mcp_name = sys.argv[2].lower()

    # 检查 root-level mcpServers
    mcp_servers = data.get('mcpServers', {})
    if mcp_name in mcp_servers:
        print('true')
        sys.exit(0)

    # 检查 project-level mcpServers
    projects = data.get('projects', {})
    for proj_path, proj_data in projects.items():
        proj_mcp = proj_data.get('mcpServers', {})
        if mcp_name in proj_mcp:
            print('true')
            sys.exit(0)

    print('false')
except:
    print('false')
PYEOF
}

# ========== 注册 MCP ==========
register_mcp() {
    local name="$1"
    local command="$2"
    local args="$3"
    local env_vars="$4"

    echo -n "注册 $name ... "

    # 构建命令
    local full_cmd="$command"
    if [[ -n "$args" ]]; then
        full_cmd="$command $args"
    fi

    # 设置环境变量
    if [[ -n "$env_vars" ]]; then
        export $env_vars
    fi

    # 使用 --scope user 添加到用户全局配置
    if claude mcp add -s user "$name" -- $full_cmd 2>&1; then
        good "✅"
        return 0
    else
        bad "❌"
        return 1
    fi
}

# ========== 配置 MCP Key ==========
configure_mcp_key() {
    local name="$1"
    local key_env="$2"
    local key_value="$3"

    if [[ -z "$key_value" ]]; then
        info "$name: 无需配置 Key 或 Key 为空"
        return 0
    fi

    echo -n "配置 $name Key ... "

    # 使用 python 更新 ~/.claude.json
    python3 - "$CLAUDE_JSON" "$name" "$key_env" "$key_value" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    mcp_name = sys.argv[2]
    key_env = sys.argv[3]
    key_value = sys.argv[4]

    # 确保 mcpServers 存在
    if 'mcpServers' not in data:
        data['mcpServers'] = {}

    # 如果 MCP 不存在，创建它
    if mcp_name not in data['mcpServers']:
        data['mcpServers'][mcp_name] = {
            'command': 'echo',
            'args': ['placeholder']
        }

    # 确保 env 存在
    if 'env' not in data['mcpServers'][mcp_name]:
        data['mcpServers'][mcp_name]['env'] = {}

    # 更新 Key
    data['mcpServers'][mcp_name]['env'][key_env] = key_value

    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2)

    print('ok')
except Exception as e:
    print(f'error: {e}')
    sys.exit(1)
PYEOF

    if [[ "$?" == "ok" ]]; then
        good "✅"
        return 0
    else
        bad "❌"
        return 1
    fi
}

# ========== 主程序 ==========

# 检查文件
if [ ! -f "$MCP_LIST_FILE" ]; then
    bad "❌ 未找到 mcplist.json"
    exit 1
fi

if [ ! -f "$MCP_IDENTITY_FILE" ]; then
    bad "❌ 未找到 mcpidentity.json"
    exit 1
fi

# 确保 PATH 包含 ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# 检查 claude 命令
if ! command -v claude &> /dev/null; then
    bad "❌ Claude Code 未安装，请先运行 init02claude.sh"
    exit 1
fi

title "Claude Code MCP 初始化"

# 获取 MCP 列表
McpNames=$(read_mcp_list)

# ========== 显示 MCP 列表 ==========
section "MCP 服务器列表"
echo "将检查以下 MCP 服务器："
echo ""

while IFS='|' read -r name desc type install install_local needs_key key_env key_url command args env; do
    [[ -z "$name" ]] && continue
    registered=$(is_mcp_registered "$name")
    if [[ "$registered" == "true" ]]; then
        good "✓ $name: $desc [已注册]"
    else
        warn "○ $name: $desc [未注册]"
    fi
done <<< "$McpNames"

echo ""

# ========== 安装选项 ==========
section "请选择操作"
echo "1) 安装所有缺失的 MCP"
echo "2) 交互式选择安装"
echo "3) 检查并配置 Key"
echo "0) 退出"
echo ""

read -p "请输入选项 [0]: " choice
choice="${choice:-0}"

case "$choice" in
    1)
        title "安装所有缺失的 MCP"
        while IFS='|' read -r name desc type install install_local needs_key key_env key_url command args env; do
            [[ -z "$name" ]] && continue
            registered=$(is_mcp_registered "$name")

            if [[ "$registered" == "true" ]]; then
                info "跳过 $name: 已注册"
                continue
            fi

            echo -e "\n安装 $name ($desc)..."

            # 确定安装命令
            if [[ -n "$command" ]]; then
                install_cmd="$command"
                [[ -n "$args" ]] && install_cmd="$install_cmd $args"
            else
                install_cmd="$install"
            fi

            # 尝试本地安装
            if [[ -n "$install_local" ]]; then
                info "本地安装: $install_local"
                eval "$install_local" &>/dev/null || true
            fi

            # 注册 MCP
            register_mcp "$name" "$command" "$args" "$env"
        done <<< "$McpNames"
        ;;

    2)
        title "交互式选择安装"
        echo "可用 MCP："
        idx=1
        declare -a McpArr=()
        while IFS='|' read -r name desc type install install_local needs_key key_env key_url command args env; do
            [[ -z "$name" ]] && continue
            registered=$(is_mcp_registered "$name")
            status="[未注册]"
            [[ "$registered" == "true" ]] && status="[已注册]"
            echo "$idx) $name $status - $desc"
            McpArr+=("$name|$desc|$type|$install|$install_local|$command|$args|$env")
            ((idx++))
        done <<< "$McpNames"

        echo ""
        echo "输入编号安装（多个用空格分隔），或回车退出："
        read -p "> " sel

        if [[ -z "$sel" ]]; then
            info "已退出"
            exit 0
        fi

        for i in $sel; do
            idx=$((i-1))
            if [[ $idx -ge 0 && $idx -lt ${#McpArr[@]} ]]; then
                IFS='|' read -r name desc type install install_local command args env <<< "${McpArr[$idx]}"
                registered=$(is_mcp_registered "$name")

                if [[ "$registered" == "true" ]]; then
                    info "跳过 $name: 已注册"
                    continue
                fi

                echo -e "\n安装 $name..."
                if [[ -n "$install_local" ]]; then
                    eval "$install_local" &>/dev/null || true
                fi
                register_mcp "$name" "$command" "$args" "$env"
            fi
        done
        ;;

    3)
        title "检查并配置 Key"
        while IFS='|' read -r name desc type install install_local needs_key key_env key_url command args env; do
            [[ -z "$name" ]] && continue
            [[ "$needs_key" != "true" ]] && continue

            registered=$(is_mcp_registered "$name")
            if [[ "$registered" != "true" ]]; then
                info "跳过 $name: 未注册"
                continue
            fi

            # 读取鉴权信息
            identity=$(read_mcp_identity "$name")
            IFS='|' read -r key_env_read key_value key_env2 key_value2 <<< "$identity"

            if [[ -z "$key_value" ]]; then
                echo -e "\n$name ($desc)"
                [[ -n "$key_url" ]] && info "  Key 地址: $key_url"
                echo -n "  请输入 $key_env: "
                read -s new_key
                echo ""

                if [[ -n "$new_key" ]]; then
                    configure_mcp_key "$name" "$key_env" "$new_key"
                    # 同时更新 mcpidentity.json
                    update_mcp_identity "$name" "$new_key"
                fi
            else
                good "$name: Key 已配置"
            fi
        done <<< "$McpNames"
        ;;

    0|*)
        info "已退出"
        exit 0
        ;;
esac

echo ""
title "✅ MCP 初始化完成"
echo "提示: 在 Claude Code 中执行 /mcp 查看已注册的 MCP"
echo ""

#!/bin/bash
# Claude MCP 管理脚本
# 功能：安装并配置 MCP 服务器
# 配置：从 conf/claude.json 读取
#
# 使用：
#   bash ccconfig/init-mcp.sh

# 清理可能被污染的 PATH（WSL/Windows 继承的 PATH 可能包含非法字符）
# 使用 $HOME 而非硬编码路径，确保在新环境下也正确
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/path-helper.sh"
MCP_CONF_FILE="$CCCONFIG_ROOT/conftemp/claude.json"

ensure_config "$MCP_CONF_FILE" "conftemp/claude.json" || exit 1

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
read_mcp_settings() {
    python3 - "$MCP_CONF_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    settings = data.get('settings', {})
    print(settings.get('default_action', 'install'))
    print('true' if settings.get('auto_config_keys', False) else 'false')
except:
    print('install')
    print('false')
PYEOF
}

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
    python3 - "$CLAUDE_JSON" "$MCP_CONF_FILE" "$1" << 'PYEOF'
import json, sys
try:
    claude_json = sys.argv[1]
    conf_json = sys.argv[2]
    mcp_name = sys.argv[3].lower()

    # 检查 ~/.claude.json
    with open(claude_json, 'r') as f:
        data = json.load(f)
    mcp_servers = data.get('mcpServers', {})
    if mcp_name in mcp_servers:
        print('true')
        sys.exit(0)

    # 检查 conf/claude.json（配置源）
    with open(conf_json, 'r') as f:
        conf_data = json.load(f)
    mcp_servers_conf = conf_data.get('mcp_servers', [])
    for server in mcp_servers_conf:
        if server.get('name', '').lower() == mcp_name:
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
        print('skip')
        sys.exit(0)

    env = json.loads(env_json) if env_json and env_json != '{}' else {}
    data['mcpServers'][mcp_name]['env'] = env

    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2)
    print('ok')
except Exception as e:
    print(f'error: {e}')
PYEOF
}

# ========== 同步到 settings.json ==========
sync_to_settings() {
    local settings_file="$1"

    python3 - "$CLAUDE_JSON" "$MCP_CONF_FILE" "$settings_file" << 'PYEOF'
import json, sys

try:
    claude_json = sys.argv[1]
    conf_json = sys.argv[2]
    settings_file = sys.argv[3]

    # 读取 ~/.claude.json（可能不存在 — 新机器首次运行）
    try:
        with open(claude_json, 'r') as f:
            claude_data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        claude_data = {}

    # 读取 conf/claude.json（完整配置源）
    with open(conf_json, 'r') as f:
        conf_data = json.load(f)

    # 读取 settings.json（处理文件不存在/断链 — 新机器无 ccprivate 常见）
    try:
        with open(settings_file, 'r') as f:
            settings_data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        settings_data = {}

    # 构建完整的 mcpServers 配置（从 conf/claude.json）
    mcp_servers = {}
    disabled_names = []
    for server in conf_data.get('mcp_servers', []):
        name = server.get('name', '')
        if not name:
            continue
        mtype = server.get('type', 'stdio')
        if mtype == 'stdio':
            entry = {
                'command': server.get('command', ''),
                'args': server.get('args', []),
                'env': server.get('env', {})
            }
        else:
            entry = {
                'type': mtype,
                'url': server.get('url', ''),
                'headers': server.get('headers', {})
            }
        if server.get('disabled'):
            disabled_names.append(name)
        # 如果 ~/.claude.json 中有该 MCP 的额外配置，合并之
        if name in claude_data.get('mcpServers', {}):
            existing = claude_data['mcpServers'][name]
            if existing.get('env'):
                entry['env'] = {**entry.get('env', {}), **existing['env']}
            if existing.get('args'):
                entry['args'] = existing['args']
            if existing.get('headers'):
                entry['headers'].update(existing['headers'])
        mcp_servers[name] = entry

    settings_data['mcpServers'] = mcp_servers
    if disabled_names:
        settings_data['disabledMcpServers'] = disabled_names

    # 同步到项目级别 disabledMcpServers（/mcp 对话框 Disable 操作实际写入的位置）
    # 顶层 disabledMcpServers 有 bug #11370 不生效，项目级别才真正禁用到 session
    if 'projects' not in settings_data:
        settings_data['projects'] = {}
    for proj_path in list(settings_data['projects'].keys()):
        if disabled_names:
            settings_data['projects'][proj_path]['disabledMcpServers'] = disabled_names
        elif 'disabledMcpServers' in settings_data['projects'][proj_path]:
            del settings_data['projects'][proj_path]['disabledMcpServers']

    # 同步 hooks
    if 'hooks' in claude_data:
        settings_data['hooks'] = claude_data['hooks']

    # 同步 env：merge（settings 已有 keys 优先 → init-llm 写入不被覆盖；
    #              conf/claude.json 仅补缺失 keys → MCP API key 等）
    conf_env = conf_data.get('env', {})
    settings_data.setdefault('env', {})
    for k, v in conf_env.items():
        if k not in settings_data['env']:
            settings_data['env'][k] = v

    # 写回 settings.json
    import os, shutil
    actual = settings_file
    if os.path.islink(settings_file):
        actual = os.path.realpath(settings_file)
        if not os.path.exists(os.path.dirname(actual)):
            os.makedirs(os.path.dirname(actual), exist_ok=True)
        if os.path.islink(settings_file) and not os.path.exists(settings_file):
            os.unlink(settings_file)
    bak = actual + '.bak'
    if os.path.exists(actual):
        shutil.copy2(actual, bak)
    tmp = actual + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(settings_data, f, indent=2)
    os.replace(tmp, actual)
    if os.path.islink(settings_file) and actual != settings_file:
        pass  # already resolved to real path, written there

    print('ok')
except Exception as e:
    print(f'error: {e}')
PYEOF
}

# ========== 主程序 ==========
if [ ! -f "$MCP_CONF_FILE" ]; then
    bad "❌ 未找到 conf/claude.json"
    exit 1
fi

if ! command -v claude &> /dev/null; then
    warn "Claude Code 未安装，跳过 MCP 注册（先运行 init-ubuntu.sh）"
    info "MCP 配置文件已就绪，Claude Code 安装后重跑: bash ccconfig/init-mcp.sh sync"
    exit 0
fi

# 读取配置
MCP_SETTINGS=$(read_mcp_settings)
IFS='|' read -r DEFAULT_ACTION AUTO_CONFIG_KEYS <<< "$MCP_SETTINGS"

# 概览：待注册 MCP
section "MCP 服务器"
pending=""
McpNames=$(read_mcp_list)
while IFS='|' read -r name desc mtype command args_str env_str; do
    [[ -z "$name" ]] && continue
    if [[ "$(is_registered "$name")" == "true" ]]; then
        info "✓ $name (已注册)"
    else
        pending+="$name "
    fi
done <<< "$McpNames"
if [[ -n "$pending" ]]; then
    info "将注册: $pending"
fi
echo ""

# 根据 default_action 执行对应操作
do_install() {
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
}

do_config_keys() {
    title "配置 Key"
    while IFS='|' read -r name desc mtype command args_str env_str; do
        [[ -z "$name" ]] && continue
        [[ "$(is_registered "$name")" != "true" ]] && continue

        if [[ -n "$env_str" ]] && [[ "$env_str" != "{}" ]]; then
            echo -n "配置 $name env ... "
            result=$(configure_mcp_env "$name" "$env_str")
            if [[ "$result" == "ok" ]]; then
                good "✅"
            elif [[ "$result" == "skip" ]]; then
                info "跳过"
            else
                bad "❌"
            fi
        else
            info "$name: 无需配置 env"
        fi
    done <<< "$McpNames"
}

do_sync() {
    title "双向同步"

    do_install
    echo ""
    do_config_keys
    echo ""

    # 同步到 settings.json / .config.json（本地文件，由 auto-sync 推 GitHub）
    SETTINGS_FILE="$HOME/.claude/settings.json"
    CONFIG_FILE="$HOME/.claude/.config.json"

    for f in "$SETTINGS_FILE" "$CONFIG_FILE"; do
        result=$(sync_to_settings "$f")
        if [[ "$result" == "ok" ]]; then
            good "✅ 已写入 $(basename "$f")"
        else
            bad "❌ 同步失败 ($(basename "$f")): $result"
        fi
    done
}

# 执行对应操作
case "$DEFAULT_ACTION" in
    sync)
        info "执行双向同步 (install + config_keys)..."
        echo ""
        do_sync
        ;;
    install)
        info "执行安装所有缺失的 MCP..."
        echo ""
        do_install
        ;;
    config_keys)
        info "执行配置所有 Key..."
        echo ""
        do_config_keys
        ;;
    interactive)
        section "操作选项"
        echo "1) 安装所有缺失的 MCP"
        echo "2) 配置所有 Key"
        echo "3) 交互式安装"
        echo "0) 退出"
        echo ""

        read -p "请输入 [1]: " choice || true
        choice="${choice:-1}"

        case "$choice" in
            1) do_install ;;
            2) do_config_keys ;;
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
        ;;
    *)
        info "未知操作: $DEFAULT_ACTION，执行安装"
        do_install
        ;;
esac

echo ""
title "✅ 完成"
echo "提示: claude mcp list 查看注册状态"

# 确保脚本正常退出
exit 0

#!/bin/bash
# Claude MCP 管理脚本
# 功能：安装并配置 MCP 服务器
# 配置：从 conf/claude.json 读取
#
# 使用：
#   bash ccconfig/init-mcp.sh [sync|install|config_keys|keys]

# 清理可能被污染的 PATH（WSL/Windows 继承的 PATH 可能包含非法字符）
# 使用 $HOME 而非硬编码路径，确保在新环境下也正确
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

set -e

# 在 while read 循环内做交互输入时，stdin 已被重定向（<<< "$McpNames"）
# read 必须显式从 /dev/tty 读，否则会读到空或 EOF
interactive_read() {
    local prompt="$1" var_name="$2"
    echo -n "$prompt"
    read -r "$var_name" < /dev/tty
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/path-helper.sh"
MCP_CONF_FILE="$CCCONFIG_ROOT/conf/claude.json"

ensure_config "$MCP_CONF_FILE" "conf/claude.json" || exit 1

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
    action = settings.get('default_action', 'sync')
    auto = 'true' if settings.get('auto_config_keys', False) else 'false'
    print(f"{action}|{auto}")
except:
    print('sync|false')
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
        disabled = 'true' if m.get('disabled') else 'false'
        how_to_get = m.get('how_to_get', '')
        args_str = ' '.join(args) if isinstance(args, list) else str(args)
        env_str = json.dumps(env, ensure_ascii=False) if env else '{}'
        print(f"{name}|{desc}|{mtype}|{command}|{args_str}|{env_str}|{disabled}|{how_to_get}")
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
    if claude mcp add -s user "$name" -- $cmd $args 2>&1; then
        good "✅"
        return 0
    else
        if claude mcp list 2>/dev/null | grep -q "$name"; then
            info "已注册"
            return 0
        fi
        bad "❌"
        return 1
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
        # ★ 保留 settings.json 中已有的 env（来自 ccprivate 的真 key，最高优先级）
        if name in settings_data.get('mcpServers', {}):
            saved_env = settings_data['mcpServers'][name].get('env', {})
            # 只保留非占位符的 key
            real_keys = {k: v for k, v in saved_env.items()
                         if v and '请填入' not in str(v) and '请到' not in str(v)
                         and 'your key' not in str(v).lower() and 'placeholder' not in str(v).lower()
                         and '<your-' not in str(v)}
            if real_keys:
                entry['env'] = {**entry.get('env', {}), **real_keys}
                import sys
                print(f"  \033[0;32m{name}\033[0m: 保留已有 Key ({', '.join(real_keys.keys())})", file=sys.stderr)
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
while IFS='|' read -r name desc mtype command args_str env_str disabled how_to_get; do
    [[ -z "$name" ]] && continue
    if [[ "$disabled" == "true" ]]; then
        info "○ $name ($desc) — 已禁用"
    elif [[ "$(is_registered "$name")" == "true" ]]; then
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
    local quiet="${INIT_ALL_FLOW:-0}"
    [[ "$quiet" != "1" ]] && title "安装 MCP"

    local installed=0 skipped=0 failed=0
    while IFS='|' read -r name desc mtype command args_str env_str disabled how_to_get; do
        [[ -z "$name" ]] && continue
        if [[ "$(is_registered "$name")" == "true" ]]; then
            [[ "$quiet" != "1" ]] && info "跳过 $name: 已注册"
            skipped=$((skipped + 1))
            continue
        fi
        if [[ "$disabled" == "true" ]]; then
            [[ "$quiet" != "1" ]] && info "跳过 $name: 已禁用"
            skipped=$((skipped + 1))
            continue
        fi

        if [[ -n "$command" ]] && [[ -n "$args_str" ]]; then
            if [[ "$quiet" == "1" ]]; then
                register_mcp "$name" "$command" "$args_str" >/dev/null 2>&1 && installed=$((installed + 1)) || failed=$((failed + 1))
                configure_mcp_env "$name" "$env_str" >/dev/null 2>&1 || true
            else
                echo -e "\n安装 $name ($desc)..."
                register_mcp "$name" "$command" "$args_str"
                configure_mcp_env "$name" "$env_str"
            fi
        else
            [[ "$quiet" != "1" ]] && warn "跳过 $name: 配置不完整"
            skipped=$((skipped + 1))
        fi
    done <<< "$McpNames"

    if [[ "$quiet" == "1" ]]; then
        echo -e "  MCP 注册: ${GREEN}${installed} 新装${NC}, ${GRAY}${skipped} 跳过${NC}, ${failed} 失败"
    fi
}

do_config_keys() {
    local quiet="${INIT_ALL_FLOW:-0}"
    [[ "$quiet" != "1" ]] && title "配置 Key"

    while IFS='|' read -r name desc mtype command args_str env_str disabled how_to_get; do
        [[ -z "$name" ]] && continue
        [[ "$(is_registered "$name")" != "true" ]] && continue

        if [[ -n "$env_str" ]] && [[ "$env_str" != "{}" ]]; then
            if [[ "$quiet" == "1" ]]; then
                configure_mcp_env "$name" "$env_str" >/dev/null 2>&1 || true
            else
                echo -n "配置 $name env ... "
                result=$(configure_mcp_env "$name" "$env_str")
                if [[ "$result" == "ok" ]]; then
                    good "✅"
                elif [[ "$result" == "skip" ]]; then
                    info "跳过"
                else
                    bad "❌"
                fi
            fi
        fi
    done <<< "$McpNames"
}

do_sync() {
    local quiet="${INIT_ALL_FLOW:-0}"
    [[ "$quiet" != "1" ]] && title "双向同步"

    do_install
    [[ "$quiet" != "1" ]] && echo ""
    do_config_keys
    [[ "$quiet" != "1" ]] && echo ""

    # 同步到 settings.json / .config.json
    SETTINGS_FILE="$HOME/.claude/settings.json"
    CONFIG_FILE="$HOME/.claude/.config.json"

    for f in "$SETTINGS_FILE" "$CONFIG_FILE"; do
        if [[ "$quiet" == "1" ]]; then
            result=$(sync_to_settings "$f" 2>/dev/null)
        else
            result=$(sync_to_settings "$f")
        fi
        if [[ "$result" == "ok" ]]; then
            [[ "$quiet" != "1" ]] && good "✅ 已写入 $(basename "$f")"
        else
            bad "❌ 同步失败 ($(basename "$f")): $result"
        fi
    done

    # 状态摘要
    local ready=0 missing=0 disabled=0
    while IFS='|' read -r name desc mtype command args_str env_str disabled how_to_get; do
        [[ -z "$name" ]] && continue
        if [[ "$disabled" == "true" ]]; then
            disabled=$((disabled + 1))
            continue
        fi
        local has_placeholder=false
        if [[ "$env_str" =~ (请填入|请到|your.key|placeholder|<your-) ]]; then
            has_placeholder=true
        fi
        if [[ "$args_str" =~ (请填入|请到|your.key|placeholder|<your-) ]]; then
            has_placeholder=true
        fi
        if $has_placeholder; then
            missing=$((missing + 1))
        else
            ready=$((ready + 1))
        fi
    done <<< "$McpNames"

    local total=$((ready + missing + disabled))
    echo -e "  MCP 状态: ${GREEN}${ready} 就绪${NC}, ${YELLOW}${missing} 缺 Key${NC}, ${GRAY}${disabled} 禁用${NC} (共 ${total})"

    # 缺 Key 时提示（两种模式：verbose 单行列表 / quiet 统计）
    if [[ $missing -gt 0 ]]; then
        if [[ "$quiet" == "1" ]]; then
            echo ""
            echo -e "${YELLOW}⚠  检测到 ${missing} 个 MCP 缺失 API Key${NC}"
            echo "  1) 现在填写（交互式逐项输入）"
            echo "  2) 跳过（后续 MCP 中自行认证或手动: bash ccconfig/lib/init-mcp.sh keys）"
            echo ""
            interactive_read "  选择 [2]: " key_choice
            key_choice="${key_choice:-2}"
            if [[ "$key_choice" == "1" ]]; then
                do_keys
            else
                info "  跳过 Key 配置。补填: bash ccconfig/lib/init-mcp.sh keys"
            fi
        else
            echo ""
            while IFS='|' read -r name desc mtype command args_str env_str disabled how_to_get; do
                [[ -z "$name" ]] && continue
                [[ "$disabled" == "true" ]] && { info "  $name: ○ 已禁用"; continue; }
                if [[ "$env_str" =~ (请填入|请到|your.key|placeholder|<your-) ]] || [[ "$args_str" =~ (请填入|请到|your.key|placeholder|<your-) ]]; then
                    warn "  $name: ⚠ 缺少 Key → bash ccconfig/lib/init-mcp.sh keys"
                else
                    good "  $name: ✅ 就绪"
                fi
            done <<< "$McpNames"

            echo ""
            echo -e "${YELLOW}⚠  检测到缺失的 API Key${NC}"
            echo "  1) 现在填写（交互式逐项输入）"
            echo "  2) 跳过（后续 MCP 中自行认证或手动: bash ccconfig/lib/init-mcp.sh keys）"
            echo ""
            interactive_read "  选择 [1]: " key_choice
            key_choice="${key_choice:-1}"
            if [[ "$key_choice" == "1" ]]; then
                do_keys
            else
                info "  跳过 Key 配置。补填: bash ccconfig/lib/init-mcp.sh keys"
            fi
        fi
    fi
}

# 交互式 Key 引导
do_keys() {
    title "MCP Key 配置"
    echo "逐个输入 API Key，回车跳过不配置的 MCP"
    echo ""

    local updated=0
    while IFS='|' read -r name desc mtype command args_str env_str disabled how_to_get; do
        [[ -z "$name" ]] && continue

        echo -e "${CYAN}── $name${NC} — $desc"
        if [[ -n "$how_to_get" ]]; then
            echo -e "  ${GRAY}$how_to_get${NC}"
        fi

        local server_changed=false

        if [[ "$disabled" == "true" ]]; then
            echo -e "  ${YELLOW}当前已禁用${NC}"
            interactive_read "  启用并配置？[y/N]: " enable_choice
            server_changed=true
            if [[ ! "$enable_choice" =~ ^[Yy]$ ]]; then
                echo "  跳过"
                echo ""
                continue
            fi
        fi

        # 提取占位符 env keys（Python 只做检测，bash 做交互）
        local placeholder_env_keys
        placeholder_env_keys=$(python3 - "$env_str" << 'PYEOF'
import json, sys
env = json.loads(sys.argv[1])
keys = [k for k, v in env.items() if any(x in str(v) for x in ['请填入', '请到', 'your key', 'placeholder', '<your-'])]
print('\n'.join(keys))
PYEOF
)

        local new_env_json="$env_str"
        if [[ -n "$placeholder_env_keys" ]]; then
            while IFS= read -r key; do
                [[ -z "$key" ]] && continue
                echo -n "  $key [跳过]: "
                read -r val < /dev/tty
                if [[ -n "$val" ]]; then
                    new_env_json=$(echo "$new_env_json" | python3 - "$key" "$val" << 'PYEOF'
import json, sys
d = json.load(sys.stdin)
d[sys.argv[1]] = sys.argv[2]
print(json.dumps(d))
PYEOF
)
                    echo "    ✅ $key"
                    server_changed=true
                fi
            done <<< "$placeholder_env_keys"
        fi

        # 提取占位符 args（支持 --key=value 和 --key value 两种格式）
        local placeholder_args
        placeholder_args=$(python3 - "$args_str" << 'PYEOF'
import sys

def is_placeholder(val):
    return any(x in str(val) for x in ['请填入', '请到', 'your key', 'placeholder', '<your-'])

args = sys.argv[1]
for part in args.split(' --'):
    if '=' in part:
        k, v = part.split('=', 1)
        if is_placeholder(v):
            print(k.strip())
    else:
        segs = part.split(None, 1)
        k = segs[0]
        v = segs[1] if len(segs) > 1 else ''
        if is_placeholder(v):
            print(k.strip())
PYEOF
)

        local new_args_str="$args_str"
        if [[ -n "$placeholder_args" ]]; then
            while IFS= read -r key; do
                [[ -z "$key" ]] && continue
                echo -n "  $key [跳过]: "
                read -r val < /dev/tty
                if [[ -n "$val" ]]; then
                    new_args_str=$(python3 - "$new_args_str" "$key" "$val" << 'PYEOF'
import sys
old = sys.argv[1]
k = sys.argv[2]
v = sys.argv[3]
parts = old.split(' --')
new = [parts[0]]
for p in parts[1:]:
    matched = False
    if '=' in p:
        pk, pv = p.split('=', 1)
        if pk.strip() == k:
            new.append(f' --{k}={v}')
            matched = True
    else:
        segs = p.split(None, 1)
        pk = segs[0]
        if pk.strip() == k:
            new.append(f' --{k} {v}')
            matched = True
    if not matched:
        new.append(f' --{p}')
print(' '.join(new))
PYEOF
)
                    echo "    ✅ $key"
                    server_changed=true
                fi
            done <<< "$placeholder_args"
        fi

        # minimax-mcp 复用 minimax Key
        if [[ "$name" == "minimax-mcp" ]]; then
            local minimax_key
            minimax_key=$(python3 - "$MCP_CONF_FILE" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for s in data['mcp_servers']:
    if s['name'] == 'minimax':
        print(s.get('env', {}).get('MINIMAX_API_KEY', ''))
        break
PYEOF
)
            if [[ -n "$minimax_key" ]] && ! echo "$minimax_key" | grep -qE '请填入|请到'; then
                interactive_read "  共用 minimax 的 MINIMAX_API_KEY？[Y/n]: " reuse
                reuse="${reuse:-y}"
                if [[ "$reuse" =~ ^[Yy]$ ]]; then
                    new_env_json=$(echo "$new_env_json" | python3 - "$minimax_key" << 'PYEOF'
import json, sys
d = json.load(sys.stdin)
d['MINIMAX_API_KEY'] = sys.argv[1]
print(json.dumps(d))
PYEOF
)
                    echo "    ✅ 复用 minimax Key"
                    server_changed=true
                fi
            fi
        fi

        # 写回 claude.json（仅当有变更）
        if ! $server_changed; then
            echo "  无变更，跳过"
            echo ""
            continue
        fi
        local write_ok
        write_ok=$(python3 - "$MCP_CONF_FILE" "$name" "$new_env_json" "$new_args_str" "$disabled" << 'PYEOF'
import json, os, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
name = sys.argv[2]
new_env = json.loads(sys.argv[3])
new_args_str = sys.argv[4]
was_disabled = sys.argv[5]

for s in data['mcp_servers']:
    if s['name'] == name:
        if new_env and new_env != {}:
            s['env'] = {**s.get('env', {}), **new_env}
        if new_args_str:
            s['args'] = new_args_str.split()
        if was_disabled == 'true':
            s.pop('disabled', None)
            print(f"    ✅ 已启用 {name}")
        break

tmp = sys.argv[1] + '.tmp'
with open(tmp, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
os.replace(tmp, sys.argv[1])
print('ok')
PYEOF
)
        if [[ "$write_ok" == *"ok"* ]]; then
            updated=$((updated + 1))
        fi

        echo ""
    done <<< "$McpNames"

    if [[ $updated -gt 0 ]]; then
        good "✅ 已更新 $updated 个 MCP Key"
        echo ""

        SETTINGS_FILE="$HOME/.claude/settings.json"
        CONFIG_FILE="$HOME/.claude/.config.json"
        for f in "$SETTINGS_FILE" "$CONFIG_FILE"; do
            result=$(sync_to_settings "$f")
            if [[ "$result" == "ok" ]]; then
                good "✅ 已同步到 $(basename "$f")"
            else
                bad "❌ 同步失败 ($(basename "$f")): $result"
            fi
        done
    else
        info "未修改任何 Key"
    fi
}

# 执行对应操作：优先用命令行参数，没有则用配置文件 default_action
ACTION="${1:-$DEFAULT_ACTION}"
case "$ACTION" in
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
    keys)
        do_keys
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
                while IFS='|' read -r name desc mtype command args_str env_str disabled how_to_get; do
                    [[ -z "$name" ]] && continue
                    if [[ "$disabled" == "true" ]]; then
                        echo "$idx) $name [已禁用] - $desc"
                    elif [[ "$(is_registered "$name")" == "true" ]]; then
                        echo "$idx) $name [已注册] - $desc"
                    else
                        echo "$idx) $name [未注册] - $desc"
                    fi
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
        info "未知操作: $ACTION，执行安装"
        do_install
        ;;
esac

echo ""
title "✅ 完成"
echo "提示: claude mcp list 查看注册状态, init-mcp.sh keys 填 Key"

# 确保脚本正常退出
exit 0

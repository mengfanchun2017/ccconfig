#!/bin/bash
# init-mcp.sh — MCP 管理工具
#   bash init-mcp.sh          # 交互菜单
#   bash init-mcp.sh status   # 查看状态
#   bash init-mcp.sh sync     # 同步到运行环境
#   bash init-mcp.sh keys     # 交互填 Key
#   bash init-mcp.sh toggle <name> on|off|status  # 启停单个

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/path-helper.sh"
MCP_CONF_FILE="$(resolve_conf claude.json)" || exit 1
source "$SCRIPT_DIR/json-validate.sh"
try_assert_json "$MCP_CONF_FILE" mcp 2>/dev/null || { echo "❌ conf/claude.json schema 校验失败" >&2; exit 1; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'
good() { echo -e "  ${GREEN}$1${NC}"; }
bad()  { echo -e "  ${RED}$1${NC}"; }
warn() { echo -e "  ${YELLOW}$1${NC}"; }
info() { echo -e "  ${GRAY}$1${NC}"; }
interactive_read() { echo -n "$1"; read -r "$2" < /dev/tty; }

# ── JSON 读取 ──
read_mcp_list() {
    python3 - "$MCP_CONF_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
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
PYEOF
}

# ── 状态检查 ──
do_status() {
    echo ""
    echo -e "${CYAN}── MCP 状态 ──${NC}"

    # 读取运行时连接状态
    local -A mcp_status=()
    if command -v claude &>/dev/null; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local name="${line%%:*}"
            if [[ "$line" == *"✔ Connected"* ]]; then
                mcp_status["$name"]="connected"
            elif [[ "$line" == *"✘ Failed"* ]]; then
                mcp_status["$name"]="failed"
            else
                mcp_status["$name"]="unknown"
            fi
        done <<< "$(claude mcp list 2>/dev/null || true)"
    fi

    # 读取配置文件信息
    local ready=0 failed=0 dcnt=0
    while IFS='|' read -r name desc mtype command args_str env_str is_disabled how_to_get; do
        [[ -z "$name" ]] && continue
        if [[ "$is_disabled" == "true" ]]; then
            dcnt=$((dcnt + 1)); continue
        fi
        local st="${mcp_status[$name]:-missing}"
        case "$st" in
            connected) ready=$((ready + 1)) ;;
            failed)    failed=$((failed + 1)) ;;
            *)         failed=$((failed + 1)) ;;
        esac
    done <<< "$(read_mcp_list)"

    local total=$((ready + failed + dcnt))
    if [[ $failed -gt 0 ]]; then
        echo -e "  ${GREEN}✓ $ready 已连${NC}  ${RED}✘ $failed 失败${NC}  ${GRAY}○ $dcnt 禁用${NC}  (共 $total)"
    else
        echo -e "  ${GREEN}✓ $ready 已连${NC}  ${GRAY}○ $dcnt 禁用${NC}  (共 $total)"
    fi
    echo ""

    while IFS='|' read -r name desc mtype command args_str env_str is_disabled how_to_get; do
        [[ -z "$name" ]] && continue
        local ico="" col=""
        if [[ "$is_disabled" == "true" ]]; then
            ico="○"; col="$GRAY"
        else
            local st="${mcp_status[$name]:-missing}"
            case "$st" in
                connected) ico="✓"; col="$GREEN" ;;
                *)         ico="✘"; col="$RED" ;;
            esac
        fi
        echo -e "  ${col}${ico} ${name}${NC}  ${GRAY}$desc${NC}"
    done <<< "$(read_mcp_list)"
    echo ""
}

# ── 注册 MCP ──
register_mcp() {
    local name="$1" cmd="$2" args="$3"
    echo -n "  注册 $name ... "
    if claude mcp add -s user "$name" -- $cmd $args 2>&1; then
        good "ok"; return 0
    else
        if claude mcp list 2>/dev/null | grep -q "$name"; then
            info "已注册"; return 0
        fi; bad "fail"; return 1
    fi
}

# ── 同步 ──
do_sync() {
    echo -e "\n${CYAN}── 同步 MCP 配置 ──${NC}"
    local installed=0 skipped=0 failed=0
    while IFS='|' read -r name desc mtype command args_str env_str is_disabled how_to_get; do
        [[ -z "$name" ]] && continue
        [[ "$is_disabled" == "true" ]] && { skipped=$((skipped + 1)); continue; }
        if ! command -v claude &>/dev/null; then
            warn "  claude 未安装，跳过注册"; break
        fi
        if claude mcp list 2>/dev/null | grep -q "^${name}:" 2>/dev/null; then
            skipped=$((skipped + 1)); continue
        fi
        if [[ -n "$command" ]] && [[ -n "$args_str" ]]; then
            register_mcp "$name" "$command" "$args_str" >/dev/null 2>&1 && installed=$((installed + 1)) || failed=$((failed + 1))
        fi
    done <<< "$(read_mcp_list)"
    echo -e "  注册: ${GREEN}+$installed${NC} 跳过: ${GRAY}$skipped${NC} 失败: ${RED}$failed${NC}"
    while IFS='|' read -r name desc mtype command args_str env_str is_disabled how_to_get; do
        [[ -z "$name" ]] && continue; [[ "$is_disabled" == "true" ]] && continue
        if [[ -n "$env_str" ]] && [[ "$env_str" != "{}" ]]; then
            configure_mcp_env "$name" "$env_str" >/dev/null 2>&1 || true
        fi
    done <<< "$(read_mcp_list)"
    sync_to_settings "$HOME/.claude.json" >/dev/null 2>&1 && good "  ~/.claude.json 已同步" || warn "  ~/.claude.json 同步失败"
    do_status
    echo -e "  ${GRAY}配置 Key: bash lib/init-mcp.sh keys  管理: maintain.sh mcp config${NC}"
    echo ""
}

# ── 同步到 settings.json ──
sync_to_settings() {
    local settings_file="$1"
    python3 - "$HOME/.claude.json" "$MCP_CONF_FILE" "$settings_file" << 'PYEOF'
import json, sys, os
claude_json, conf_json, settings_file = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(claude_json) as f: claude_data = json.load(f)
except: claude_data = {}
with open(conf_json) as f: conf_data = json.load(f)
try:
    with open(settings_file) as f: settings_data = json.load(f)
except: settings_data = {}

ccpriv_dir = os.path.dirname(conf_json)
ccpriv_bridge = {}
for server in conf_data.get('mcp_servers', []):
    sname = server.get('name', '')
    bridge_path = os.path.join(ccpriv_dir, f'{sname}.json')
    if os.path.exists(bridge_path):
        try:
            with open(bridge_path) as bf: bridge = json.load(bf)
            tokens = bridge.get('tokens', {})
            if tokens:
                t = list(tokens.values())[0]
                ccpriv_bridge[sname] = {'project_ref': t.get('project_ref', ''), 'access_token': t.get('access_token', '')}
        except: pass

mcp_servers = {}
disabled_names = []
for server in conf_data.get('mcp_servers', []):
    name = server.get('name', '')
    if not name: continue
    mtype = server.get('type', 'stdio')
    entry = {'command': server.get('command', ''), 'args': list(server.get('args', [])), 'env': dict(server.get('env', {}))} if mtype == 'stdio' else {'type': mtype, 'url': server.get('url', ''), 'headers': server.get('headers', {})}
    if name in ccpriv_bridge:
        bridge = ccpriv_bridge[name]; new_args = []; skip_next = False
        for a in entry['args']:
            if skip_next:
                new_args.append(bridge['project_ref'] if '请填入' in a and 'project' in a else bridge['access_token'] if '请填入' in a and 'token' in a else a)
                skip_next = False; continue
            if a in ('--project-ref', '--access-token'): new_args.append(a); skip_next = True; continue
            new_args.append(bridge['access_token'] if '请填入' in a and 'token' in a else bridge['project_ref'] if '请填入' in a and 'project' in a else a)
        entry['args'] = new_args
    if server.get('disabled'):
        disabled_names.append(name); continue
    if name in claude_data.get('mcpServers', {}):
        existing = claude_data['mcpServers'][name]
        if existing.get('env'): entry['env'] = {**entry.get('env', {}), **existing['env']}
    if name in settings_data.get('mcpServers', {}):
        real_keys = {k: v for k, v in settings_data['mcpServers'][name].get('env', {}).items() if v and '请填入' not in str(v) and 'your key' not in str(v).lower() and '<your-' not in str(v)}
        if real_keys: entry['env'] = {**entry.get('env', {}), **real_keys}
    mcp_servers[name] = entry

settings_data['mcpServers'] = mcp_servers
if disabled_names: settings_data['disabledMcpServers'] = disabled_names
elif 'disabledMcpServers' in settings_data: del settings_data['disabledMcpServers']
if 'projects' not in settings_data: settings_data['projects'] = {}
for proj_path in list(settings_data['projects'].keys()):
    if disabled_names: settings_data['projects'][proj_path]['disabledMcpServers'] = disabled_names
    elif 'disabledMcpServers' in settings_data['projects'][proj_path]: del settings_data['projects'][proj_path]['disabledMcpServers']
if 'hooks' in claude_data:
    merged = settings_data.get('hooks', {})
    for ht, hl in claude_data['hooks'].items():
        if ht not in merged or not merged[ht]: merged[ht] = hl
    settings_data['hooks'] = merged
for k, v in conf_data.get('env', {}).items():
    settings_data.setdefault('env', {})
    if k not in settings_data['env']: settings_data['env'][k] = v
actual = settings_file
if os.path.islink(settings_file):
    actual = os.path.realpath(settings_file)
    if not os.path.exists(os.path.dirname(actual)): os.makedirs(os.path.dirname(actual), exist_ok=True)
tmp = actual + '.tmp'
with open(tmp, 'w') as f: json.dump(settings_data, f, indent=2)
os.replace(tmp, actual)
print('ok')
PYEOF
}

configure_mcp_env() {
    local name="$1" env_json="$2"
    local config_file="$HOME/.claude/.config.json"
    local c_env_str="$env_json"
    # 写 ~/.claude.json
    python3 -c "
import json, sys
path, name, env_str = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: data = json.load(f)
env = json.loads(env_str) if env_str and env_str != '{}' else {}
if env and name in data.get('mcpServers', {}):
    data['mcpServers'][name]['env'] = env
    tmp = path + '.tmp'
    with open(tmp, 'w') as f: json.dump(data, f, indent=2)
    os.replace(tmp, path)
" "$HOME/.claude.json" "$name" "$c_env_str" 2>/dev/null || true
    # 同步 ~/.claude/.config.json（运行时 MCP env）
    if [[ -f "$config_file" ]]; then
        python3 -c "
import json, sys
path, name, env_str = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: data = json.load(f)
env = json.loads(env_str) if env_str and env_str != '{}' else {}
if env and name in data.get('mcpServers', {}):
    data['mcpServers'][name]['env'] = env
    tmp = path + '.tmp'
    with open(tmp, 'w') as f: json.dump(data, f, indent=2)
    os.replace(tmp, path)
" "$config_file" "$name" "$c_env_str" 2>/dev/null || true
    fi
}

# ── 交互填 Key ──
do_keys() {
    echo -e "\n${CYAN}── 配置 MCP Key ──${NC}"
    echo ""

    # 第一阶段：列出所有有占位符的 MCP
    local idx=0 names=() descs=() env_strs=() how_tos=() disableds=()
    while IFS='|' read -r name desc mtype command args_str env_str is_disabled how_to_get; do
        [[ -z "$name" ]] && continue
        local ph
        ph=$(python3 -c "
import json, sys
env = json.loads(sys.argv[1])
keys = [k for k, v in env.items() if any(x in str(v) for x in ['请填入', '请到', 'your key', 'placeholder', '<your-'])]
print(' '.join(keys))
" "$env_str")
        [[ -z "$ph" ]] && continue
        idx=$((idx + 1))
        names+=("$name")
        descs+=("$desc")
        env_strs+=("$env_str")
        how_tos+=("$how_to_get")
        disableds+=("$is_disabled")
        local st="${GREEN}启用${NC}"; [[ "$is_disabled" == "true" ]] && st="${YELLOW}禁用${NC}"
        echo -e "  ${CYAN}$idx) $name${NC}  ${GRAY}$desc${NC}  ($st)"
        [[ -n "$how_to_get" ]] && echo -e "     ${GRAY}$how_to_get${NC}"
    done <<< "$(read_mcp_list)"

    if [[ $idx -eq 0 ]]; then
        echo "  没有需要配置的 MCP"
        return
    fi

    echo ""
    read -p "  选择序号（逗号分隔，回车跳过）: " selections < /dev/tty
    [[ -z "$selections" ]] && { echo "  跳过"; return; }

    # 第二阶段：逐个填选中的
    local updated=0
    for sel in ${selections//,/ }; do
        sel="$((sel))" 2>/dev/null || continue
        [[ $sel -lt 1 || $sel -gt $idx ]] && continue
        local i=$((sel - 1))
        local name="${names[$i]}" desc="${descs[$i]}" env_str="${env_strs[$i]}" how_to_get="${how_tos[$i]}" is_disabled="${disableds[$i]}"
        echo -e "\n  ${CYAN}═ $name${NC}  ${GRAY}$desc${NC}"
        [[ -n "$how_to_get" ]] && echo -e "    ${GRAY}$how_to_get${NC}"

        local changed=false
        if [[ "$is_disabled" == "true" ]]; then
            read -p "  当前禁用，启用？[y/N]: " yn < /dev/tty
            if [[ ! "$yn" =~ ^[Yy]$ ]]; then echo "  跳过"; continue; fi
            changed=true; is_disabled="false"
        fi

        local ph_keys
        ph_keys=$(python3 -c "
import json, sys
env = json.loads(sys.argv[1])
keys = [k for k, v in env.items() if any(x in str(v) for x in ['请填入', '请到', 'your key', 'placeholder', '<your-'])]
print('\n'.join(keys))
" "$env_str")
        local new_env_json="$env_str"
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            read -p "    $key: " val < /dev/tty
            if [[ -n "$val" ]]; then
                new_env_json=$(echo "$new_env_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d[sys.argv[1]] = sys.argv[2]
print(json.dumps(d))
" "$key" "$val")
                changed=true
            fi
        done <<< "$ph_keys"

        if [[ "$name" == "minimax-mcp" ]] && ! echo "$new_env_json" | grep -qE 'gk_live|sk-'; then
            local mk
            mk=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: data = json.load(f)
for s in data['mcp_servers']:
    if s['name'] == 'minimax': print(s.get('env', {}).get('MINIMAX_API_KEY', '')); break
" "$MCP_CONF_FILE" 2>/dev/null)
            if [[ -n "$mk" ]] && ! echo "$mk" | grep -qE '请填入|请到'; then
                new_env_json=$(echo "$new_env_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['MINIMAX_API_KEY'] = sys.argv[1]
print(json.dumps(d))
" "$mk")
                changed=true
            fi
        fi

        if ! $changed; then echo -e "  ${GRAY}无变更${NC}"; continue; fi
        python3 -c "
import json, os, sys
with open(sys.argv[1]) as f: data = json.load(f)
name, new_env_str, disabled = sys.argv[2], sys.argv[3], sys.argv[4]
new_env = json.loads(new_env_str) if new_env_str else {}
for s in data['mcp_servers']:
    if s['name'] == name:
        if new_env: s['env'] = {**s.get('env', {}), **new_env}
        if disabled == 'true': s.pop('disabled', None)
        break
tmp = sys.argv[1] + '.tmp'
with open(tmp, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False); f.write('\n')
os.replace(tmp, sys.argv[1])
" "$MCP_CONF_FILE" "$name" "$new_env_json" "$is_disabled"
        good "  ✅ $name"
        updated=$((updated + 1))
    done

    if [[ $updated -gt 0 ]]; then
        echo ""; good "✅ 已更新 $updated 个 MCP Key"
        do_sync
    fi
}

# ── 启停单个 ──
do_toggle() {
    local name="${1:-}" action="${2:-}"
    if [[ -z "$name" ]] || [[ -z "$action" ]]; then
        echo "用法: bash init-mcp.sh toggle <name> {on|off|status}"
        echo ""
        while IFS='|' read -r n desc mtype command args_str env_str is_disabled how_to_get; do
            [[ -z "$n" ]] && continue
            local s="${GREEN}启用${NC}"; [[ "$is_disabled" == "true" ]] && s="${YELLOW}禁用${NC}"
            echo -e "  $n ($s)  $desc"
        done <<< "$(read_mcp_list)"
        return 0
    fi
    local line
    line=$(read_mcp_list | grep "^${name}|" || true)
    [[ -z "$line" ]] && { bad "❌ MCP '$name' 未定义"; return 1; }
    IFS='|' read -r sname desc mtype command args_str env_str is_disabled how_to_get <<< "$line"
    case "$action" in
        status)
            local s="${YELLOW}禁用${NC}"; [[ "$is_disabled" != "true" ]] && s="${GREEN}启用${NC}"
            echo -e "  $name: $s (conf)"
            local reg="${GRAY}未注册${NC}"
            claude mcp list 2>/dev/null | grep -q "^${name}:" && reg="${GREEN}已注册${NC}"
            echo -e "  $name: $reg (~/.claude.json)"
            ;;
        on)
            python3 -c "
import json, os, sys
path, name = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
found = False
for s in data.get('mcp_servers', []):
    if s.get('name') == name and s.pop('disabled', None):
        found = True
        break
if not found:
    exit(0)
tmp = path + '.tmp'
with open(tmp, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False); f.write('\n')
os.replace(tmp, path)
" "$MCP_CONF_FILE" "$name"
            echo -n "  注册 $name ... "
            if claude mcp add -s user "$name" -- $command $args_str 2>&1; then good "ok"; else bad "fail"; return 1; fi
            if [[ "$mtype" == "stdio" ]] && [[ -n "$env_str" ]] && [[ "$env_str" != "{}" ]]; then
                configure_mcp_env "$name" "$env_str" >/dev/null 2>&1 || true
            fi
            ;;
        off)
            python3 - "$MCP_CONF_FILE" "$name" << 'PYEOF'
import json, os, sys
path, name = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
for s in data.get('mcp_servers', []):
    if s.get('name') == name and not s.get('disabled'):
        s['disabled'] = True
        tmp = path + '.tmp'
        with open(tmp, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False); f.write('\n')
        os.replace(tmp, path)
        break
PYEOF
            claude mcp remove -s user "$name" 2>/dev/null && good "  ✅ $name 已移除" || info "  未注册"
            ;;
    esac
}

# ── 交互菜单 ──
do_menu() {
    local cmd=""
    while true; do
        clear 2>/dev/null || true
        do_status
        echo -e "${CYAN}── MCP 配置 ──${NC}"
        echo ""
        echo "  1) 查看状态"
        echo "  2) 同步到运行环境"
        echo "  3) 配置 Key（交互）"
        echo "  4) 启停单个 MCP"
        echo ""
        echo "  0) 退出"
        echo ""
        read -p "  选择 [0-4]: " cmd
        case "$cmd" in
            1) do_status; read -p "  按回车继续..." dummy ;;
            2) do_sync; read -p "  按回车继续..." dummy ;;
            3) do_keys; read -p "  按回车继续..." dummy ;;
            4)
                echo ""; echo -e "${CYAN}── 启停 MCP ──${NC}"
                while IFS='|' read -r n desc mtype command args_str env_str is_disabled how_to_get; do
                    [[ -z "$n" ]] && continue
                    local s="${GREEN}启用${NC}"; [[ "$is_disabled" == "true" ]] && s="${YELLOW}禁用${NC}"
                    echo -e "  $n ($s)  $desc"
                done <<< "$(read_mcp_list)"
                echo ""
                read -p "  MCP 名称: " tname < /dev/tty
                read -p "  操作 (on/off): " tact < /dev/tty
                do_toggle "$tname" "$tact"
                read -p "  按回车继续..." dummy
                ;;
            0) echo ""; exit 0 ;;
        esac
    done
}

# ── 入口 ──
if ! command -v claude &>/dev/null; then
    if [[ "${1:-}" == "sync" ]]; then
        warn "claude 未安装，仅同步配置文件"
        sync_to_settings "$HOME/.claude.json" >/dev/null 2>&1 && good "  ~/.claude.json 已同步"
        exit 0
    fi
fi

case "${1:-}" in
    status)   do_status ;;
    sync)     do_sync ;;
    keys)     do_keys ;;
    toggle)   shift; do_toggle "$@" ;;
    ""|menu)  do_menu ;;
    *)        echo "用法: bash init-mcp.sh [status|sync|keys|toggle]; 无参数=交互菜单"; exit 1 ;;
esac

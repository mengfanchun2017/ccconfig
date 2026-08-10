#!/bin/bash
# getnote-switch.sh — getnote MCP 账号切换
# 数据源: ccprivate/conf/claude.json
#   getnote_accounts[]    账号列表（每项含 name/api_key/client_id/description/enabled）
#   getnote_default       当前活跃账号名
#   mcp_servers[getnote].env  单实例 fallback（向后兼容无 getnote_accounts 时的旧部署）
#
# 切换 = 改 ~/.claude.json mcpServers.getnote.env → 提示重启 claude session 让新 env 生效
# 持久化 = -p 写 ccprivate getnote_default 字段
#
# 使用：
#   bash getnote-switch.sh                # 显示当前活跃账号
#   bash getnote-switch.sh --list         # 列出所有账号
#   bash getnote-switch.sh <name>         # 切换到指定账号（仅本 session env）
#   bash getnote-switch.sh <name> -p      # 切换并持久化（写 ccprivate，跨机器生效）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/path-helper.sh"
source "$CCCONFIG_DIR/lib/dry-run.sh"
CONF_FILE="$(resolve_conf claude.json)" || exit 1
RUNTIME_JSON="$HOME/.claude.json"
MARKER_FILE="$HOME/.getnote-account"

source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'
}

# ── 解析所有 getnote 账号 ──
# 优先 getnote_accounts[]，否则从 mcp_servers[getnote].env 推断一个 fallback 账号
parse_accounts() {
    python3 - "$CONF_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
except Exception as e:
    print(f"ERROR:{e}", file=sys.stderr)
    sys.exit(1)

accounts = data.get('getnote_accounts')
default_name = data.get('getnote_default', '')

if not accounts:
    # Fallback: 从 mcp_servers[getnote].env 推断一个账号
    for s in data.get('mcp_servers', []):
        if s.get('name') == 'getnote':
            env = s.get('env', {})
            ak = env.get('GETNOTE_API_KEY', '')
            cid = env.get('GETNOTE_CLIENT_ID', '')
            if ak and '请' not in ak and '<your' not in ak:
                # 单 entry inline → 包装为 accounts[]
                accounts = [{
                    'name': default_name or 'default',
                    'description': s.get('description', '默认账号（mcp_servers[getnote].env）'),
                    'api_key': ak,
                    'client_id': cid,
                    'enabled': True,
                    'source': 'inline',
                }]
                default_name = default_name or 'default'
            break

print(json.dumps({
    'accounts': accounts or [],
    'default': default_name,
}, ensure_ascii=False))
PYEOF
}

# ── 检测当前活跃账号（从 ~/.claude.json mcpServers.getnote.env 的 api_key 反查 name） ──
detect_current() {
    local runtime_json="$RUNTIME_JSON"
    [ -f "$runtime_json" ] || { echo ""; return; }

    local cur_key
    cur_key=$(python3 -c "
import json, os
p = '$runtime_json'
real = os.path.realpath(p)
with open(real) as f: d = json.load(f)
print(d.get('mcpServers', {}).get('getnote', {}).get('env', {}).get('GETNOTE_API_KEY', ''))
" 2>/dev/null) || cur_key=""
    [ -z "$cur_key" ] && { echo ""; return; }

    # 用 api_key 前 16 位匹配（避免泄露完整 key）
    local key_prefix="${cur_key:0:16}"
    local accounts_json="$1"
    python3 -c "
import json, sys
d = json.loads(sys.argv[1])
target = '$key_prefix'
for a in d.get('accounts', []):
    if a.get('api_key', '').startswith(target):
        print(a.get('name', ''))
        break
" "$accounts_json" 2>/dev/null
}

# ── 显示当前账号 ──
show_current() {
    local accounts_json
    accounts_json="$(parse_accounts)"
    local cur
    cur="$(detect_current "$accounts_json")"

    local default_name
    default_name=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('default',''))" "$accounts_json" 2>/dev/null)

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${CYAN}  getnote MCP 当前账号${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo ""

    local cnt
    cnt=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1]).get('accounts',[])))" "$accounts_json")
    if [ "$cnt" -eq 0 ]; then
        echo -e "  账号:     ${YELLOW}无 getnote 配置${NC}"
        echo -e "  引导:     ${CYAN}bash ccconfig/option-getnote/init.sh${NC}"
        echo ""
        return
    fi

    if [ -n "$cur" ]; then
        echo -e "  运行时活跃:  ${GREEN}${cur}${NC}  ${GRAY}(~/.claude.json env)${NC}"
    else
        echo -e "  运行时活跃:  ${YELLOW}未匹配${NC}"
    fi
    if [ -n "$default_name" ]; then
        echo -e "  ccprivate 默认: ${GREEN}${default_name}${NC}"
        if [ "$default_name" = "$cur" ]; then
            echo -e "  同步状态:    ${GREEN}运行时 = ccprivate（一致）${NC}"
        else
            echo -e "  同步状态:    ${YELLOW}运行时≠ccprivate，需重启 session 或重跑切换${NC}"
        fi
    else
        echo -e "  ccprivate 默认: ${GRAY}未设置${NC}"
    fi

    local env_applied=""
    env_applied=$(python3 -c "
import json, os
p = '$RUNTIME_JSON'
if not os.path.exists(p): print('no'); exit()
real = os.path.realpath(p)
with open(real) as f: d = json.load(f)
v = d.get('mcpServers', {}).get('getnote', {}).get('env', {}).get('GETNOTE_API_KEY', '')
print('yes' if v and '请' not in v else 'placeholder')
" 2>/dev/null)
    if [ "$env_applied" = "yes" ]; then
        echo -e "  运行时 env:  ${GREEN}已注入${NC}"
    elif [ "$env_applied" = "placeholder" ]; then
        echo -e "  运行时 env:  ${YELLOW}占位符未替换${NC}"
    else
        echo -e "  运行时 env:  ${GRAY}未注册（bash init-mcp.sh sync）${NC}"
    fi

    echo ""
    echo -e "${GRAY}切换:  bash ccconfig/option-getnote/getnote-switch.sh <name> [-p]${NC}"
    echo -e "${GRAY}列表:  bash ccconfig/option-getnote/getnote-switch.sh --list${NC}"
    echo ""
}

# ── 列出所有账号 ──
list_accounts() {
    local accounts_json
    accounts_json="$(parse_accounts)"
    local cur
    cur="$(detect_current "$accounts_json")"
    local default_name
    default_name=$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('default',''))" "$accounts_json" 2>/dev/null)

    echo ""
    local cnt
    cnt=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1]).get('accounts',[])))" "$accounts_json")
    if [ "$cnt" -eq 0 ]; then
        echo -e "  ${YELLOW}无 getnote 账号${NC}"
        echo ""
        echo -e "  ${GRAY}添加: bash ccconfig/option-getnote/init.sh${NC}"
        echo ""
        return
    fi

    idx=0
    python3 - "$accounts_json" "$cur" << 'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
cur = sys.argv[2]
accounts = d.get('accounts', [])
for i, a in enumerate(accounts, 1):
    name = a.get('name', '?')
    desc = a.get('description', '')
    enabled = a.get('enabled', True)
    cid = a.get('client_id', '')
    key = a.get('api_key', '')
    cid_tail = cid[-4:] if len(cid) >= 4 else cid
    key_tail = key[-4:] if len(key) >= 4 else ''
    suffix = '  \033[1;32m[当前]\033[0m' if name == cur else ''
    n_suffix = '  \033[0;90m(禁用)\033[0m' if not enabled else ''
    info = f'  clientid {cid_tail}  key *{key_tail}' if cid_tail else ''
    print(f'  {i}) {name}  {info}{n_suffix}{suffix}')
PYEOF
    echo ""
    echo -e "  ${GRAY}切换: bash ccconfig/option-getnote/getnote-switch.sh <name> [-p]${NC}"
    echo ""
}

# ── 切换账号 ──
switch_account() {
    local target_name="$1"
    local do_persist=false
    if [ "${2:-}" = "-p" ] || [ "${2:-}" = "--persist" ]; then
        do_persist=true
    fi

    local accounts_json
    accounts_json="$(parse_accounts)"

    # 查找目标
    local target_line
    target_line=$(python3 - "$accounts_json" "$target_name" << 'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
for a in d.get('accounts', []):
    if a.get('name') == sys.argv[2]:
        print(json.dumps(a, ensure_ascii=False))
        break
PYEOF
    )

    if [ -z "$target_line" ]; then
        echo -e "${RED}✗ 未找到账号: ${target_name}${NC}"
        echo ""
        echo "可用账号："
        python3 - "$accounts_json" << 'PYEOF'
import json, sys
for a in json.loads(sys.argv[1]).get('accounts', []):
    print(f"  - {a.get('name','?')}")
PYEOF
        return 1
    fi

    local enabled
    enabled=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('enabled', True))" <<< "$target_line")
    if [ "$enabled" = "False" ]; then
        echo -e "${RED}✗ 账号 ${target_name} 已禁用${NC}"
        return 1
    fi

    local api_key client_id desc
    api_key=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('api_key',''))" <<< "$target_line")
    client_id=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('client_id',''))" <<< "$target_line")
    desc=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))" <<< "$target_line")

    # 写 ~/.claude.json mcpServers.getnote.env（如果 mcpServers 还没有 getnote entry，先注入 stub）
    if [ ! -f "$RUNTIME_JSON" ]; then
        echo -e "${RED}✗ $RUNTIME_JSON 不存在，请先跑: bash init-mcp.sh sync${NC}"
        return 1
    fi

    python3 - "$RUNTIME_JSON" "$api_key" "$client_id" << 'PYEOF'
import json, os, sys
path, api_key, client_id = sys.argv[1], sys.argv[2], sys.argv[3]
real = os.path.realpath(path)
with open(real) as f: d = json.load(f)
d.setdefault('mcpServers', {}).setdefault('getnote', {})
d['mcpServers']['getnote'].setdefault('command', 'npx')
d['mcpServers']['getnote'].setdefault('args', ['-y', '@getnote/mcp'])
d['mcpServers']['getnote']['env'] = {
    'GETNOTE_API_KEY': api_key,
    'GETNOTE_CLIENT_ID': client_id,
}
tmp = real + '.tmp'
with open(tmp, 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
os.replace(tmp, real)
print('ok')
PYEOF
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ 写入 $RUNTIME_JSON 失败${NC}"
        return 1
    fi

    # 写 marker（仅 session 范围）
    cat > "$MARKER_FILE" << EOF
name=$target_name
switchedAt=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    # 持久化到 ccprivate：写 getnote_default
    if $do_persist; then
        python3 - "$CONF_FILE" "$target_name" << 'PYEOF'
import json, os, sys
path, target = sys.argv[1], sys.argv[2]
real = os.path.realpath(path)
with open(real) as f: d = json.load(f)
d['getnote_default'] = target
tmp = real + '.tmp'
with open(tmp, 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
os.replace(tmp, real)
PYEOF
        echo -e "${GREEN}✓ 已持久化到 ccprivate（getnote_default=$target_name，auto-sync 上传）${NC}"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}  getnote 账号切换成功${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo ""
    echo -e "  账号:     ${GREEN}${target_name}${NC}"
    [ -n "$desc" ] && echo -e "  说明:     ${GRAY}${desc}${NC}"
    echo -e "  clientId: ${GRAY}${client_id:0:16}…${NC}"
    echo ""
    echo -e "  ${YELLOW}⚠ 需要重启 claude session 让新 env 生效：${NC}"
    echo -e "  ${CYAN}claude --resume 或新开会话${NC}"
    echo ""
    if $do_persist; then
        echo -e "  ccprivate: ${GREEN}已写入 getnote_default${NC}"
    else
        echo -e "  ccprivate: ${GRAY}未持久化（加 -p 写入跨机器生效）${NC}"
    fi
    echo ""
}

# ── 主入口 ──
main() {
    local arg="${1:-}"
    case "$arg" in
        --list|-l) list_accounts ;;
        --help|-h)
            echo "用法: getnote-switch.sh [name] [-p] [--list]"
            echo ""
            echo "  name        切换到指定账号（仅当前 session env）"
            echo "  name -p     切换并持久化到 ccprivate getnote_default"
            echo "  --list      列出所有账号"
            echo "  (无参数)    显示当前活跃账号"
            ;;
        "") show_current ;;
        *) switch_account "$@" ;;
    esac
}

main "$@"
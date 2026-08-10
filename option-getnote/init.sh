#!/bin/bash
# option-getnote/init.sh — 引导添加/删除 getnote 账号
# 数据写 ccprivate/conf/claude.json (getnote_accounts[] + getnote_default)
#
# 使用：
#   bash init.sh                  # 交互菜单
#   bash init.sh add              # 添加新账号
#   bash init.sh remove <name>    # 删除账号
#   bash init.sh list             # 列出账号（等价 getnote-switch.sh --list）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/path-helper.sh"
source "$CCCONFIG_DIR/lib/dry-run.sh"
source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'
}
source "$CCCONFIG_DIR/lib/interact.sh"

CONF_FILE="$(resolve_conf claude.json)" || exit 1

# ── 添加账号 ──
do_add() {
    echo ""
    echo -e "${CYAN}── 添加 getnote 账号 ──${NC}"
    echo ""
    info "获取凭证: https://www.biji.com/openapi → 创建应用 → API Key(gk_live_xxx) + Client ID(cli_xxx)"
    echo ""

    local name; while true; do
        name=$(prompt "账号名 (personal/work/test)") || true
        [ -z "$name" ] && { err "账号名不能为空"; continue; }
        echo "$name" | grep -qE '[^a-zA-Z0-9_-]' && { err "仅允许字母数字_-_"; continue; }
        python3 - "$CONF_FILE" "$name" 2>/dev/null | grep -q '"name":' || break
        err "账号 $name 已存在"
    done

    local api_key; while true; do
        api_key=$(prompt "GETNOTE_API_KEY (gk_live_xxx)") || true
        [ -z "$api_key" ] && { err "不能为空"; continue; }
        break; done

    local client_id; while true; do
        client_id=$(prompt "GETNOTE_CLIENT_ID (cli_xxx)") || true
        [ -z "$client_id" ] && { err "不能为空"; continue; }
        break; done

    local desc; desc=$(prompt "说明（可选）") || true

    local as_default=false
    local cnt; cnt=$(python3 -c "import json; print(len(json.load(open('$CONF_FILE')).get('getnote_accounts',[])))" 2>/dev/null || echo "0")
    if [ "$cnt" = "0" ]; then
        as_default=true; info "首个账号，自动设为默认"
    elif confirm "设为 ccprivate 默认账号？" n; then
        as_default=true; fi

    # 写 ccprivate/conf/claude.json
    python3 - "$CONF_FILE" "$name" "$api_key" "$client_id" "$desc" "$as_default" << 'PYEOF'
import json, os, sys
path, name, api_key, client_id, desc, as_default = sys.argv[1:7]
real = os.path.realpath(path)
with open(real) as f: d = json.load(f)
d.setdefault('getnote_accounts', [])
d['getnote_accounts'].append({
    'name': name,
    'description': desc,
    'api_key': api_key,
    'client_id': client_id,
    'enabled': True,
})
if as_default == 'true' or not d.get('getnote_default'):
    d['getnote_default'] = name

# 同时把 inline env 占位符更新（向后兼容 — 让 init-mcp.sh keys 检测到不需要重填）
for s in d.get('mcp_servers', []):
    if s.get('name') == 'getnote':
        s.setdefault('env', {})
        s['env']['GETNOTE_API_KEY'] = api_key
        s['env']['GETNOTE_CLIENT_ID'] = client_id
        break

tmp = real + '.tmp'
with open(tmp, 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
os.replace(tmp, real)
print('ok')
PYEOF

    ok "账号 $name 已添加"
    $as_default && ok "已设为 ccprivate 默认" || info "未设为默认"
    echo ""
    info "切换到该账号: bash ccconfig/option-getnote/getnote-switch.sh $name -p"
    echo ""
}

# ── 删除账号 ──
do_remove() {
    local target="${1:-}"
    if [ -z "$target" ]; then
        echo ""
        echo -e "${CYAN}── 删除 getnote 账号 ──${NC}"
        bash "$SCRIPT_DIR/getnote-switch.sh" --list
        echo ""
        read -p "  输入要删除的账号名: " target < /dev/tty
    fi

    local cnt
    cnt=$(python3 - "$CONF_FILE" "$target" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
print(len(d.get('getnote_accounts', [])))
PYEOF
    )
    if [ "$cnt" -eq 0 ]; then
        err "无 getnote_accounts 配置"; return 1
    fi

    local default_name
    default_name=$(python3 -c "
import json
with open('$CONF_FILE') as f: d = json.load(f)
print(d.get('getnote_default', ''))")

    if [ "$target" = "$default_name" ]; then
        warn "该账号是 ccprivate 默认，删除后需要重新指定默认"
        if ! confirm "仍要删除？" n; then info "取消"; return 0; fi
    fi
    if ! confirm "确认删除 $target？" n; then info "取消"; return 0; fi

    python3 - "$CONF_FILE" "$target" "$default_name" << 'PYEOF'
import json, os, sys
path, target, default_name = sys.argv[1], sys.argv[2], sys.argv[3]
real = os.path.realpath(path)
with open(real) as f: d = json.load(f)
before = len(d.get('getnote_accounts', []))
d['getnote_accounts'] = [a for a in d.get('getnote_accounts', []) if a.get('name') != target]
after = len(d['getnote_accounts'])
if before == after:
    print('not_found'); sys.exit(0)
if d.get('getnote_default') == target:
    d['getnote_default'] = d['getnote_accounts'][0]['name'] if d['getnote_accounts'] else ''
tmp = real + '.tmp'
with open(tmp, 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
os.replace(tmp, real)
print('ok')
PYEOF

    if [ $? -eq 0 ]; then
        ok "账号 $target 已删除"
        local new_default
        new_default=$(python3 -c "import json; print(json.load(open('$CONF_FILE')).get('getnote_default',''))")
        [ -n "$new_default" ] && info "新默认: $new_default" || warn "无账号剩余，inline env 仍保留旧 key"
    else
        err "账号 $target 未找到"
        return 1
    fi
}

# ── 主入口 ──
case "${1:-}" in
    add|a)    do_add ;;
    remove|rm|r) shift; do_remove "${1:-}" ;;
    list|ls|l) bash "$SCRIPT_DIR/getnote-switch.sh" --list ;;
    ""|menu)
        while true; do
            local c; c=$(menu_select "getnote 账号管理" \
                "1) 添加账号" "2) 删除账号" "3) 列出账号" "4) 切换账号" "0) 退出")
            [[ -z "$c" ]] && continue
            case "${c:0:1}" in
                1) do_add ;;
                2) do_remove ;;
                3) bash "$SCRIPT_DIR/getnote-switch.sh" --list ;;
                4)
                    bash "$SCRIPT_DIR/getnote-switch.sh" --list
                    local target; target=$(prompt "账号名") || continue
                    if [ -n "$target" ]; then
                        if confirm "持久化到 ccprivate？" n; then
                            bash "$SCRIPT_DIR/getnote-switch.sh" "$target" -p
                        else
                            bash "$SCRIPT_DIR/getnote-switch.sh" "$target"
                        fi
                    fi
                    ;;
                0|"") exit 0 ;;
                *) warn "无效选项" ;;
            esac
        done
        ;;
    *) err "用法: bash init.sh [add|remove <name>|list|menu]"; exit 1 ;;
esac
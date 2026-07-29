#!/bin/bash
# ccconfig/option-cconnect/init.sh — 飞书 cc-connect 初始化（可选组件）
#
# cc-connect: 接收飞书消息的 Bridge（WebSocket 长连接，systemd --user 服务）
# 配置源: ../conf/feishu.json（单一真相源）
#
# 用法：
#   bash ccconfig/option-cconnect/init.sh           # 安装 + 生成 config.toml + 启服务
#   bash ccconfig/option-cconnect/init.sh --status  # 服务状态
#   bash ccconfig/option-cconnect/init.sh --list    # 列出可用机器人

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/path-helper.sh"
FEISHU_CONF="$(resolve_conf feishu.json)" || exit 1

CC_CONNECT_VERSION=$(get_cconnect_version)
CC_CONNECT_BIN="$HOME/.local/bin/cc-connect"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad()  { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
info() { echo -e "${GRAY}$1${NC}"; }

# ========== JSON 读取 ==========
get_apps() {
    python3 - "$FEISHU_CONF" << 'PYEOF' 2>/dev/null
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
for app in data.get('apps', []):
    print(json.dumps(app))
PYEOF
}

# ========== 环境检测 ==========
detect_env() {
    echo -e "${CYAN}── 环境检测 ──${NC}"
    echo -n "  Node.js ... "
    command -v node &>/dev/null && good "✓ $(node --version)" || warn "○ 未安装"
    echo -n "  systemd ... "
    systemctl --user daemon-reload 2>/dev/null && good "✓" || warn "○ 不可用"
    command -v loginctl &>/dev/null && loginctl enable-linger "$USER" 2>/dev/null || true
    echo ""
}

# ========== cc-connect 安装 ==========
install_cconnect() {
    echo -e "${CYAN}── cc-connect v${CC_CONNECT_VERSION} ──${NC}"
    if [ -x "$CC_CONNECT_BIN" ]; then
        local ver=$("$CC_CONNECT_BIN" --version 2>/dev/null | head -1 || echo "unknown")
        good "  ✓ 已安装: $ver"
        return 0
    fi

    local url="https://github.com/chenhg5/cc-connect/releases/download/v${CC_CONNECT_VERSION}/cc-connect-v${CC_CONNECT_VERSION}-linux-amd64.tar.gz"
    local tmp="/tmp/cc-connect-$$"
    mkdir -p "$tmp" "$HOME/.local/bin"

    echo -n "  下载 ... "
    if curl -fsSL --connect-timeout 10 --max-time 120 --retry 2 "$url" -o "$tmp/cc-connect.tar.gz" 2>/dev/null || \
       curl -fsSL --connect-timeout 10 --max-time 120 --retry 2 --http1.1 "$url" -o "$tmp/cc-connect.tar.gz" 2>/dev/null; then
        tar -xzf "$tmp/cc-connect.tar.gz" -C "$tmp"
        local bin=$(find "$tmp" -maxdepth 2 -type f -exec test -x {} \; -print | head -1)
        [ -n "$bin" ] && { cp "$bin" "$CC_CONNECT_BIN"; chmod +x "$CC_CONNECT_BIN"; good "✅"; } || { bad "❌ 未找到二进制"; return 1; }
    else
        bad "❌ 下载失败"
        warn "  手动: https://github.com/chenhg5/cc-connect/releases"
        return 1
    fi
    rm -rf "$tmp"
}

generate_toml() {
    echo -e "${CYAN}── 生成 config.toml ──${NC}"
    local config_path="$HOME/cc-connect/config.toml"
    mkdir -p "$(dirname "$config_path")"

    python3 - "$FEISHU_CONF" "$config_path" << 'PYEOF'
import json, sys, os

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

config_path = sys.argv[2]
apps = data.get('apps', [])

lines = ['# ╔══════════════════════════════════════════════════╗',
         '# ║  cc-connect 配置 — 由 ccconfig/option-cconnect/init.sh 生成 ║',
         '# ║  修改: 编辑 ~/git/ccprivate/conf/feishu.json         ║',
         '# ╚══════════════════════════════════════════════════╝', '',
         '[log]', 'level = "info"', '']

enabled_count = 0
for app in apps:
    cc = app.get('ccConnect', {})
    if not cc.get('enabled'): continue
    enabled_count += 1

    name = app['name']
    app_id, app_secret = app['appId'], app['appSecret']
    work_dir = app.get('workDir', os.path.expanduser('~/git'))
    perms, opts = cc.get('permissions', {}), cc.get('options', {})
    timeout_ms = cc.get('timeoutMs', 3600000)

    os.makedirs(work_dir, exist_ok=True)

    lines.append(f'# ═══ {name}: {app.get("description", "")} ═══')
    lines.append('[[projects]]')
    lines.append(f'name = "{name}-main"')
    lines.append('[projects.agent]')
    lines.append('type = "claudecode"')
    lines.append('[projects.agent.options]')
    lines.append(f'work_dir = "{work_dir}"')
    lines.append(f'mode = "{opts.get("mode", "default")}"')
    lines.append(f'timeout_ms = {timeout_ms}')
    lines.append('')

    ccd = app.get('claudeConfigDir', '')
    if ccd:
        d = os.path.expanduser(ccd)
        os.makedirs(d, exist_ok=True)
        lines.append('[projects.agent.env]')
        lines.append(f'CLAUDE_CONFIG_DIR = "{d}"')
        lines.append('')

    aids = perms.get('adminOpenIds', [])
    dcmds = perms.get('disabledCommands', [])
    rl = perms.get('rateLimit', {})
    if aids:
        lines.append('[projects.users]')
        lines.append('default_role = "member"')
        lines.append('[projects.users.roles.admin]')
        lines.append(f'user_ids = {json.dumps(aids)}')
        lines.append(f'disabled_commands = {json.dumps(dcmds)}')
        lines.append(f'rate_limit = {{ max_messages = {rl.get("maxMessages", 100)}, window_secs = {rl.get("windowSecs", 60)} }}')
        lines.append(f'admin_from = "{",".join(aids)}"')
        lines.append('')

    lines.append('[[projects.platforms]]')
    lines.append('type = "feishu"')
    lines.append('[projects.platforms.options]')
    lines.append(f'app_id = "{app_id}"')
    lines.append(f'app_secret = "{app_secret}"')
    lines.append(f'allow_from = "{perms.get("allowFrom", "*")}"')
    if opts.get('threadIsolation', True): lines.append('thread_isolation = true')
    if opts.get('groupOnly'): lines.append('group_only = true')
    if opts.get('groupReplyAll'): lines.append('group_reply_all = true')
    lines.append('')

with open(config_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))

print(f'  ✅ {config_path} ({enabled_count}/{len(apps)} 机器人启用)')
PYEOF
}

setup_service() {
    echo -e "${CYAN}── systemd 服务 ──${NC}"
    local node_bin=$(find_node_bin)
    local sf="$HOME/.config/systemd/user/cc-connect.service"
    mkdir -p "$HOME/.config/systemd/user"

    cat > "$sf" << SERVICEOF
[Unit]
Description=CC-Connect - AI Bridge (Feishu Bot)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'export PATH=\$(echo "\$PATH" | tr ":" "\\n" | grep -v "^/mnt/" | tr "\\n" ":" | sed "s/:\$//"); exec ${CC_CONNECT_BIN} -config ${HOME}/cc-connect/config.toml'
Restart=on-failure
RestartSec=10
Environment=PATH=${HOME}/.local/bin:${node_bin}:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
SERVICEOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable cc-connect 2>/dev/null || true
    systemctl --user restart cc-connect 2>&1 && good "  ✅ 服务运行中" || warn "  ⚠ 启动失败"
}

run_cconnect() {
    detect_env
    # 预检：检查是否有占位符 App ID/Secret
    local placeholder_apps
    placeholder_apps=$(python3 - "$FEISHU_CONF" << 'PYEOF' 2>/dev/null
import json, sys
PLACEHOLDER = ['请填入', '请到', '请替换', 'your key', 'your_key', 'placeholder', 'changeme', '<your-', 'your-app-name']
def is_ph(val):
    if not val or not isinstance(val, str): return True
    for p in PLACEHOLDER:
        if p.lower() in val.lower(): return True
    return False
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
apps = data.get('apps', [])
bad = [a.get('name','?') for a in apps if a.get('ccConnect',{}).get('enabled') and (is_ph(a.get('appId','')) or is_ph(a.get('appSecret','')))]
if bad:
    print('\n'.join(bad))
PYEOF
    )
    if [ -n "$placeholder_apps" ]; then
        warn "以下 cc-connect 账号的 App ID/Secret 仍为占位符，需先填写:"
        echo "$placeholder_apps" | while read -r name; do
            echo -e "    ${YELLOW}→${NC} $name"
        done
        echo ""
        info "编辑 feishu.json 填入真实值: vim $FEISHU_CONF"
        info "获取地址: https://open.feishu.cn/app"
        return 1
    fi

    install_cconnect || return 1
    echo ""
    generate_toml
    setup_service
    echo ""
    bash "$SCRIPT_DIR/bot-status.sh"
}

list_apps() {
    echo -e "${CYAN}可用飞书应用（ccConnect.enabled）${NC}\n"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        echo "$line" | python3 -c "
import json,sys
a=json.load(sys.stdin)
cc=a.get('ccConnect',{})
if cc.get('enabled'):
    print(f'  {a[\"name\"]:12s}  {a.get(\"description\",\"\")}')
    print(f'  {\"\":12s}  {a[\"appId\"][:22]}...')
" 2>/dev/null
    done < <(get_apps)
    echo ""
}

show_status() {
    # 第一行：无 ANSI 状态行（供 init-option.sh 解析）
    if ! command -v cc-connect &>/dev/null; then
        echo "MISSING cc-connect 未安装"
        return 0
    fi
    local ver=$(cc-connect --version 2>/dev/null | head -1 | sed 's/^[^0-9]*//')
    local running="false"
    if systemctl --user is-active cc-connect.service &>/dev/null 2>&1 || pgrep -f "cc-connect" >/dev/null 2>&1; then
        running="true"
    fi

    # 检查 feishu.json 是否有占位符 key
    local has_ph="false"
    if [ -f "$FEISHU_CONF" ]; then
        has_ph=$(python3 -c "
import json, sys
PLACEHOLDER = ['请填入','请到','请替换','your key','your_key','placeholder','changeme','<your-','your-app-name']
def is_ph(v):
    if not v or not isinstance(v, str): return True
    return any(p in v.lower() for p in PLACEHOLDER)
with open('$FEISHU_CONF') as f: d = json.load(f)
print('true' if any(is_ph(a.get('appId','')) or is_ph(a.get('appSecret','')) for a in d.get('apps',[]) if a.get('ccConnect',{}).get('enabled')) else 'false')
" 2>/dev/null || echo "false")
    fi

    if [ "$has_ph" = "true" ]; then
        echo "WARN cc-connect v${ver:-?} (未运行) — feishu.json 含占位符"
    elif [ "$running" = "true" ]; then
        echo "OK cc-connect v${ver:-?} 运行中"
    else
        echo "WARN cc-connect v${ver:-?} (已装未运行)"
    fi

    # 后续行：彩色详情（--status 直接展示用）
    echo ""
    echo -e "${CYAN}── cc-connect 详情 ──${NC}"
    echo -n "  二进制 ... "
    if command -v cc-connect &>/dev/null; then
        echo -e "${GREEN}✅${NC} $(cc-connect --version 2>/dev/null | head -1 || echo '已安装')"
    else
        echo -e "${RED}❌${NC} 未安装"
    fi
    echo -n "  服务 ... "
    if [ "$running" = "true" ]; then
        echo -e "${GREEN}●${NC} 运行中"
    else
        echo -e "${YELLOW}○${NC} 未运行"
    fi
    if [ "$has_ph" = "true" ]; then
        echo -e "  ${YELLOW}!${NC} feishu.json 仍含占位符 → 编辑 ${GRAY}$FEISHU_CONF${NC}"
    fi
    bash "$SCRIPT_DIR/bot-status.sh" 2>/dev/null | grep -v -E "^\[1mcc-connect 服务\[0m|^\[1m机器人列表\[0m|^$" | head -20
}

# ========== 主程序 ==========
case "${1:-}" in
    --list|-ls)
        list_apps
        ;;
    --status|-s)
        show_status
        ;;
    --help|-h)
        echo "用法: $0 [--list|--status]"
        echo ""
        echo "  (无参数)    安装 cc-connect + 生成 config.toml + 启 systemd 服务"
        echo "  --list      列出可用机器人"
        echo "  --status    服务状态"
        ;;
    "")
        run_cconnect
        echo ""
        good "✅ cc-connect 配置完成"
        echo ""
        echo "后续操作:"
        echo "  机器人状态:    bash ccconfig/option-cconnect/bot-status.sh"
        echo "  启停机器人:    bash ccconfig/option-cconnect/bot-toggle.sh <name> --enable|--disable"
        echo "  服务管理:      systemctl --user status cc-connect"
        echo ""
        echo -e "  ${YELLOW}💡 可选: feishu MCP Bridge（bot 消息）${NC}"
        echo -e "     ${CYAN}bash ccconfig/option-cconnect/mcp-bridge/install.sh${NC}"
        ;;
    *)
        bad "❌ 未知参数: $1"
        exit 1
        ;;
esac
#!/bin/bash
# ccconfig/option-bridge/init.sh — 飞书 Bridge 初始化（可选组件）
#
# 管理 lark-cli（创建飞书文档）和 cc-connect（接收飞书消息）
# 配置源: ../conf/feishu.json（单一真相源）
#
# 设计原则：
#   - lark-cli: 每台电脑都需要（用于创建飞书文档/日历/任务）
#   - cc-connect: 仅接收飞书消息的机器需要（台式机常驻）
#   - mcp-bridge: 可选，feishu MCP 安装脚本（bot 消息），与 cc-connect 配对使用
#
# 用法：
#   bash ccconfig/option-bridge/init.sh              # 交互式（推荐）
#   bash ccconfig/option-bridge/init.sh --lark-cli   # 仅 lark-cli（非交互）
#   bash ccconfig/option-bridge/init.sh --cc-connect # 仅 cc-connect（非交互）
#   bash ccconfig/option-bridge/init.sh --all        # 全部（非交互）
#   bash ccconfig/option-bridge/init.sh --list       # 列出所有账号

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FEISHU_CONF="$CCCONFIG_DIR/conf/feishu.json"

source "$CCCONFIG_DIR/lib/path-helper.sh"
export PATH="$(find_node_bin):${HOME}/.local/bin:$PATH"
export LARK_CLI_NO_PROXY=1

CC_CONNECT_VERSION=$(get_cconnect_version)
CC_CONNECT_BIN="$HOME/.local/bin/cc-connect"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad()  { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
info() { echo -e "${GRAY}$1${NC}"; }

banner() {
    echo -e "${CYAN}"
    echo "飞书 Bridge 初始化（可选组件）"
    echo "═══════════════════════════════════"
    echo "    lark-cli (文档) + cc-connect (消息)"
    echo "$NC"
}

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
    command -v node &>/dev/null && good "✓ $(node --version)" || { bad "❌"; return 1; }
    echo -n "  systemd ... "
    systemctl --user daemon-reload 2>/dev/null && good "✓" || warn "○ 不可用"
    command -v loginctl &>/dev/null && loginctl enable-linger "$USER" 2>/dev/null || true
    echo ""
}

# ========== lark-cli ==========
install_lark_cli() {
    echo -e "${CYAN}── lark-cli ──${NC}"
    if command -v lark-cli &>/dev/null; then
        good "  ✓ 已安装"
        return 0
    fi
    echo -n "  npm install @larksuite/cli ... "
    npm install -g @larksuite/cli 2>&1 && good "✅" || { bad "❌"; return 1; }

    local npm_root=$(npm root -g 2>/dev/null || echo "$(dirname "$(find_node_bin)")/lib/node_modules")
    for src in "$npm_root/@larksuite/cli/bin/lark-cli.js" "$npm_root/@larksuite/cli/bin/cli.js" "$npm_root/@larksuite/cli/scripts/run.js"; do
        [ -f "$src" ] && { mkdir -p "$HOME/.local/bin"; rm -f "$HOME/.local/bin/lark-cli"; ln -sf "$src" "$HOME/.local/bin/lark-cli"; break; }
    done
}

setup_lark_cli_account() {
    local name="$1" brand="$2" app_id="$3" app_secret="$4" config_dir="$5"
    config_dir="${config_dir/#\~/$HOME}"
    mkdir -p "$config_dir"
    export LARKSUITE_CLI_CONFIG_DIR="$config_dir"

    local cf="${config_dir}/config.json"
    if [ -f "$cf" ]; then
        good "  ✓ ${name}"
        lark-cli auth status 2>/dev/null | grep -q "Authorized" || warn "    ○ 待授权: LARKSUITE_CLI_CONFIG_DIR=${config_dir} lark-cli auth login --recommend"
        return 0
    fi
    echo -n "  → ${name} ... "
    echo "$app_secret" | lark-cli config init --app-id "$app_id" --app-secret-stdin --brand "$brand" 2>&1 && good "✅" || bad "❌"
}

run_lark_cli() {
    install_lark_cli || return 1
    echo ""

    local apps=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        local lc_enabled=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('larkCli',{}).get('enabled',False))" 2>/dev/null)
        [ "$lc_enabled" = "True" ] && apps+=("$line")
    done < <(get_apps)

    if [ ${#apps[@]} -eq 0 ]; then
        info "  无启用的 lark-cli 账号"
        return 0
    fi

    echo -e "${CYAN}配置 lark-cli 账号 (${#apps[@]} 个):${NC}"
    for line in "${apps[@]}"; do
        local name=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])" 2>/dev/null)
        local brand=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('brand','feishu'))" 2>/dev/null)
        local app_id=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['appId'])" 2>/dev/null)
        local app_secret=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['appSecret'])" 2>/dev/null)
        local lc=$(echo "$line" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('larkCli',{})))" 2>/dev/null)
        local config_dir=$(echo "$lc" | python3 -c "import json,sys; print(json.load(sys.stdin).get('configDir','~/.lark-cli'))" 2>/dev/null || echo "~/.lark-cli")
        setup_lark_cli_account "$name" "$brand" "$app_id" "$app_secret" "$config_dir"
    done
}

# ========== cc-connect ==========
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
    if curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp/cc-connect.tar.gz" 2>/dev/null; then
        tar -xzf "$tmp/cc-connect.tar.gz" -C "$tmp"
        local bin=$(find "$tmp" -name "cc-connect" -type f | head -1)
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
         '# ║  cc-connect 配置 — 由 ccconfig/option-bridge/init.sh 生成 ║',
         '# ║  修改: 编辑 ccconfig/conf/feishu.json              ║',
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
    install_cconnect || return 1
    echo ""
    generate_toml
    setup_service
    echo ""
    bash "$SCRIPT_DIR/bot-status.sh"
}

# ========== 列表 ==========
list_apps() {
    echo -e "${CYAN}可用飞书应用${NC}\n"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        echo "$line" | python3 -c "
import json,sys
a=json.load(sys.stdin)
lc=a.get('larkCli',{}); cc=a.get('ccConnect',{})
print(f'  {a[\"name\"]:12s}  lark-cli: {\"✅\" if lc.get(\"enabled\") else \"❌\"}  cc-connect: {\"✅\" if cc.get(\"enabled\") else \"❌\"}  {a.get(\"description\",\"\")}')
print(f'  {\"\":12s}  {a[\"appId\"][:22]}...')
" 2>/dev/null
    done < <(get_apps)
    echo ""
}

# ========== 交互式 ==========
interactive_mode() {
    banner
    detect_env || exit 1
    echo ""

    # --- lark-cli（默认 YES：每台电脑都要创建飞书文档） ---
    echo -e "${BOLD}lark-cli${NC} — 终端创建飞书文档/日历/任务"
    echo -e "  ${GRAY}推荐每台电脑都安装（包括笔记本）${NC}"
    echo ""
    read -p "  安装配置 lark-cli? [Y/n]: " lc_confirm
    lc_confirm="${lc_confirm:-y}"
    if [[ "$lc_confirm" =~ ^[Yy]$ ]]; then
        run_lark_cli
        echo ""
    else
        info "  跳过 lark-cli"
    fi

    # --- cc-connect（默认 NO：只有接收消息的机器需要） ---
    echo ""
    echo -e "${BOLD}cc-connect${NC} — 接收飞书消息的 Bridge（WebSocket 长连接）"
    echo -e "  ${GRAY}仅需在接收飞书消息的机器上配置（台式机常驻）${NC}"
    echo ""
    read -p "  安装配置 cc-connect? [y/N]: " cc_confirm
    cc_confirm="${cc_confirm:-n}"
    if [[ "$cc_confirm" =~ ^[Yy]$ ]]; then
        run_cconnect
    else
        info "  跳过 cc-connect"
    fi

    echo ""
    good "✅ 完成"
    echo ""
    echo "后续操作:"
    echo "  切换 lark-cli 账号:  bash ccconfig/option-bridge/lark-switch.sh <name>"
    echo "  查看机器人状态:     bash ccconfig/option-bridge/bot-status.sh"
    echo "  服务管理:           systemctl --user status cc-connect"
    echo ""
    echo -e "  ${YELLOW}💡 可选: feishu MCP Bridge（bot 消息）${NC}"
    echo -e "     ${CYAN}bash ccconfig/option-bridge/mcp-bridge/install.sh${NC}"
}

# ========== 主程序 ==========
main() {
    case "${1:-}" in
        --lark-cli|-l)
            detect_env || exit 1
            echo ""; run_lark_cli
            echo ""; good "✅ lark-cli 配置完成"
            ;;
        --cc-connect|-c)
            detect_env || exit 1
            echo ""; run_cconnect
            echo ""; good "✅ cc-connect 配置完成"
            ;;
        --all|-a)
            detect_env || exit 1
            echo ""; run_lark_cli
            echo ""; run_cconnect
            echo ""; good "✅ 飞书配置完成"
            ;;
        --list|-ls)
            list_apps
            ;;
        --status|-s)
            local has_lark=false has_bridge=false
            command -v lark-cli &>/dev/null && has_lark=true
            command -v cc-connect &>/dev/null && has_bridge=true
            if $has_lark && $has_bridge; then
                echo "OK lark-cli + Bridge"
            elif $has_lark; then
                echo "OK lark-cli 已配置"
            else
                echo "FAIL lark-cli 未安装"
            fi
            echo -e "${CYAN}── 飞书 Bridge 状态 ──${NC}"
            echo -n "  lark-cli ... "
            if $has_lark; then
                echo -e "${GREEN}✅${NC} $(lark-cli --version 2>/dev/null | head -1)"
            else
                echo -e "${RED}❌${NC} 未安装"
            fi
            echo -n "  cc-connect ... "
            if $has_bridge; then
                echo -e "${GREEN}✅${NC} $(cc-connect --version 2>/dev/null | head -1 || echo '已安装')"
            else
                echo -e "${YELLOW}○${NC} 未安装"
            fi
            bash "$SCRIPT_DIR/bot-status.sh" 2>/dev/null || true
            $has_lark || exit 1
            ;;
        --help|-h)
            echo "用法: $0 [--lark-cli|--cc-connect|--all|--list]"
            echo ""
            echo "  (无参数)    交互式模式（推荐）"
            echo "  --lark-cli  仅 lark-cli（文档/日历/任务）— 每台电脑都需要"
            echo "  --cc-connect 仅 cc-connect（消息 Bridge）— 仅接收消息的机器"
            echo "  --all       全部（非交互）"
            echo "  --list      列出所有账号"
            echo "  --status    状态检查"
            ;;
        "")
            interactive_mode
            ;;
        *)
            bad "❌ 未知参数: $1"; exit 1
            ;;
    esac
}

main "$@"

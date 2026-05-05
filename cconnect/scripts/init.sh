#!/bin/bash
# ccconfig/cconnect/scripts/init.sh
# 功能：安装 cc-connect 二进制 → 从 bots.json 生成 config.toml → 管理 systemd 服务
# 自动检测环境：有 cc-connect 二进制 → 完整配置；没有 → 自动下载安装
# 用法：
#   bash ccconfig/cconnect/scripts/init.sh              # 完整安装+配置+启动
#   bash ccconfig/cconnect/scripts/init.sh --dry-run    # 仅生成配置，不操作服务
#   bash ccconfig/cconnect/scripts/init.sh --restart    # 仅重启服务，不重新生成

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/../../lib/path-helper.sh"
BOTS_JSON="$PROJECT_DIR/conf/bots.json"
CC_CONNECT_VERSION=$(get_cconnect_version)
CC_CONNECT_BIN="$HOME/.local/bin/cc-connect"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad() { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
info() { echo -e "${GRAY}$1${NC}"; }

# ========== 安装 cc-connect 二进制 ==========
install_cconnect_binary() {
    echo ""
    echo -e "${CYAN}── 安装 cc-connect v${CC_CONNECT_VERSION} ──${NC}"

    if [ -x "$CC_CONNECT_BIN" ]; then
        local current_ver
        current_ver=$("$CC_CONNECT_BIN" --version 2>/dev/null | head -1 || echo "unknown")
        good "✓ 已安装: $current_ver"
        return 0
    fi

    echo "下载 cc-connect v${CC_CONNECT_VERSION} ..."
    local download_url="https://github.com/chenhg5/cc-connect/releases/download/v${CC_CONNECT_VERSION}/cc-connect-v${CC_CONNECT_VERSION}-linux-amd64.tar.gz"
    local tmp_dir="/tmp/cc-connect-install-$$"

    mkdir -p "$tmp_dir" "$HOME/.local/bin"

    if curl -fsSL "$download_url" -o "$tmp_dir/cc-connect.tar.gz"; then
        tar -xzf "$tmp_dir/cc-connect.tar.gz" -C "$tmp_dir"
        binary=$(find "$tmp_dir" -name "cc-connect" -type f 2>/dev/null | head -1)
        if [ -n "$binary" ]; then
            cp "$binary" "$CC_CONNECT_BIN"
            chmod +x "$CC_CONNECT_BIN"
            good "✅ 安装成功: $CC_CONNECT_BIN"
        fi
    else
        bad "❌ 下载失败"
        warn "手动下载: https://github.com/chenhg5/cc-connect/releases"
        return 1
    fi
    rm -rf "$tmp_dir"
}

# ========== 环境检测 ==========
detect_env() {
    echo -e "${CYAN}═══ 环境检测 ═══${NC}"

    # Node.js 检查
    export PATH="$HOME/.local/bin:$(find_node_bin):$PATH"
    echo -n "Node.js ... "
    if command -v node &> /dev/null; then
        good "✓ $(node --version)"
    else
        bad "❌ 未安装，请先运行 bash ccconfig/init-ubuntu.sh"
        exit 1
    fi

    # Claude Code 检查
    echo -n "Claude Code ... "
    if command -v claude &> /dev/null; then
        good "✓"
    else
        bad "❌ 未安装"
        exit 1
    fi

    # 检测 cc-connect 二进制
    if [ -x "$CC_CONNECT_BIN" ]; then
        local ver
        ver=$("$CC_CONNECT_BIN" --version 2>/dev/null | head -1 || echo "unknown")
        good "✓ cc-connect: $ver"
        HAS_CCONNECT=true
    else
        warn "○ cc-connect 未安装"
        HAS_CCONNECT=false
    fi

    # 检测 systemd
    if systemctl --user daemon-reload 2>/dev/null; then
        good "✓ systemd 可用"
        HAS_SYSTEMD=true
    else
        warn "○ systemd 不可用 — 跳过服务管理"
        HAS_SYSTEMD=false
    fi

    # 检测 linger
    if command -v loginctl &> /dev/null; then
        loginctl enable-linger "$USER" 2>/dev/null || true
    fi

    # 机器标识
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    info "  主机: $hostname"
    echo ""
}

# ========== 读取配置 ==========
read_bots_config() {
    python3 - "$BOTS_JSON" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

cc = data.get('cconnect', {})
bots = data.get('bots', [])

config_path = cc.get('configPath', '/home/francis/cc-connect/config.toml')
service_name = cc.get('serviceName', 'cc-connect')
print(f"config_path={config_path}")
print(f"service_name={service_name}")
print(f"bot_count={len(bots)}")

for i, bot in enumerate(bots):
    print(f"BOT_{i}={json.dumps(bot)}")
PYEOF
}

# ========== 生成 config.toml ==========
generate_toml() {
    echo -e "${CYAN}═══ 生成 cc-connect config.toml ═══${NC}"
    echo ""

    local config_path service_name
    eval "$(read_bots_config | grep -E '^(config_path|service_name)=' )"
    local config_dir
    config_dir=$(dirname "$config_path")

    mkdir -p "$config_dir"

    python3 - "$BOTS_JSON" "$config_path" << 'PYEOF'
import json, sys, os

bots_file = sys.argv[1]
config_path = sys.argv[2]

with open(bots_file, 'r') as f:
    data = json.load(f)

bots = data.get('bots', [])

lines = []
lines.append('# ╔══════════════════════════════════════════════════╗')
lines.append('# ║  cc-connect 多机器人配置                          ║')
lines.append('# ║  由 ccconfig/cconnect/scripts/init.sh 自动生成    ║')
lines.append('# ║  修改机器人: 编辑 ccconfig/cconnect/conf/bots.json ║')
lines.append('# ╚══════════════════════════════════════════════════╝')
lines.append('')
lines.append('[log]')
lines.append('level = "info"')
lines.append('')

enabled_count = 0
for bot in bots:
    if not bot.get('enabled', False):
        continue
    enabled_count += 1

    name = bot['name']
    app_id = bot.get('feishuAppId', '')
    app_secret = bot.get('feishuAppSecret', '')
    work_dir = bot.get('workDir', '/home/francis/git')
    claude_config_dir = bot.get('claudeConfigDir', '')
    timeout_ms = bot.get('timeoutMs', 3600000)
    desc = bot.get('description', '')
    perms = bot.get('permissions', {})
    opts = bot.get('options', {})

    if not os.path.isdir(work_dir):
        os.makedirs(work_dir, exist_ok=True)

    lines.append(f'# ═══ 机器人: {name} ═══')
    if desc:
        lines.append(f'# {desc}')
    lines.append('[[projects]]')
    lines.append(f'name = "{name}-main"')
    lines.append('')
    lines.append('[projects.agent]')
    lines.append('type = "claudecode"')
    lines.append('')
    lines.append('[projects.agent.options]')
    lines.append(f'work_dir = "{work_dir}"')
    lines.append(f'mode = "{opts.get("mode", "default")}"')
    lines.append(f'timeout_ms = {timeout_ms}')
    lines.append('')

    if claude_config_dir:
        claude_config_dir_expanded = os.path.expanduser(claude_config_dir)
        if not os.path.isdir(claude_config_dir_expanded):
            os.makedirs(claude_config_dir_expanded, exist_ok=True)
        lines.append('[projects.agent.env]')
        lines.append(f'CLAUDE_CONFIG_DIR = "{claude_config_dir_expanded}"')
        lines.append('')

    admin_ids = perms.get('adminOpenIds', [])
    disabled_cmds = perms.get('disabledCommands', [])
    rate_limit = perms.get('rateLimit', {})

    if admin_ids:
        lines.append('[projects.users]')
        lines.append('default_role = "member"')
        lines.append('')
        lines.append('[projects.users.roles.admin]')
        lines.append(f'user_ids = {json.dumps(admin_ids)}')
        lines.append(f'disabled_commands = {json.dumps(disabled_cmds)}')
        lines.append(f'rate_limit = {{ max_messages = {rate_limit.get("maxMessages", 100)}, window_secs = {rate_limit.get("windowSecs", 60)} }}')
        lines.append('')
        lines.append(f'admin_from = "{",".join(admin_ids)}"')
        lines.append('')

    lines.append('[[projects.platforms]]')
    lines.append('type = "feishu"')
    lines.append('')
    lines.append('[projects.platforms.options]')
    lines.append(f'app_id = "{app_id}"')
    lines.append(f'app_secret = "{app_secret}"')
    lines.append(f'allow_from = "{perms.get("allowFrom", "*")}"')

    if opts.get('threadIsolation'):
        lines.append('thread_isolation = true')
    if opts.get('groupOnly'):
        lines.append('group_only = true')
    if opts.get('groupReplyAll'):
        lines.append('group_reply_all = true')
    lines.append('')

content = '\n'.join(lines)

with open(config_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'✅ 已生成 {config_path}')
print(f'   启用的机器人: {enabled_count}/{len(bots)}')
for bot in bots:
    marker = '✅' if bot.get('enabled') else '❌'
    name = bot['name']
    desc = bot.get('description', '')
    app_id = bot.get('feishuAppId', '')
    if app_id:
        app_display = app_id[:22] + '...'
    else:
        app_display = '(未配置)'
    print(f'   {marker} {name}: {desc} ({app_display})')
PYEOF
}

# ========== systemd 服务管理 ==========
setup_service() {
    echo ""
    echo -e "${CYAN}═══ systemd 服务 ═══${NC}"

    if [ "$HAS_CCONNECT" != "true" ]; then
        warn "○ cc-connect 未安装 — 跳过服务配置"
        info "  运行 bash ccconfig/cconnect/scripts/init.sh 安装并配置 cc-connect"
        return 0
    fi

    local config_path service_name
    eval "$(read_bots_config | grep -E '^(config_path|service_name)=' )"

    if [ "$HAS_SYSTEMD" = "true" ]; then
        local service_file="$HOME/.config/systemd/user/${service_name}.service"
        mkdir -p "$HOME/.config/systemd/user"

        local _node_bin
        _node_bin=$(find_node_bin)
        cat > "$service_file" << SERVICEOF
[Unit]
Description=CC-Connect - Multi-Bot AI Bridge (cconnect)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'export PATH=\$(echo "\$PATH" | tr ":" "\\n" | grep -v "^/mnt/" | tr "\\n" ":" | sed "s/:\$//"); exec ${CC_CONNECT_BIN} -config ${config_path}'
Restart=on-failure
RestartSec=10
Environment=PATH=${HOME}/.local/bin:${_node_bin}:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
SERVICEOF

        good "✅ 服务文件: $service_file"

        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable "$service_name" 2>/dev/null || true

        echo -n "启动服务 ... "
        if systemctl --user restart "$service_name" 2>&1; then
            good "✅ 启动成功"
        else
            warn "⚠ systemd 启动失败"
        fi
    else
        warn "○ systemd 不可用 — 跳过服务管理"
    fi
}

show_status() {
    echo ""
    echo -e "${CYAN}═══ 当前状态 ═══${NC}"

    local service_name
    eval "$(read_bots_config | grep 'service_name=' )"

    echo -n "cc-connect 服务 ... "
    if [ "$HAS_SYSTEMD" = "true" ] && systemctl --user is-active "$service_name" &>/dev/null 2>&1; then
        good "● 运行中 (systemd)"
    elif pgrep -f "cc-connect" > /dev/null 2>&1; then
        warn "○ 后台进程 (PID: $(pgrep -f 'cc-connect' | head -1))"
    else
        if [ "$HAS_CCONNECT" = "true" ]; then
            warn "○ 未运行"
        else
            info "○ 本机不需要运行（笔记本）"
        fi
    fi

    echo ""
    bash "$PROJECT_DIR/scripts/status.sh"
}

# ========== 主程序 ==========
main() {
    case "${1:-}" in
        --dry-run)
            echo -e "${CYAN}═══ Dry Run: 仅生成配置，不操作服务 ═══${NC}"
            echo ""
            detect_env
            generate_toml
            echo ""
            info "Dry run 完成。运行 bash ccconfig/cconnect/scripts/init.sh 以应用配置。"
            ;;
        --restart)
            detect_env
            setup_service
            show_status
            ;;
        *)
            echo -e "${CYAN}"
            echo "╔══════════════════════════════════════════════════╗"
            echo "║     cc-connect 多机器人管理 (cconnect)           ║"
            echo "╚══════════════════════════════════════════════════╝"
            echo "$NC"
            detect_env

            # 如果 cc-connect 未安装，尝试安装
            if [ "$HAS_CCONNECT" != "true" ]; then
                install_cconnect_binary || exit 1
            fi

            generate_toml
            setup_service
            show_status
            echo ""
            good "✅ 完成"
            echo ""
            echo "常用命令:"
            echo "  bash ccconfig/cconnect/scripts/status.sh      查看机器人状态"
            echo "  bash ccconfig/cconnect/scripts/bot-enable.sh   启用机器人"
            echo "  bash ccconfig/cconnect/scripts/bot-disable.sh  禁用机器人"
            echo "  systemctl --user status cc-connect            服务状态"
            echo "  journalctl --user -u cc-connect -f            查看日志"
            ;;
    esac
}

main "$@"

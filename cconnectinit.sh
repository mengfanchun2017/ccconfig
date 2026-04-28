#!/bin/bash
# cc-connect 初始化脚本
# 功能：安装配置 cc-connect（替代 ccbot），支持多用户/多飞书 App
# 配置：从 conf-feishu.json 读取
# 目的：Bridge 环境运行的飞书 WebSocket 长连接桥接
#
# 架构说明：
#   每个用户在 conf-feishu.json 的 ccconnect.users[] 中配置
#   每个用户 = 一个 cc-connect project = 一个飞书 App = 一个 Claude Code agent
#   Claude Code 通过 CLAUDE_CONFIG_DIR 隔离配置/凭证/会话
#
# 使用：
#   bash ccconfig/cconnectinit.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEISHU_CONF="$SCRIPT_DIR/conf-feishu.json"
CC_CONNECT_VERSION="1.3.2"
CC_CONNECT_BIN="$HOME/.local/bin/cc-connect"

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
get_cconnect_users() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(json.dumps(data.get('ccconnect', {}).get('users', [])))
except Exception as e:
    print('[]')
PYEOF
}

get_cconnect_config_path() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get('ccconnect', {}).get('configPath', '/home/francis/cc-connect/config.toml'))
except:
    print('/home/francis/cc-connect/config.toml')
PYEOF
}

get_cconnect_service_name() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get('ccconnect', {}).get('serviceName', 'cc-connect'))
except:
    print('cc-connect')
PYEOF
}

get_user_count() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(len(data.get('ccconnect', {}).get('users', [])))
except:
    print('0')
PYEOF
}

# ========== 检查前置环境 ==========
check_prerequisites() {
    title "检查前置环境"

    # 确保 ~/.local/bin 和 Node.js bin 在 PATH 中
    export PATH="$HOME/.local/bin:$HOME/.local/node-v20.11.0-linux-x64/bin:$PATH"

    local missing=0

    if ! command -v node &> /dev/null; then
        bad "❌ Node.js 未安装"
        missing=1
    else
        good "✓ Node.js $(node --version)"
    fi

    if ! command -v claude &> /dev/null; then
        bad "❌ Claude Code 未安装"
        missing=1
    else
        good "✓ Claude Code $(claude --version 2>/dev/null || echo 'installed')"
    fi

    if [ ! -f "$FEISHU_CONF" ]; then
        bad "❌ 配置文件不存在: $FEISHU_CONF"
        exit 1
    fi

    local user_count
    user_count=$(get_user_count)
    if [ "$user_count" -eq 0 ]; then
        bad "❌ conf-feishu.json 中 ccconnect.users 为空，至少需要配置一个用户"
        exit 1
    fi
    good "✓ 配置文件: $FEISHU_CONF ($user_count 个用户)"

    if [ $missing -eq 1 ]; then
        echo ""
        warn "请先运行 ubuntuinit.sh 完成基础环境配置"
        exit 1
    fi
}

# ========== 安装 cc-connect ==========
install_cconnect() {
    title "安装 cc-connect (Bridge)"

    if [ -x "$CC_CONNECT_BIN" ]; then
        local current_ver
        current_ver=$("$CC_CONNECT_BIN" --version 2>/dev/null | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || echo "unknown")
        good "✓ cc-connect 已安装: $current_ver"
        return 0
    fi

    section "下载二进制文件"
    local download_url="https://github.com/chenhg5/cc-connect/releases/download/v${CC_CONNECT_VERSION}/cc-connect-v${CC_CONNECT_VERSION}-linux-amd64.tar.gz"
    local tmp_dir="/tmp/cc-connect-install"

    mkdir -p "$tmp_dir" "$HOME/.local/bin"

    echo "下载: $download_url"
    if curl -fsSL "$download_url" -o "$tmp_dir/cc-connect.tar.gz"; then
        good "✅ 下载成功"
    else
        bad "❌ 下载失败，请检查网络连接"
        return 1
    fi

    echo -n "解压... "
    tar -xzf "$tmp_dir/cc-connect.tar.gz" -C "$tmp_dir"
    # 查找二进制文件
    local binary
    binary=$(find "$tmp_dir" -name "cc-connect" -type f 2>/dev/null | head -1)
    if [ -z "$binary" ]; then
        binary=$(find "$tmp_dir" -name "cc-connect*" -type f 2>/dev/null | head -1)
    fi

    if [ -n "$binary" ]; then
        cp "$binary" "$CC_CONNECT_BIN"
        chmod +x "$CC_CONNECT_BIN"
        good "✅ 安装成功: $CC_CONNECT_BIN"
    else
        bad "❌ 未找到 cc-connect 二进制文件"
        return 1
    fi

    rm -rf "$tmp_dir"

    echo -n "验证安装 ... "
    if "$CC_CONNECT_BIN" --version 2>/dev/null; then
        good "✅ cc-connect 已可用"
    else
        warn "⚠ 版本信息获取失败，但二进制已安装"
    fi
}

# ========== 生成 cc-connect config.toml ==========
generate_cconnect_config() {
    title "生成 cc-connect 配置"

    local config_path
    config_path=$(get_cconnect_config_path)
    local config_dir
    config_dir=$(dirname "$config_path")

    mkdir -p "$config_dir"

    local users_json
    users_json=$(get_cconnect_users)

    python3 - "$config_path" "$users_json" << 'PYEOF'
import json, sys, os

config_path = sys.argv[1]
users = json.loads(sys.argv[2])

lines = []
lines.append('# cc-connect 多用户配置')
lines.append('# 由 cconnectinit.sh 自动生成，请勿手动编辑')
lines.append('# 修改用户配置请编辑 conf-feishu.json 后重新运行 cconnectinit.sh')
lines.append('')
lines.append('[log]')
lines.append('level = "info"')
lines.append('')

for user in users:
    name = user.get('name', 'unknown')
    app_id = user.get('feishuAppId', '')
    app_secret = user.get('feishuAppSecret', '')
    work_dir = user.get('workDir', '/home/francis/git')
    claude_config_dir = user.get('claudeConfigDir', '')
    timeout_ms = user.get('timeoutMs', 3600000)
    desc = user.get('description', '')

    # 确保工作目录存在
    if not os.path.isdir(work_dir):
        os.makedirs(work_dir, exist_ok=True)

    lines.append(f'# === 用户: {name} ===')
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
    lines.append('mode = "default"')
    lines.append(f'timeout_ms = {timeout_ms}')
    lines.append('')

    # CLAUDE_CONFIG_DIR 环境变量实现多用户隔离
    if claude_config_dir:
        claude_config_dir_expanded = os.path.expanduser(claude_config_dir)
        if not os.path.isdir(claude_config_dir_expanded):
            os.makedirs(claude_config_dir_expanded, exist_ok=True)
        lines.append('[projects.agent.env]')
        lines.append(f'CLAUDE_CONFIG_DIR = "{claude_config_dir_expanded}"')
        lines.append('')

    lines.append('[[projects.platforms]]')
    lines.append('type = "feishu"')
    lines.append('')
    lines.append('[projects.platforms.options]')
    lines.append(f'app_id = "{app_id}"')
    lines.append(f'app_secret = "{app_secret}"')
    lines.append('')
    lines.append('# 可选配置（取消注释启用）：')
    lines.append('# thread_isolation = true    # 按飞书 thread 隔离群聊会话')
    lines.append('# enable_feishu_card = true  # 启用交互式卡片（需订阅 card.action.trigger 事件）')
    lines.append('')

content = '\n'.join(lines)

with open(config_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f'✅ 已生成 {config_path}')
print(f'   包含 {len(users)} 个用户/项目配置')
for u in users:
    print(f'   - {u.get("name", "?")}: {u.get("feishuAppId", "?")[:20]}... → {u.get("workDir", "?")}')
PYEOF
}

# ========== 配置 cc-connect systemd 服务 ==========
setup_cconnect_service() {
    title "配置 systemd 服务"

    local config_path service_name
    config_path=$(get_cconnect_config_path)
    service_name=$(get_cconnect_service_name)
    local service_file="$HOME/.config/systemd/user/${service_name}.service"

    mkdir -p "$HOME/.config/systemd/user"

    cat > "$service_file" << EOF
[Unit]
Description=CC-Connect - Multi-User Claude Code Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'export PATH=\$(echo "\$PATH" | tr ":" "\\n" | grep -v "^/mnt/" | tr "\\n" ":" | sed "s/:\$//"); exec ${CC_CONNECT_BIN} -config ${config_path}'
Restart=on-failure
RestartSec=10
Environment=PATH=${HOME}/.local/bin:${HOME}/.local/node-v20.11.0-linux-x64/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF

    good "✅ 服务文件已创建: $service_file"

    # 启用 linger（允许用户级 systemd 在未登录时运行）
    if command -v loginctl &> /dev/null; then
        loginctl enable-linger "$USER" 2>/dev/null || true
    fi

    # 重新加载 systemd
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable "$service_name" 2>/dev/null || true

    section "启动 cc-connect"
    echo -n "启动服务 ... "
    if systemctl --user restart "$service_name" 2>&1; then
        good "✅ 启动成功"
    else
        warn "⚠ systemd 启动失败，尝试直接后台运行"
        nohup "$CC_CONNECT_BIN" -config "$config_path" > /dev/null 2>&1 &
    fi
}

# ========== 停止旧 ccbot（如果存在）==========
cleanup_old_ccbot() {
    title "清理旧 ccbot"

    # 停止 pm2 中的 ccbot
    if command -v pm2 &> /dev/null && pm2 list 2>&1 | grep -q "ccbot"; then
        section "停止旧 ccbot (pm2)"
        pm2 stop ccbot 2>/dev/null || true
        pm2 delete ccbot 2>/dev/null || true
        good "✅ 已停止旧 ccbot"
    else
        info "○ 旧 ccbot 未在运行"
    fi

    # 检查旧的 systemd 服务
    if systemctl --user is-active ccbot.service &>/dev/null 2>&1; then
        systemctl --user stop ccbot.service 2>/dev/null || true
        systemctl --user disable ccbot.service 2>/dev/null || true
        good "✅ 已停用旧 ccbot systemd 服务"
    fi

    # 备份旧的 ccbot.json（如果存在）
    if [ -f "$HOME/git/ccbot.json" ]; then
        mv "$HOME/git/ccbot.json" "$HOME/git/ccbot.json.bak.$(date +%Y%m%d)" 2>/dev/null || true
        info "○ 已备份旧 ccbot.json"
    fi
}

# ========== 飞书开放平台配置提示 ==========
show_feishu_guide() {
    title "飞书开放平台配置提示"

    local users_json
    users_json=$(get_cconnect_users)

    python3 - "$users_json" << 'PYEOF'
import json, sys

users = json.loads(sys.argv[1])

print()
print("每个用户需要独立的飞书企业自建应用：")
print()

for i, user in enumerate(users, 1):
    name = user.get('name', 'unknown')
    app_id = user.get('feishuAppId', '')
    print(f"  {i}. 用户 {name}")
    print(f"     App ID: {app_id}")
    print(f"     链接: https://open.feishu.cn/app/{app_id}")
    print()

print("各应用需要配置：")
print("  1. 启用「机器人」能力")
print("  2. 事件订阅 → 长连接模式")
print("  3. 添加事件: im.message.receive_v1")
print("  4. 权限: im:message.p2p_msg:readonly, im:message.group_at_msg:readonly, im:message:send_as_bot")
print("  5. 如需图片: 额外添加 im:resource 权限")
print("  6. 发布应用（版本管理与发布 → 创建版本 → 发布）")
PYEOF
}

# ========== 状态检查 ==========
show_status() {
    title "状态检查"

    local service_name config_path
    service_name=$(get_cconnect_service_name)
    config_path=$(get_cconnect_config_path)

    section "cc-connect"
    echo -n "安装 ... "
    if [ -x "$CC_CONNECT_BIN" ]; then
        good "✓ ($("$CC_CONNECT_BIN" --version 2>/dev/null | head -1 || echo 'unknown'))"
    else
        bad "❌"
    fi

    echo -n "配置 ... "
    if [ -f "$config_path" ]; then
        local user_count
        user_count=$(get_user_count)
        good "✓ ($user_count 个用户)"
    else
        bad "❌"
    fi

    echo -n "运行 ... "
    if systemctl --user is-active "$service_name" &>/dev/null 2>&1; then
        good "✓ (systemd)"
    elif pgrep -f "cc-connect" > /dev/null 2>&1; then
        warn "○ (后台进程)"
    else
        warn "○ 未运行"
    fi

    echo -n "自动启动 ... "
    if systemctl --user is-enabled "$service_name" &>/dev/null 2>&1; then
        good "✓"
    else
        warn "○ 未配置"
    fi

    section "用户配置"
    local users_json
    users_json=$(get_cconnect_users)
    python3 - "$users_json" << 'PYEOF'
import json, sys
users = json.loads(sys.argv[1])
for u in users:
    print(f"  - {u.get('name', '?')}: {u.get('feishuAppId', '?')[:25]}...")
    print(f"    workDir: {u.get('workDir', '?')}")
    claude_dir = u.get('claudeConfigDir', '')
    if claude_dir:
        print(f"    CLAUDE_CONFIG_DIR: {claude_dir}")
    print()
PYEOF
}

# ========== 主程序 ==========
main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║     cc-connect 初始化 - CC-Connect Init        ║"
    echo "║   多用户 Claude Code 飞书桥接（替代 ccbot）    ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"

    check_prerequisites
    cleanup_old_ccbot
    install_cconnect
    generate_cconnect_config
    setup_cconnect_service
    show_feishu_guide
    show_status

    echo ""
    title "✅ cc-connect 初始化完成"
    echo ""
    echo "常用命令："
    echo "  systemctl --user status cc-connect    # 查看状态"
    echo "  systemctl --user restart cc-connect   # 重启"
    echo "  journalctl --user -u cc-connect -f    # 查看日志"
    echo "  bash ccconfig/cconnectinit.sh         # 重新配置（修改 conf-feishu.json 后）"
    echo ""
    echo "添加新用户："
    echo "  1. 编辑 conf-feishu.json，在 ccconnect.users 中新增用户"
    echo "  2. 在飞书开放平台创建新的企业自建应用"
    echo "  3. 运行 bash ccconfig/cconnectinit.sh 重新生成配置"
    echo ""
}

main "$@"

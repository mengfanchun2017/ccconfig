#!/bin/bash
# ccconfig/option-larkbridge/init.sh — 飞书 lark-channel-bridge 安装/配置/管理
#
# lark-channel-bridge: 飞书 ↔ Claude Code 双向通信 Bridge
# 安装: npm i -g lark-channel-bridge，首次启动扫码绑 PersonalAgent 应用
# 配置源: ccprivate/conf/feishu.json（同一配置源）
#
# 用法:
#   bash ccconfig/option-larkbridge/init.sh               # 安装 + 首次启动
#   bash ccconfig/option-larkbridge/init.sh --start       # 后台服务（systemd）
#   bash ccconfig/option-larkbridge/init.sh --stop        # 停止服务
#   bash ccconfig/option-larkbridge/init.sh --restart      # 重启服务
#   bash ccconfig/option-larkbridge/init.sh --status       # 状态
#   bash ccconfig/option-larkbridge/init.sh --run          # 前台运行（首次配置）
#   bash ccconfig/option-larkbridge/init.sh --logs         # 查看日志

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/path-helper.sh" 2>/dev/null || true
source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || true

NODE_BIN="$(find_node_bin 2>/dev/null || echo "")"
export PATH="$HOME/.local/bin:${NODE_BIN}:$PATH"
SERVICE_NAME="lark-channel-bridge"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

# fallback colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad()  { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
info() { echo -e "${GRAY}$1${NC}"; }

# ========== 安装 ==========
install() {
    echo -e "${CYAN}── 安装 lark-channel-bridge ──${NC}"

    if command -v lark-channel-bridge &>/dev/null; then
        local ver
        ver=$(lark-channel-bridge --version 2>/dev/null | head -1 || echo "?")
        good "  ✓ 已安装: $ver"
        return 0
    fi

    echo -n "  安装中 ... "
    if npm install -g lark-channel-bridge 2>&1 | tail -1; then
        # symlink
        local npm_bin
        npm_bin="$(npm prefix -g 2>/dev/null)/bin"
        mkdir -p "$HOME/.local/bin"
        if [ -x "$npm_bin/lark-channel-bridge" ]; then
            ln -sf "$npm_bin/lark-channel-bridge" "$HOME/.local/bin/lark-channel-bridge"
        fi
        good "✅"
    else
        bad "❌ 安装失败"
        return 1
    fi
}

# ========== 首次配置（前台扫码） ==========
run_foreground() {
    echo -e "${CYAN}── 首次启动（前台扫码） ──${NC}"
    echo ""
    echo "  lark-channel-bridge 首次运行会："
    echo "  1. 终端显示二维码"
    echo "  2. 用飞书扫码 → 自动创建 PersonalAgent 应用"
    echo "  3. 配置写入 ~/.lark-channel/config.json"
    echo ""
    echo -e "  ${YELLOW}扫码完成后，Claude Code 即可在飞书中接收消息${NC}"
    echo ""
    echo -e "  ${GRAY}提示：可用 --start 切换为后台服务运行${NC}"
    echo ""

    if ! command -v lark-channel-bridge &>/dev/null; then
        bad "  lark-channel-bridge 未安装，先运行 $0"
        return 1
    fi

    lark-channel-bridge run
}

# ========== systemd 服务 ==========
setup_service() {
    echo -e "${CYAN}── systemd 服务 ──${NC}"

    if ! systemctl --user daemon-reload 2>/dev/null; then
        warn "  systemd --user 不可用，跳过服务"
        return 1
    fi
    loginctl enable-linger "$USER" 2>/dev/null || true

    mkdir -p "$HOME/.config/systemd/user"

    cat > "$SERVICE_FILE" << SERVICEOF
[Unit]
Description=Lark Channel Bridge — Feishu ↔ Claude Code
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${HOME}/.local/bin/lark-channel-bridge start
Restart=on-failure
RestartSec=15
Environment=PATH=${HOME}/.local/bin:${NODE_BIN}:/usr/local/bin:/usr/bin:/bin
Environment=LARK_CHANNEL_HOME=${HOME}/.lark-channel

[Install]
WantedBy=default.target
SERVICEOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable "${SERVICE_NAME}" 2>/dev/null || true

    if systemctl --user restart "${SERVICE_NAME}" 2>&1; then
        good "  ✅ 服务运行中"
        echo ""
        info "  管理命令:"
        info "    状态: systemctl --user status ${SERVICE_NAME}"
        info "    日志: journalctl --user -u ${SERVICE_NAME} -f"
        info "    重启: bash ccconfig/option-larkbridge/init.sh --restart"
        info "    停止: bash ccconfig/option-larkbridge/init.sh --stop"
    else
        warn "  ⚠ 服务启动失败（检查 journalctl 日志）"
        journalctl --user -u "${SERVICE_NAME}" --no-pager -n 20 2>/dev/null || true
    fi
}

# ========== 状态 ==========
show_status() {
    echo -e "${CYAN}── lark-channel-bridge 状态 ──${NC}"

    echo -n "  安装 ... "
    if command -v lark-channel-bridge &>/dev/null; then
        good "✅ $(lark-channel-bridge --version 2>/dev/null | head -1)"
    else
        echo -e "${YELLOW}○${NC} 未安装"
    fi

    echo -n "  服务 ... "
    if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null 2>&1; then
        good "● 运行中 (systemd)"
    elif pgrep -f "lark-channel-bridge" > /dev/null 2>&1; then
        good "● 运行中 (进程)"
    elif [ -f "$SERVICE_FILE" ]; then
        warn "○ 已装未运行"
    else
        echo -e "${GRAY}－${NC} 未安装"
    fi

    if [ -f "$HOME/.lark-channel/config.json" ]; then
        local bot_name
        bot_name=$(python3 -c "
import json,sys
try:
    with open('$HOME/.lark-channel/config.json') as f:
        d = json.load(f)
    profiles = d.get('profiles', {})
    active = d.get('activeProfile', list(profiles.keys())[0] if profiles else '')
    p = profiles.get(active, {})
    print(f'profile: {active}')
    print(f'agent: {p.get(\"agentKind\", \"?\")}')
    acc = p.get('access', {})
    users = acc.get('allowedUsers', [])
    groups = acc.get('allowedChats', [])
    print(f'允许: {len(users)} 用户, {len(groups)} 群组')
except Exception as e:
    print(f'无法解析: {e}')
" 2>/dev/null || echo "?")
        echo ""
        echo -e "${CYAN}── 配置 ──${NC}"
        echo "$bot_name" | while IFS= read -r line; do
            [ -n "$line" ] && echo "  $line"
        done

        local work_dir
        work_dir=$(python3 -c "
import json,sys
try:
    with open('$HOME/.lark-channel/config.json') as f:
        d = json.load(f)
    profiles = d.get('profiles', {})
    active = d.get('activeProfile', list(profiles.keys())[0] if profiles else '')
    p = profiles.get(active, {})
    ws = p.get('workspaces', {}).get('default', '')
    print(ws or '（未设置，用 /cd 切换）')
except:
    print('?')
" 2>/dev/null)
        echo "  工作目录: $work_dir"
        echo ""
        info "  飞书命令:"
        info "    /help      — 帮助"
        info "    /status    — 状态"
        info "    /cd <dir>  — 切换工作目录"
        info "    /ws save/list/use/remove — 工作区管理"
        info "    /config    — 显示设置"
        info "    /new       — 重置 session"
    fi
}

# ========== 日志 ==========
show_logs() {
    if systemctl --user is-active "${SERVICE_NAME}" &>/dev/null 2>&1; then
        journalctl --user -u "${SERVICE_NAME}" -f
    else
        local log_dir="$HOME/.lark-channel/profiles/"
        if [ -d "$log_dir" ]; then
            local latest
            latest=$(find "$log_dir" -name '*.jsonl' -type f 2>/dev/null | sort -r | head -1)
            if [ -n "$latest" ]; then
                info "日志: $latest"
                tail -f "$latest" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        d = json.loads(line)
        time = d.get('time','')[:19]
        event = d.get('event','')
        msg = d.get('message','')
        print(f'{time} [{event}] {msg}')
    except:
        print(line.rstrip())" 2>/dev/null || tail -f "$latest"
            else
                warn "暂无日志"
            fi
        else
            warn "日志目录不存在"
        fi
    fi
}

# ========== 重新配置 / 修改配置 ==========
reconfigure() {
    echo -e "${CYAN}── 重新配置 lark-channel-bridge ──${NC}"
    echo ""
    echo "  1. 编辑 ~/.lark-channel/config.json 直接修改"
    echo "  2. 或删除配置文件重新扫码绑定:"
    echo ""
    echo -e "  ${YELLOW}rm -rf ~/.lark-channel${NC}"
    echo -e "  ${YELLOW}$0 --run${NC}"
    echo ""
    echo "  常用配置项:"
    echo "    profiles.<name>.workspaces.default — 默认工作目录"
    echo "    profiles.<name>.permissions.defaultAccess — full|workspace|read-only"
    echo "    profiles.<name>.access.allowedUsers — 允许的用户 open_id 列表"
    echo "    profiles.<name>.access.allowedChats — 允许的群组 chat_id 列表"
    echo ""
    info "  修改后执行 systemctl --user restart ${SERVICE_NAME} 生效"
    info "  或在飞书内用 /config /invite 命令配置"
}

# ========== 主程序 ==========
case "${1:-}" in
    --start|-s)
        install
        echo ""
        setup_service
        ;;
    --stop)
        if [ -f "$SERVICE_FILE" ]; then
            systemctl --user stop "${SERVICE_NAME}" 2>/dev/null && good "✅ 已停止" || warn "⚠ 停止失败"
        else
            pkill -f "lark-channel-bridge" 2>/dev/null && good "✅ 已停止" || warn "⚠ 未运行"
        fi
        ;;
    --restart)
        if [ -f "$SERVICE_FILE" ]; then
            systemctl --user restart "${SERVICE_NAME}" 2>/dev/null && good "✅ 已重启" || warn "⚠ 重启失败"
        else
            warn "服务未安装，请先运行 $0 --start"
        fi
        ;;
    --status)
        show_status
        ;;
    --run)
        install
        echo ""
        run_foreground
        ;;
    --logs|-l)
        show_logs
        ;;
    --config|-c)
        reconfigure
        ;;
    --help|-h|*)
        echo "用法: bash ccconfig/option-larkbridge/init.sh <command>"
        echo ""
        echo "  安装/运行:"
        echo "    (无参数)     安装 + 提示下一步"
        echo "    --run        前台运行（首次扫码绑定）"
        echo "    --start      后台服务（systemd）"
        echo ""
        echo "  管理:"
        echo "    --stop       停止服务"
        echo "    --restart    重启服务"
        echo "    --status     查看状态"
        echo "    --logs       查看日志（tail -f）"
        echo "    --config     修改配置指南"
        echo ""
        echo "  示例:"
        echo "    bash ccconfig/option-larkbridge/init.sh --run     # 首次安装+扫码"
        echo "    bash ccconfig/option-larkbridge/init.sh --start   # 转为后台服务"
        echo "    bash ccconfig/option-larkbridge/init.sh --status  # 查看状态"
        ;;
esac

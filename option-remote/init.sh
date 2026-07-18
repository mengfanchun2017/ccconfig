#!/bin/bash
# option-remote/init.sh — 远程连接（SSH + Tailscale）
#
# 用法:
#   bash init.sh                    # 交互式安装
#   bash init.sh --status           # 状态查询
#   bash init.sh server             # 安装服务器端（当前 WSL）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'

info()    { echo -e "  ${GRAY}$1${NC}"; }
ok()      { echo -e "  ${GREEN}✅ $1${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
err()     { echo -e "  ${RED}❌ $1${NC}"; }

# ── 状态查询 ──
do_status() {
    local all_ok=true

    # SSH
    local ssh_status="未安装"
    if systemctl is-active ssh.socket &>/dev/null 2>&1 || systemctl is-active ssh &>/dev/null 2>&1; then
        local port
        port=$(grep -oP '^Port \K[0-9]+' /etc/ssh/sshd_config 2>/dev/null || echo "22")
        ssh_status="✅ 端口 $port"
    elif command -v sshd &>/dev/null; then
        ssh_status="○ 已安装未启动"
        all_ok=false
    else
        all_ok=false
    fi

    # Tailscale
    local ts_status="未安装"
    local ts_exe="/mnt/c/Program Files/Tailscale/tailscale.exe"
    if [ -f "$ts_exe" ]; then
        local ts_ip
        ts_ip=$("$ts_exe" ip -4 2>/dev/null || echo "")
        if [ -n "$ts_ip" ]; then
            ts_status="✅ $ts_ip"
        else
            ts_status="○ 未登录"
            all_ok=false
        fi
    else
        all_ok=false
    fi

    # 第一行：给 status.sh check_option_components 解析
    if $all_ok; then
        echo "OK remote (SSH + Tailscale 就绪)"
    elif systemctl is-active ssh.socket &>/dev/null 2>&1; then
        echo "OK remote (SSH 就绪, Tailscale 未登录)"
    else
        echo "remote: SSH $ssh_status"
    fi

    echo -e "  SSH Server ... ${ssh_status}"
    echo -e "  Tailscale ... ${ts_status}"
    echo -n "  远程可用 ... "
    if systemctl is-active ssh.socket &>/dev/null 2>&1 && [ -f "$ts_exe" ]; then
        local port
        port=$(grep -oP '^Port \K[0-9]+' /etc/ssh/sshd_config 2>/dev/null || echo "22")
        local ts_ip
        ts_ip=$("$ts_exe" ip -4 2>/dev/null || echo "")
        if [ -n "$ts_ip" ]; then
            echo -e "${GREEN}✅${NC} ssh $USER@$ts_ip -p $port"
        else
            echo -e "${YELLOW}○${NC} Tailscale 未就绪"
        fi
    else
        echo -e "${GRAY}－${NC} 需安装 SSH + Tailscale"
    fi
    return 0
}

# ── 服务器端安装 ──
do_server() {
    section "安装 SSH Server + tmux"
    bash "$SCRIPT_DIR/server/tmux-sshd.sh"

    section "部署 Windows 脚本"
    bash "$SCRIPT_DIR/deploy.sh" server

    echo ""
    echo -e "${YELLOW}━━━ 下一步（Windows 管理员 PowerShell）━━━${NC}"
    echo ""
    echo "  1) C:\git\winremote\tmux-portforward.ps1"
    echo "  2) C:\git\winremote\ts-setup.ps1"
    echo ""
    echo -e "  或在 WSL 执行: ${GREEN}powershell.exe -File C:\\git\\winremote\\ts-setup.ps1${NC}"
    echo ""
}

# ── 入口 ──
case "${1:-menu}" in
    --status|-s)
        do_status
        ;;
    server|--server)
        do_server
        ;;
    menu|"")
        do_server
        ;;
    *)
        echo "用法: bash init.sh [server|--status]"
        ;;
esac

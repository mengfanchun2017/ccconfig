#!/bin/bash
# option-remote/init.sh — 远程连接（SSH + Tailscale）
#
# 用法:
#   bash init.sh                    # 查看用法
#   bash init.sh --run              # 一键安装服务器端
#   bash init.sh --status           # 状态查询
#   bash init.sh server             # 仅安装 SSH + tmux

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'

info()    { echo -e "  ${GRAY}$1${NC}"; }
ok()      { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠ $1${NC}"; }
err()     { echo -e "  ${RED}✗ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ── 状态查询 ──
do_status() {
    local all_ok=true

    # SSH
    local ssh_status="未安装"
    if systemctl is-active ssh.socket &>/dev/null 2>&1 || systemctl is-active ssh &>/dev/null 2>&1; then
        local port
        port=$(grep -oP '^Port \K[0-9]+' /etc/ssh/sshd_config 2>/dev/null || echo "22")
        ssh_status="✓ 端口 $port"
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
            ts_status="✓ $ts_ip"
        else
            ts_status="○ 未登录"
            all_ok=false
        fi
    else
        all_ok=false
    fi

    # 第一行：给 status.sh check_option_components 解析（规范: OK|WARN|MISSING <name> ...）
    if $all_ok; then
        echo "OK remote (SSH + Tailscale 就绪)"
    elif systemctl is-active ssh.socket &>/dev/null 2>&1; then
        echo "WARN remote (SSH 就绪, Tailscale 未登录)"
    else
        echo "MISSING remote (SSH $ssh_status)"
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
            echo -e "${GREEN}✓${NC} ssh $USER@$ts_ip -p $port"
        else
            echo -e "${YELLOW}○${NC} Tailscale 未就绪"
        fi
    else
        echo -e "${GRAY}－${NC} 需安装 SSH + Tailscale"
    fi
    return 0
}

# ── 检测 mirrored 网络模式 ──
is_mirrored_network() {
    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "$USER")
    [ -f "/mnt/c/Users/${win_user}/.wslconfig" ] && \
        grep -q "networkingMode=mirrored" "/mnt/c/Users/${win_user}/.wslconfig" 2>/dev/null
}

# ── 服务器端安装 ──
do_server() {
    # 预检：SSH 已就绪则跳过 tmux-sshd.sh（避免 sudo 提示）
    local ssh_ok=false port=""
    if systemctl is-active ssh.socket &>/dev/null 2>&1 || systemctl is-active ssh &>/dev/null 2>&1; then
        port=$(grep -oP '^Port \K[0-9]+' /etc/ssh/sshd_config 2>/dev/null || echo "")
        [ -n "$port" ] && ssh_ok=true
    fi

    if ! $ssh_ok; then
        section "安装 SSH Server + tmux"
        bash "$SCRIPT_DIR/server/tmux-sshd.sh"
    else
        ok "SSH Server 已就绪（端口 $port）"
    fi

    if is_mirrored_network; then
        echo -e "  Mirrored 模式：端口转发无需配置"
    else
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
    fi
}

# ── 一键安装 ──
do_all() {
    # 预检：SSH 已就绪则跳过 tmux-sshd.sh
    local ssh_ok=false
    if systemctl is-active ssh.socket &>/dev/null 2>&1 || systemctl is-active ssh &>/dev/null 2>&1; then
        local port
        port=$(grep -oP '^Port \K[0-9]+' /etc/ssh/sshd_config 2>/dev/null || echo "")
        if [ -n "$port" ]; then
            ssh_ok=true
            ok "SSH Server 已就绪（端口 $port）"
        fi
    fi

    if ! $ssh_ok; then
        section "安装 SSH Server + tmux"
        bash "$SCRIPT_DIR/server/tmux-sshd.sh"
    fi

    if is_mirrored_network; then
        echo -e "  Mirrored 模式：端口转发无需配置"
    else
        bash "$SCRIPT_DIR/deploy.sh" server 2>/dev/null || warn "deploy 跳过（/mnt/c 不可用）"
    fi

    # Tailscale 登录检查
    local ts_exe="/mnt/c/Program Files/Tailscale/tailscale.exe"
    if [ -f "$ts_exe" ]; then
        local ts_ip
        ts_ip=$("$ts_exe" ip -4 2>/dev/null || echo "")
        if [ -n "$ts_ip" ]; then
            ok "Tailscale 已连接: $ts_ip"
            echo ""
            echo -e "  ${GREEN}✓ 远程连接命令${NC}"
            echo -e "    ssh $USER@$ts_ip -p 2222"
            echo ""
            echo "  客户端（笔记本）安装 Tailscale 后运行此命令即可连入。"
            echo "  断开: Ctrl+B D（进程保持）"
            echo "  重连: ssh ...（自动 attach tmux）"
        else
            warn "Tailscale 未登录，请在 Windows 中执行: tailscale up"
        fi
    else
        warn "Tailscale 未安装"
    fi
}

# ── 入口 ──
case "${1:-menu}" in
    --status|-s)
        do_status
        ;;
    --run|-r)
        do_all
        ;;
    server|--server)
        do_server
        ;;
    menu|"")
        echo "option-remote — 远程连接 Claude Code"
        echo ""
        echo "用法:"
        echo "  bash init.sh --run      一键安装（SSH + tmux + Tailscale 检查）"
        echo "  bash init.sh --status   查看连接状态"
        echo "  bash init.sh server     仅安装服务器端组件"
        echo ""
        exit 0
        ;;
    *)
        echo "用法: bash init.sh [server|--run|--status]"
        ;;
esac

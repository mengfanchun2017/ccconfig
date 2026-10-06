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

source "$SCRIPT_DIR/../lib/dry-run.sh"
source "$SCRIPT_DIR/../lib/colors.sh"

# ── 参数解析：server/--run 后可选 --port N（默认 2222）──
SSH_PORT=""
parse_port() {
    local args=("$@") port="" i
    for ((i=0; i<${#args[@]}; i++)); do
        if [ "${args[$i]}" = "--port" ] || [ "${args[$i]}" = "--set-port" ]; then
            port="${args[$((i+1))]:-}"
            break
        fi
    done
    # 位置式：set-port 2223 / server 2223 直接吃第一个纯数字参数
    if [ -z "$port" ]; then
        for a in "${args[@]}"; do
            if [[ "$a" =~ ^[0-9]+$ ]]; then port="$a"; break; fi
        done
    fi
    if [ -n "$port" ]; then
        case "$port" in
            ''|*[!0-9]*)
                echo "错误: --port 后需接数字: $port" >&2
                exit 1
                ;;
        esac
        SSH_PORT="$port"
    fi
}
get_ssh_port() {
    # 优先用用户指定端口，否则读 sshd_config，缺省 22
    if [ -n "$SSH_PORT" ]; then echo "$SSH_PORT"; return; fi
    grep -oP '^Port \K[0-9]+' /etc/ssh/sshd_config 2>/dev/null | head -1 || echo "22"
}

# ── 状态查询 ──
do_status() {
    local all_ok=true
    local ssh_ok=false

    # SSH
    local ssh_status="未安装"
    if systemctl is-active ssh.socket &>/dev/null 2>&1 || systemctl is-active ssh &>/dev/null 2>&1; then
        local port
        port=$(get_ssh_port)
        ssh_status="✓ 端口 $port"
        ssh_ok=true
    elif command -v sshd &>/dev/null; then
        ssh_status="○ 已安装未启动"
        all_ok=false
    else
        all_ok=false
    fi

# Tailscale: 查 WSL 网口，无则看 Windows exe
    local ts_status="未安装"
    local ts_ip=""
    local ts_ok=false
    local ts_iface=$(ip addr show tailscale0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$ts_iface" ]; then
        ts_ip="$ts_iface"
        ts_status="✓ $ts_ip"
        ts_ok=true
    else
        local ts_exe="/mnt/c/Program Files/Tailscale/tailscale.exe"
        if [ -f "$ts_exe" ]; then
            ts_status="✓ Windows 已安装"
            ts_ok=true
        fi
    fi

    # 第一行：给 status.sh check_option_components 解析（规范: OK|WARN|MISSING <name> ...）
    if $ssh_ok && $ts_ok; then
        echo "OK remote (SSH + Tailscale 就绪)"
    elif $ssh_ok && ! $ts_ok; then
        echo "WARN remote (SSH 就绪, Tailscale 未安装)"
    elif ! $ssh_ok && $ts_ok; then
        echo "WARN remote (SSH 未安装, Tailscale 就绪)"
    else
        echo "MISSING remote (SSH + Tailscale 未安装)"
    fi

    echo -e "  SSH Server ... ${ssh_status}"
    echo -e "  Tailscale ... ${ts_status}"
    echo -n "  远程可用 ... "
    if systemctl is-active ssh.socket &>/dev/null 2>&1 || systemctl is-active ssh &>/dev/null 2>&1; then
        local port
        port=$(get_ssh_port)
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

# ── 修改 SSH 端口（幂等：落盘 + 重启）──
do_set_port() {
    local port="$1"
    local rc=0
    sudo sed -i "s/^Port [0-9]*/Port $port/" /etc/ssh/sshd_config
    grep -q "^Port $port" /etc/ssh/sshd_config || echo "Port $port" | sudo tee -a /etc/ssh/sshd_config
    sudo systemctl restart ssh || rc=$?
    if [ $rc -eq 0 ]; then
        ok "SSH 端口已改为 $port"
        echo -e "  远程连接: ssh $USER@<Windows-Tailscale-IP> -p $port"
    else
        err "ssh 重启失败，请检查配置"
        return 1
    fi
}

# ── 服务器端安装 ──
do_server() {
    # 预检：SSH 已就绪则跳过 tmux-sshd.sh（避免 sudo 提示）
    local ssh_ok=false port=""
    if systemctl is-active ssh.socket &>/dev/null 2>&1 || systemctl is-active ssh &>/dev/null 2>&1; then
        port=$(get_ssh_port)
        [ -n "$port" ] && ssh_ok=true
    fi

    if ! $ssh_ok; then
        section "安装 SSH Server + tmux"
        bash "$SCRIPT_DIR/server/tmux-sshd.sh" "$SSH_PORT"
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
        port=$(get_ssh_port)
        if [ -n "$port" ]; then
            ssh_ok=true
            ok "SSH Server 已就绪（端口 $port）"
        fi
    fi

    if ! $ssh_ok; then
        section "安装 SSH Server + tmux"
        bash "$SCRIPT_DIR/server/tmux-sshd.sh" "$SSH_PORT"
    fi

    if is_mirrored_network; then
        echo -e "  Mirrored 模式：端口转发无需配置"
    else
        bash "$SCRIPT_DIR/deploy.sh" server 2>/dev/null || warn "deploy 跳过（/mnt/c 不可用）"
    fi

# Tailscale 登录检查
    local ts_ip=""
    local ts_iface=$(ip addr show tailscale0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$ts_iface" ]; then
        ts_ip="$ts_iface"
    fi
local ts_exe="/mnt/c/Program Files/Tailscale/tailscale.exe"
    if [ -n "$ts_ip" ]; then
        ok "Tailscale 已连接: $ts_ip"
    elif [ -f "$ts_exe" ]; then
        ok "Tailscale 已在 Windows 安装"
    else
        warn "Tailscale 未安装"
    fi

    if [ -f "$ts_exe" ]; then
        local port
        port=$(get_ssh_port)
        echo ""
        echo -e "  ${GREEN}✓ 远程连接命令${NC}"
        echo -e "    ssh <USER>@<Windows_Tailscale_IP> -p $port"
        echo ""
        echo "  客户端（笔记本）安装 Tailscale 后运行此命令即可连入。"
        echo "  断开: Ctrl+B D（进程保持）"
        echo "  重连: ssh ...（自动 attach tmux）"
    fi
}

# ── 入口 ──
case "${1:-menu}" in
    --status|-s)
        do_status
        ;;
    set-port|--set-port)
        parse_port "$@"
        if [ -z "$SSH_PORT" ]; then
            err "用法: bash init.sh set-port <端口>"
            exit 1
        fi
        do_set_port "$SSH_PORT"
        ;;
    --run|-r)
        parse_port "$@"
        do_all
        ;;
    server|--server)
        parse_port "$@"
        do_server
        ;;
    menu|"")
        echo "option-remote — 远程连接 Claude Code"
        echo ""
        echo "用法:"
        echo "  bash init.sh --run                  一键安装（SSH + tmux + Tailscale 检查，端口 2222）"
        echo "  bash init.sh --run --port 2223      新 WSL 发行版指定端口（多发行版多端口）"
        echo "  bash init.sh --status               查看连接状态"
        echo "  bash init.sh server --port 2223     仅安装服务器端组件，端口 2223"
        echo "  bash init.sh set-port <端口>        修改当前发行版 SSH 端口（落盘+重启，幂等）"
        echo ""
        echo "多发行版: 每个 WSL 发行版跑各自 sshd 绑不同端口，Tailscale 在 Windows 侧共享，"
        echo "新发行版只需传 --port 再跑一次即可。"
        echo ""
        exit 0
        ;;
    *)
        echo "用法: bash init.sh [server|--run|--status]"
        ;;
esac

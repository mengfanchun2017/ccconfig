#!/bin/bash
# Claude Config - 启用/禁用 auto-sync 自启动
#
# 统一使用系统级 systemd service（WSL 和原生 Linux 通用）：
#   /etc/systemd/system/claude-auto-sync.service
#
# 使用方法：
#   bash ccconfig/lib/init-autostart.sh enable   # 启用自启动
#   bash ccconfig/lib/init-autostart.sh disable  # 禁用自启动
#   bash ccconfig/lib/init-autostart.sh status   # 查看状态
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/dry-run.sh"
source "$SCRIPT_DIR/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    GRAY='\033[0;90m'
    NC='\033[0m'
}

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
CCCONFIG_HOME="${CCCONFIG_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SVC_TEMPLATE="$SCRIPT_DIR/claude-auto-sync.service"
SYS_SVC_FILE="/etc/systemd/system/claude-auto-sync.service"
SVC_NAME="claude-auto-sync"
USER_SVC_FILE="$HOME/.config/systemd/user/claude-auto-sync.service"

# ── 清理旧用户级 service（迁移遗留） ──

cleanup_legacy_user_service() {
    if [ -f "$USER_SVC_FILE" ]; then
        info "清理旧用户级 service..."
        systemctl --user disable --now "$SVC_NAME" 2>/dev/null || true
        rm -f "$USER_SVC_FILE"
        rm -f "$HOME/.config/systemd/user/default.target.wants/$SVC_NAME" 2>/dev/null || true
    fi
}

# ── 清理僵尸 inotifywait ──

cleanup_zombie_inotify() {
    # 只杀孤儿 inotifywait（PPID=1 残留），不误杀运行中实例
    # sudo pkill -f 会连健康实例一起杀，触发 restart 风暴
    for p in $(pgrep -f "inotifywait.*$HOME/git" 2>/dev/null); do
        [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "1" ] && kill "$p" 2>/dev/null || true
    done
}

# ── enable/disable ──

enable_autostart() {
    if ! command -v systemctl &>/dev/null; then
        error "systemd 不可用（WSL1 或旧版 Linux？），跳过 auto-sync 服务安装"
        return 1
    fi

    if [ ! -f /proc/1/comm ] || ! grep -q "systemd" /proc/1/comm 2>/dev/null; then
        error "systemd 非 PID 1（WSL 需 systemd 支持），跳过系统级 service"
        info "手动启动: bash $SCRIPT_DIR/monitor.sh start"
        return 1
    fi

    cleanup_legacy_user_service
    cleanup_zombie_inotify

    # 清理残留 PIDFile（init 阶段常见：手动跑过 monitor 或上次 systemd 启动失败留下）
    # 防止 monitor.sh start 看到 "Already running" → exit 1 → systemd Type=forking 失败
    local monitor_pid_file="${CCCONFIG_HOME}/.monitor-sync.pid"
    if [ -f "$monitor_pid_file" ]; then
        local stale_pid
        stale_pid=$(cat "$monitor_pid_file" 2>/dev/null)
        if [ -n "$stale_pid" ] && ! kill -0 "$stale_pid" 2>/dev/null; then
            info "清理残留 PIDFile: PID $stale_pid 已退出"
            rm -f "$monitor_pid_file"
        fi
    fi

    if [ ! -f "$SVC_TEMPLATE" ]; then
        error "service 模板不存在: $SVC_TEMPLATE"
        return 1
    fi

    info "安装系统级 systemd service..."
    local _user="$USER"
    local _group="$(id -gn)"
    local _home="$HOME"
    sed -e "s/<USER>/$_user/g" \
        -e "s/<GROUP>/$_group/g" \
        -e "s|<HOME>|$_home|g" \
        "$SVC_TEMPLATE" | sudo tee "$SYS_SVC_FILE" > /dev/null
    sudo systemctl daemon-reload
    if ! sudo systemctl enable --now "$SVC_NAME" 2>&1; then
        warn "systemd 启动失败，打印最近日志："
        sudo journalctl -u "$SVC_NAME" --no-pager -n 10 2>&1 | sed 's/^/    /'
        error "auto-sync 服务启动失败"
        return 1
    fi
    info "auto-sync 已启用（开机自启 + 当前已运行）"
    info "首次启动后 60s 内自动检测已有改动并推送"
}

disable_autostart() {
    info "禁用 auto-sync 自启动..."
    if [ -f "$SYS_SVC_FILE" ]; then
        sudo systemctl disable --now "$SVC_NAME" 2>/dev/null || true
        sudo rm -f "$SYS_SVC_FILE"
        sudo systemctl daemon-reload
    fi
    cleanup_legacy_user_service
    info "自启动已禁用"
}

status_autostart() {
    echo ""
    echo -e "${CYAN}=== auto-sync 自启动状态 ===${NC}"
    echo ""

    if [ -f "$SYS_SVC_FILE" ]; then
        echo -n "  systemd service ... "
        if systemctl is-active --quiet "$SVC_NAME" 2>/dev/null; then
            echo -e "${GREEN}✅${NC} active"
        else
            echo -e "${YELLOW}⚠ ${NC}文件存在但未运行 → sudo systemctl start $SVC_NAME"
        fi
    else
        echo -e "  systemd service ... ${GRAY}未安装${NC} → bash ccconfig/lib/init-autostart.sh enable"
    fi

    local pid_file="${CCCONFIG_HOME}/.monitor-sync.pid"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo -e "  monitor-sync ... ${GREEN}✅${NC} 运行中 (PID: $(cat "$pid_file"))"
    else
        echo -e "  monitor-sync ... ${YELLOW}○${NC} 未运行"
    fi

    local inotify_count=$(pgrep -cf "inotifywait.*$HOME/git" 2>/dev/null || echo 0)
    if [ "$inotify_count" -gt 1 ]; then
        echo -e "  inotifywait ... ${YELLOW}⚠ ${inotify_count} 个${NC} → enable 自动清理"
    elif [ "$inotify_count" -eq 1 ]; then
        echo -e "  inotifywait ... ${GREEN}✅${NC}"
    else
        echo -e "  inotifywait ... ${GRAY}－${NC}"
    fi

    echo ""
    echo -e "${GRAY}命令: enable | disable | status${NC}"
    echo ""
}

case "${1:-status}" in
    enable)  enable_autostart  ;;
    disable) disable_autostart ;;
    status)  status_autostart  ;;
    *)
        echo "用法: $0 {enable|disable|status}"
        exit 1
        ;;
esac

#!/bin/bash
# Claude Config - 启用/禁用 auto-sync 自启动
#
# 使用方法：
#   bash ccconfig/init-autostart.sh enable   # 启用自启动
#   bash ccconfig/init-autostart.sh disable  # 禁用自启动
#   bash ccconfig/init-autostart.sh status    # 查看状态
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

SYSTEMD_SERVICE="$HOME/.config/systemd/user/claude-auto-sync.service"
SYSTEMD_SERVICE_NAME="claude-auto-sync"

enable_autostart() {
    info "启用 auto-sync 自启动..."

    # 检查 systemd 是否可用
    if ! command -v systemctl &>/dev/null; then
        error "systemd 不可用，无法设置自启动"
        return 1
    fi

    # 检查 WSL 是否支持 systemd
    if [ ! -f /proc/1/comm ] || ! grep -q "systemd" /proc/1/comm 2>/dev/null; then
        warn "当前环境可能不支持 systemd 用户服务"
        warn "尝试启用..."
    fi

    # 创建 systemd 服务目录（如果不存在）
    mkdir -p "$(dirname "$SYSTEMD_SERVICE")"

    # 复制服务文件
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cp "$SCRIPT_DIR/sync-monitor.sh" "$HOME/.local/bin/claude-auto-sync-wrapper.sh" 2>/dev/null || true

    cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=Claude Code Auto-Sync Service
Documentation=https://github.com/<your-github-username>/ccconfig
After=default.target

[Service]
Type=oneshot
ExecStart=${HOME}/git/ccconfig/sync-monitor.sh start
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF

    # 启用服务
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable "$SYSTEMD_SERVICE_NAME" 2>/dev/null || {
        warn "systemctl --user 启用失败，尝试直接操作..."
        # 创建符号链接方式
        mkdir -p "$HOME/.config/systemd/user/default.target.wants"
        ln -sf "$SYSTEMD_SERVICE" "$HOME/.config/systemd/user/default.target.wants/$SYSTEMD_SERVICE_NAME" 2>/dev/null || true
    }

    info "自启动已启用"
    info "下次 WSL 启动时 auto-sync 将自动运行"

    # 保存当前 PM2 进程列表（供 resurrect 使用）
    export PATH="$HOME/.local/bin:$PATH"
    if pm2 ping &>/dev/null; then
        pm2 save 2>/dev/null && info "PM2 进程列表已保存" || warn "PM2 save 失败"
    fi
}

disable_autostart() {
    info "禁用 auto-sync 自启动..."

    if command -v systemctl &>/dev/null; then
        systemctl --user disable "$SYSTEMD_SERVICE_NAME" 2>/dev/null || true
    fi

    rm -f "$HOME/.config/systemd/user/default.target.wants/$SYSTEMD_SERVICE_NAME" 2>/dev/null || true
    rm -f "$SYSTEMD_SERVICE" 2>/dev/null || true

    info "自启动已禁用"
}

status_autostart() {
    echo "========================================"
    echo "auto-sync 自启动状态"
    echo "========================================"

    # 检查 systemd 服务
    if [ -f "$SYSTEMD_SERVICE" ]; then
        info "systemd 服务文件: 已创建"
        if command -v systemctl &>/dev/null; then
            if systemctl --user is-enabled "$SYSTEMD_SERVICE_NAME" 2>/dev/null; then
                info "systemd 服务: 已启用"
            else
                warn "systemd 服务: 未启用"
            fi
        fi
    else
        warn "systemd 服务文件: 未创建"
    fi

    # 检查当前 monitor-sync 状态
    AUTO_SYNC_PID_FILE="${HOME}/git/ccconfig/.monitor-sync.pid"
    if [ -f "$AUTO_SYNC_PID_FILE" ] && kill -0 "$(cat "$AUTO_SYNC_PID_FILE")" 2>/dev/null; then
        info "monitor-sync 当前状态: 运行中 (PID: $(cat "$AUTO_SYNC_PID_FILE"))"
    else
        warn "monitor-sync 当前状态: 未运行"
    fi

    echo ""
    echo "自启动配置方法："
    echo "  启用: bash ccconfig/init-autostart.sh enable"
    echo "  禁用: bash ccconfig/init-autostart.sh disable"
    echo "  状态: bash ccconfig/init-autostart.sh status"
    echo ""
}

case "${1:-status}" in
    enable)
        enable_autostart
        ;;
    disable)
        disable_autostart
        ;;
    status)
        status_autostart
        ;;
    *)
        echo "用法: $0 {enable|disable|status}"
        exit 1
        ;;
esac

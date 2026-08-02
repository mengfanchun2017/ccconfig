#!/bin/bash
# ccconfig/option-usage/init.sh — Token 用量统计组件初始化
#
# 功能：
#   - 装好归档目录 ccprivate/usage/
#   - 把 token-usage.sh 注册到 maintain.sh（已完成）
#   - 配套 systemd timer 每日归档（可选）
#
# 用法：
#   bash ccconfig/option-usage/init.sh                # 初始化（创建归档目录）
#   bash ccconfig/option-usage/init.sh --timer        # 启用每日 systemd timer
#   bash ccconfig/option-usage/init.sh --untimer      # 禁用 timer
#   bash ccconfig/option-usage/init.sh --status       # 状态

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CCPRIVATE="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
SERVICE="ccconfig-token-usage.service"
TIMER="ccconfig-token-usage.timer"

ok()   { echo "  ✅ $1"; }
warn() { echo "  ⚠  $1"; }
err()  { echo "  ❌ $1"; }
info() { echo "  ℹ  $1"; }

setup_archive() {
    info "归档目录: $CCPRIVATE/usage/"
    mkdir -p "$CCPRIVATE/usage"
    # 确保 .gitignore 包含 /usage/ 排除
    local gitignore="$CCPRIVATE/.gitignore"
    if ! grep -qE '^/usage/?$|^/usage/' "$gitignore" 2>/dev/null; then
        echo "" >> "$gitignore"
        echo "# Token usage archive (local stat only; remove this line to sync to remote)" >> "$gitignore"
        echo "/usage/" >> "$gitignore"
        ok ".gitignore 加 /usage/ 排除"
    fi
    ok "归档目录就绪"
}

enable_timer() {
    local service_file="$SCRIPT_DIR/$SERVICE"
    if [[ ! -f "$service_file" ]]; then
        err "找不到 $service_file"
        return 1
    fi
    local timer_file="$SCRIPT_DIR/$TIMER"
    sudo cp "$service_file" /etc/systemd/system/
    [[ -f "$timer_file" ]] && sudo cp "$timer_file" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$TIMER"
    ok "timer 已启用：$TIMER"
}

disable_timer() {
    sudo systemctl disable --now "$TIMER" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$SERVICE" "/etc/systemd/system/$TIMER"
    sudo systemctl daemon-reload
    ok "timer 已禁用"
}

status() {
    echo "归档目录: $CCPRIVATE/usage/"
    ls -1 "$CCPRIVATE/usage/" 2>/dev/null | head -10 || warn "归档目录为空"
    echo ""
    echo "systemd timer:"
    systemctl is-active "$TIMER" 2>/dev/null || echo "  未启用"
}

case "${1:-}" in
    --timer)    enable_timer ;;
    --untimer)  disable_timer ;;
    --status)   status ;;
    "")         setup_archive ;;
    *)          echo "用法: $0 [--timer|--untimer|--status]"; exit 1 ;;
esac
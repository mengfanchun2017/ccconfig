#!/bin/bash
# maintain.sh — ccconfig 统一运维入口
#
# 用法：
#   bash maintain.sh status              # 状态检查
#   bash maintain.sh monitor [start|stop|status]  # auto-sync 管理
#   bash maintain.sh sync [--pull|--push] [repo]  # 同步
#   bash maintain.sh update [all|python|<comp>]    # 升级
#   bash maintain.sh deps                # 依赖检查
#   bash maintain.sh fix                 # 自动修复常见问题
#
# 暗号（CLAUDE.md 中定义）：
#   hookstatus → bash maintain.sh status
#   pullff     → bash maintain.sh sync --pull

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

usage() {
    echo "用法: bash maintain.sh <command> [args]"
    echo ""
    echo "命令:"
    echo "  status              状态检查（11 项）"
    echo "  monitor start|stop|status  auto-sync 管理"
    echo "  sync [--pull|--push] [repo]  同步"
    echo "  update [all|python|<comp>]   升级"
    echo "  deps                依赖完整性检查"
    echo "  fix                 自动修复常见问题"
    exit 1
}

case "${1:-}" in
    status)
        bash "$LIB_DIR/status.sh"
        ;;
    monitor)
        bash "$LIB_DIR/monitor.sh" "${2:-status}"
        ;;
    sync)
        shift
        bash "$LIB_DIR/sync.sh" "$@"
        ;;
    update)
        shift
        bash "$LIB_DIR/update.sh" "$@"
        ;;
    deps)
        bash "$LIB_DIR/deps-check.sh"
        ;;
    fix)
        echo "运行自动修复..."
        bash "$LIB_DIR/setup-links.sh"
        bash "$LIB_DIR/init-autostart.sh" enable
        echo "修复完成，运行 maintain.sh status 验证"
        ;;
    *)
        usage
        ;;
esac

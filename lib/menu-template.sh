#!/bin/bash
# menu-template.sh — 标准 SH 脚本脚手架
#
# 用法（不要直接执行）：
#   1. 复制本文件: cp menu-template.sh option-MYTOOL/init.sh
#   2. 改 <MYTOOL> → 实际名字
#   3. 写 do_install / do_update / do_uninstall 逻辑
#   4. 编辑同目录 menu-data.sh 加菜单项
#
# 入口：
#   bash option-MYTOOL/init.sh              # 交互菜单
#   bash option-MYTOOL/init.sh --install    # 安装
#   bash option-MYTOOL/init.sh --update     # 更新
#   bash option-MYTOOL/init.sh --status     # 状态
#   bash option-MYTOOL/init.sh --uninstall  # 卸载
#   bash option-MYTOOL/init.sh --help       # 帮助

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$CCCONFIG_ROOT/lib"

# ── 基础库（顺序固定）──
source "$LIB_DIR/dry-run.sh"
source "$LIB_DIR/path-helper.sh" 2>/dev/null || true
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/interact.sh"
source "$LIB_DIR/quick-probe.sh"

# ── 必填变量 ──
COMPONENT_NAME="<MYTOOL>"

# ── 加载本 option 的菜单数据 ──
# menu-data.sh 定义 MENU_ENTRIES 和 CAT_NAME
source "$SCRIPT_DIR/menu-data.sh"

# ── 状态查询 ──
# 规范：首行 "OK <name> ..." | "WARN <name> ..." | "MISSING <name> ..."
#       无 ANSI（被 init-option 解析）
#       后续行可含 ANSI
do_status() {
    local ok=true
    # TODO: 替换为真实检测
    # [[ -f "/etc/$COMPONENT_NAME" ]] || ok=false

    if $ok; then
        echo "OK $COMPONENT_NAME 已就绪"
    else
        echo "MISSING $COMPONENT_NAME 未安装（bash $0 --install）"
    fi
}

# ── 安装 ──
do_install() {
    section "安装 $COMPONENT_NAME"
    # TODO: 安装逻辑
    do_status
}

# ── 更新 ──
do_update() {
    section "更新 $COMPONENT_NAME"
    do_install  # 多数场景 install == update
}

# ── 卸载 ──
do_uninstall() {
    section "卸载 $COMPONENT_NAME"
    confirm "确认卸载 $COMPONENT_NAME？" n || { info "取消"; return 0; }
    # TODO: 卸载逻辑
}

# ── 帮助 ──
show_help() {
    cat <<EOF
用法: $0 [OPTIONS]

子命令:
  --install     安装 $COMPONENT_NAME
  --update      更新到最新版本
  --status      状态查询
  --uninstall   卸载
  --help        显示帮助

无参数时进入交互菜单（输入 <cat><letter> 执行，如 1A）。
EOF
}

# ── 主菜单（数据驱动）──
menu_main() {
    menu_loop "$COMPONENT_NAME 管理"
}

# ── 入口 ──
case "${1:-menu}" in
    --install)    do_install ;;
    --update)     do_update ;;
    --status)     do_status ;;
    --uninstall)  do_uninstall ;;
    --help|-h)    show_help ;;
    menu|"")      menu_main ;;
    *)            err "未知参数: $1"; show_help; exit 1 ;;
esac

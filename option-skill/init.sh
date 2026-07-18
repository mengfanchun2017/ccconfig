#!/bin/bash
# ccconfig/option-skill/init.sh — Skills 可选组件
#
# 用法：
#   bash ccconfig/option-skill/init.sh              # 交互式
#   bash ccconfig/option-skill/init.sh --install    # 安装（首次）
#   bash ccconfig/option-skill/init.sh --update     # 更新
#   bash ccconfig/option-skill/init.sh --status     # 状态检查

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$CCCONFIG_ROOT/lib"
source "$LIB_DIR/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; NC='\033[0m'
}
SKILLS_SRC="${SKILL_SRC:-$HOME/git/skill/plugins}"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"

do_install() {
    echo -e "${CYAN}── 安装 Skills ──${NC}"
    bash "$LIB_DIR/init-skill.sh" sync
}

do_update() {
    echo -e "${CYAN}── 更新 Skills ──${NC}"
    bash "$LIB_DIR/init-skill.sh" update
    echo ""
    bash "$LIB_DIR/init-skill.sh" sync
}

do_status() {
    local count=0 src_count=0
    [[ -d "$CLAUDE_SKILLS_DIR" ]] && count=$(ls "$CLAUDE_SKILLS_DIR" 2>/dev/null | wc -l)
    [[ -d "$SKILLS_SRC" ]] && src_count=$(ls "$SKILLS_SRC" 2>/dev/null | wc -l)

    if [[ $count -gt 0 ]]; then
        echo "OK Skills ${count}个已安装（源: ${src_count}个）"
    elif [[ $src_count -gt 0 ]]; then
        echo "FAIL Skills 源存在但未链接（运行 --install）"
    else
        echo "Skills — 未安装（bash ccconfig/option-skill/init.sh --install）"
    fi
}

show_menu() {
    echo ""
    echo -e "${CYAN}── Skills 可选组件 ──${NC}"
    echo ""
    bash "$LIB_DIR/init-skill.sh" status
    echo ""
    echo "  1) 安装/同步 skills"
    echo "  2) 更新 skills"
    echo "  3) 查看详细列表"
    echo "  4) 检测 drift"
    echo "  0) 返回"
    echo ""
    read -p "选择 [0-4]: " c
    case "$c" in
        1) do_install ;;
        2) do_update ;;
        3) bash "$LIB_DIR/init-skill.sh" list ;;
        4) bash "$LIB_DIR/init-skill.sh" diff ;;
        0) return ;;
        *) show_menu ;;
    esac
    echo ""
    read -p "按回车返回..." dummy
    show_menu
}

case "${1:-menu}" in
    --install)  do_install ;;
    --update)   do_update ;;
    --status)   do_status ;;
    menu|"")    show_menu ;;
    *)          echo "用法: $0 [--install|--update|--status|menu]" ;;
esac

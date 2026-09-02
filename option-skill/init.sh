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
source "$LIB_DIR/dry-run.sh"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/interact.sh"
SKILLS_SRC="${SKILL_SRC:-$HOME/git/skill/plugins}"
CCPRIVATE_DIR="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
LOCAL_SKILLS_SRC="${LOCAL_SKILLS_SRC:-$CCPRIVATE_DIR/skill-local}"
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
    local count=0 pub_count=0 priv_count=0
    [[ -d "$CLAUDE_SKILLS_DIR" ]] && count=$(ls "$CLAUDE_SKILLS_DIR" 2>/dev/null | wc -l)
    [[ -d "$SKILLS_SRC" ]] && pub_count=$(find "$SKILLS_SRC" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    [[ -d "$LOCAL_SKILLS_SRC" ]] && priv_count=$(find "$LOCAL_SKILLS_SRC" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)

    if [[ $count -gt 0 ]]; then
        echo "OK Skills ${count}个已安装（公开 ${pub_count} / 私有 ${priv_count}）"
    elif [[ $pub_count -gt 0 || $priv_count -gt 0 ]]; then
        echo "WARN Skills 源存在但未链接（运行 --install）"
    else
        echo "MISSING Skills 源不存在（bash ccconfig/option-skill/init.sh --install）"
    fi
}

show_menu() {
    echo ""
    echo -e "${CYAN}── Skills 可选组件 ──${NC}"
    echo ""
    bash "$LIB_DIR/init-skill.sh" status
    echo ""
    local c; c=$(menu_select "Skills 管理" \
        "安装/同步" "更新" "详细列表" "检测 drift" "返回")
    [[ -z "$c" ]] && return
    case "$c" in
        1) do_install ;;
        2) do_update ;;
        3) bash "$LIB_DIR/init-skill.sh" list ;;
        4) bash "$LIB_DIR/init-skill.sh" diff ;;
        5) return ;;
    esac
    echo ""; read -p "按回车返回..." dummy < /dev/tty || true
    show_menu
}

case "${1:-menu}" in
    --install)  do_install ;;
    --update)   do_update ;;
    --status)   do_status ;;
    menu|"")    show_menu ;;
    *)          echo "用法: $0 [--install|--update|--status|menu]" ;;
esac

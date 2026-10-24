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
    # 视图里的条目来自三个互相独立的源，"总数"必须按类拆开，否则对不上账：
    #   公开 = 指向 $SKILLS_SRC 的 symlink
    #   私有 = 指向 $LOCAL_SKILLS_SRC 的 symlink
    #   第三方 = 其余 symlink（lark-* → ~/.agents/skills/，非本仓库管理）
    #   实体 = 真实目录（getnote 的 5 个 skill 由 CLI 直接写进视图）
    # 此前只报"公开/私有"，58 个总数减掉 25 公开还剩 33 无处交代 → 数字对不上。
    local total=0 pub=0 priv=0 third=0 real=0 broken=0
    if [[ -d "$CLAUDE_SKILLS_DIR" ]]; then
        local d target
        for d in "$CLAUDE_SKILLS_DIR"/*; do
            [[ -e "$d" || -L "$d" ]] || continue
            total=$((total + 1))
            if [[ -L "$d" ]]; then
                if [[ ! -e "$d" ]]; then
                    broken=$((broken + 1))
                else
                    target=$(readlink -f "$d")
                    case "$target" in
                        "$SKILLS_SRC"/*)      pub=$((pub + 1)) ;;
                        "$LOCAL_SKILLS_SRC"/*) priv=$((priv + 1)) ;;
                        *)                    third=$((third + 1)) ;;
                    esac
                fi
            else
                real=$((real + 1))
            fi
        done
    fi
    [[ -d "$SKILLS_SRC" ]] && local _p; _p=$(find "$SKILLS_SRC" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    local src_pub=${_p:-0}

    if [[ $total -gt 0 ]]; then
        echo "OK Skills ${total}个（公开 ${pub} / 私有 ${priv} / 第三方 ${third} / 实体 ${real}）"
    elif [[ $src_pub -gt 0 ]]; then
        echo "WARN Skills 源存在但未链接（运行 --install）"
    else
        echo "MISSING Skills 源不存在（bash ccconfig/option-skill/init.sh --install）"
    fi
    if [[ $broken -gt 0 ]]; then
        info "  断链 ${broken} 个 → bash maintain.sh fix"
    fi
    # 源与视图数量不一致（公开源有 N 个 skill，视图里只链上 M 个）单独提示
    if [[ $src_pub -gt 0 && $pub -ne $src_pub ]]; then
        info "  注意: 公开源 ${src_pub} 个 ≠ 视图链接 ${pub} 个 → bash lib/init-skill.sh diff"
    fi
}

show_menu() {
    # 用 while 循环重绘，不要尾调 show_menu —— 递归会每次操作套一层调用栈。
    while true; do
        echo ""
        echo -e "${CYAN}── Skills 可选组件 ──${NC}"
        echo ""
        bash "$LIB_DIR/init-skill.sh" status
        echo ""
        local c; c=$(menu_select "Skills 管理" \
            "安装/同步" "更新" "详细列表" "检测 drift" "返回")
        [[ -z "$c" || "$c" == "0" || "$c" == "5" ]] && return
        case "$c" in
            1) do_install ;;
            2) do_update ;;
            3) bash "$LIB_DIR/init-skill.sh" list ;;
            4) bash "$LIB_DIR/init-skill.sh" diff ;;
        esac
        echo ""; read -p "按回车返回..." dummy < /dev/tty || return
    done
}

case "${1:-menu}" in
    --install)  do_install ;;
    --update)   do_update ;;
    --status)   do_status ;;
    menu|"")    show_menu ;;
    *)          echo "用法: $0 [--install|--update|--status|menu]" ;;
esac

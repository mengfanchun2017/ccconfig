#!/bin/bash
# Claude Skills 管理脚本
# 功能：同步 skills 符号链接、查看状态
# Skills 文件统一存放在 link/skills/，通过 Git 同步
#
# 使用：
#   bash ccconfig/init-skill.sh          # 同步 skills 到 ~/.claude/skills/
#   bash ccconfig/init-skill.sh list     # 查看已安装 skills
#   bash ccconfig/init-skill.sh status   # 查看状态

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/link/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

title() { echo -e "\n========================================\n$1\n========================================\n${CYAN}"; }
good() { echo -e "$1${GREEN}"; }
bad() { echo -e "$1${RED}"; }
info() { echo -e "$1${GRAY}"; }
warn() { echo -e "$1${YELLOW}"; }

do_sync() {
    title "同步 Skills"
    mkdir -p "$CLAUDE_SKILLS_DIR"

    if [[ ! -d "$SKILLS_SRC" ]]; then
        bad "Skills 源目录不存在: $SKILLS_SRC"
        return 1
    fi

    local linked=0 skipped=0
    for skill_dir in "$SKILLS_SRC"/*; do
        [[ -d "$skill_dir" ]] || continue
        local name=$(basename "$skill_dir")
        local target="$CLAUDE_SKILLS_DIR/$name"

        if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$skill_dir")" ]]; then
            info "  $name: 已链接"
            skipped=$((skipped + 1))
        elif [[ -d "$target" ]]; then
            info "  $name: 本地已有，跳过"
            skipped=$((skipped + 1))
        else
            if ln -s "$skill_dir" "$target"; then
                good "  $name: ✓"
                linked=$((linked + 1))
            else
                warn "  $name: 失败"
            fi
        fi
    done

    echo ""
    good "同步完成: $linked 新建, $skipped 跳过"
}

do_status() {
    title "Skills 状态"

    echo -e "${CYAN}link/skills/ (${NC}$(ls "$SKILLS_SRC" 2>/dev/null | wc -l)${CYAN} skills)${NC}"
    for d in "$SKILLS_SRC"/*; do
        [[ -d "$d" ]] || continue
        echo -e "  ${GREEN}✓${NC} $(basename "$d")"
    done

    echo ""
    echo -e "${CYAN}~/.claude/skills/ (Claude Code 可见)${NC}"
    local count=0
    for d in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -e "$d" ]] || continue
        local marker="✓"
        [[ -L "$d" ]] || marker="○"
        echo -e "  ${GREEN}$marker${NC} $(basename "$d")"
        count=$((count + 1))
    done
    [[ $count -eq 0 ]] && echo "  ${GRAY}(空)${NC}"

    echo ""
}

action="${1:-sync}"
case "$action" in
    sync)   do_sync ;;
    list)   echo "=== Skills (link/skills/) ==="; ls "$SKILLS_SRC" 2>/dev/null | while read n; do echo "  $n"; done ;;
    status) do_status ;;
    *)      echo "用法: $0 {sync|list|status}"; exit 1 ;;
esac

echo ""
good "提示: bash ccconfig/init-skill.sh sync 在新环境同步时使用"
exit 0

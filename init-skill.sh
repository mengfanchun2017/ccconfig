#!/bin/bash
# Claude Skills 管理脚本
# 功能：同步自建 skill 符号链接、一键装 marketplace skill
#
# 三种 skill 来源：
#   自建 f-*      → symlink 到 ~/.claude/skills/（本仓 link/skills/）
#   私有 f-logme  → symlink（只本机，不发布）
#   外部 skill    → claude plugin install 从 marketplace 装
#
# 使用：
#   bash ccconfig/init-skill.sh                  # 同步自建 skill
#   bash ccconfig/init-skill.sh install          # 一键装外部 skill（先 add marketplace 再 install）
#   bash ccconfig/init-skill.sh list             # 查看已安装 skills
#   bash ccconfig/init-skill.sh status           # 查看状态

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/link/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
MARKETPLACE_REPO="<your-github-username>/claude-skills"
MARKETPLACE_NAME="<your-github-username>-skills"

# 外部 skill 列表（marketplace + lark 官方 npm）
MARKETPLACE_PLUGINS=(
    "caveman@<your-github-username>-skills:vinvcn/mattpocock-skills-zh-CN"
    "diagnose@<your-github-username>-skills:vinvcn/mattpocock-skills-zh-CN"
    "grill-me@<your-github-username>-skills:vinvcn/mattpocock-skills-zh-CN"
    "improve-codebase-architecture@<your-github-username>-skills:vinvcn/mattpocock-skills-zh-CN"
    "write-a-skill@<your-github-username>-skills:vinvcn/mattpocock-skills-zh-CN"
    "zoom-out@<your-github-username>-skills:vinvcn/mattpocock-skills-zh-CN"
)
LARK_PLUGINS=(
    "lark-shared"
    "lark-doc"
    "lark-base"
    "lark-sheets"
    "lark-wiki"
    "lark-whiteboard"
    "lark-drive"
    "lark-calendar"
)

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

# 同步自建 skill（symlink）
do_sync() {
    title "同步自建 skill → ~/.claude/skills/"
    mkdir -p "$CLAUDE_SKILLS_DIR"

    if [[ ! -d "$SKILLS_SRC" ]]; then
        bad "Skills 源目录不存在: $SKILLS_SRC"
        return 1
    fi

    local linked=0 skipped=0 cleaned=0
    for skill_dir in "$SKILLS_SRC"/*; do
        [[ -d "$skill_dir" ]] || continue
        local name=$(basename "$skill_dir")
        local target="$CLAUDE_SKILLS_DIR/$name"

        if [[ -L "$target" ]] && [[ -e "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$skill_dir")" ]]; then
            info "  $name: 已链接"
            skipped=$((skipped + 1))
        elif [[ -L "$target" ]] && [[ ! -e "$target" ]]; then
            # 源已被删（如 external skill 移到 marketplace）— 清掉断链
            rm -f "$target"
            good "  $name: ✓ 删断链（源已移走）"
            cleaned=$((cleaned + 1))
        elif [[ -L "$target" ]]; then
            # 指向错误目标 — 重建
            rm -f "$target"
            ln -s "$skill_dir" "$target"
            good "  $name: ✓ (修复链接)"
            linked=$((linked + 1))
        elif [[ -d "$target" ]]; then
            info "  $name: 本地已有（非链接），跳过"
            skipped=$((skipped + 1))
        else
            ln -s "$skill_dir" "$target"
            good "  $name: ✓"
            linked=$((linked + 1))
        fi
    done

    echo ""
    good "同步完成: $linked 新建, $skipped 跳过, $cleaned 删断链"
}

# 清理所有 ~/.claude/skills/ 里源已不存在的断链
do_cleanup() {
    title "清理断链"
    local count=0
    for target in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -L "$target" ]] || continue
        if [[ ! -e "$target" ]]; then
            local name=$(basename "$target")
            rm -f "$target"
            good "  ✓ 删: $name"
            count=$((count + 1))
        fi
    done
    [[ $count -eq 0 ]] && info "  无断链"
    echo ""
    good "清理完成: $count 个"
}

# 一键装外部 skill（marketplace + lark npm）
do_install() {
    title "一键装外部 skill"

    info "1. 添加 marketplace: $MARKETPLACE_REPO"
    if claude plugin marketplace add "$MARKETPLACE_REPO" --scope user 2>&1; then
        good "   ✓ marketplace 已添加"
    else
        warn "   ! marketplace 添加失败（可能已存在）"
    fi
    echo ""

    info "2. 从 marketplace 装 6 个三方 skill"
    for entry in "${MARKETPLACE_PLUGINS[@]}"; do
        local plugin="${entry%%:*}"
        local source="${entry##*:}"
        info "   → $plugin  ($source)"
        if claude plugin install "$plugin" 2>&1 | tail -1; then
            good "     ✓"
        else
            warn "     ! 失败（可能已装）"
        fi
    done
    echo ""

    info "3. lark-* 8 个：官方 npm 装 lark-cli 拿全功能"
    info "   ${YELLOW}npm install -g @larksuite/cli && lark-cli auth login${NC}"
    warn "   跳过自动执行 — 涉及全局 npm 安装和飞书认证，需你确认"
    info "   若只想要 skill（不开 CLI），改成: claude plugin install lark-base@<your-github-username>-skills"
    echo ""

    info "4. 更新已装的 marketplace skill"
    if claude plugin marketplace update "$MARKETPLACE_NAME" 2>&1 | tail -3; then
        good "   ✓"
    fi
    echo ""
    good "完成。验证: claude plugin list"
}

do_list() {
    echo "=== 自建 skill (link/skills/) ==="
    ls "$SKILLS_SRC" 2>/dev/null | while read n; do echo "  $n"; done
    echo ""
    echo "=== Marketplace 已装（claude plugin list）==="
    claude plugin list 2>&1 | head -20
}

do_status() {
    title "Skills 状态"
    echo -e "${CYAN}link/skills/ (自建 $(ls "$SKILLS_SRC" 2>/dev/null | wc -l) 个)${NC}"
    for d in "$SKILLS_SRC"/*; do
        [[ -d "$d" ]] || continue
        echo -e "  ${GREEN}✓${NC} $(basename "$d")"
    done

    echo ""
    echo -e "${CYAN}~/.claude/skills/ (symlink 加载)${NC}"
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
    echo -e "${CYAN}Marketplace 已装（claude plugin list）${NC}"
    claude plugin list 2>&1 | head -15
    echo ""
}

action="${1:-sync}"
case "$action" in
    sync)    do_sync ;;
    install) do_install ;;
    cleanup) do_cleanup ;;
    list)    do_list ;;
    status)  do_status ;;
    *)       echo "用法: $0 {sync|install|cleanup|list|status}"; exit 1 ;;
esac

echo ""
good "提示: 新环境先跑 sync + install"
exit 0

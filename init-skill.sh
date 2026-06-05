#!/bin/bash
# Claude Skills 管理脚本
# 功能：同步自建 skill 符号链接 + 装 marketplace 外部 plugin（一站式）
#
# 三个 skill 来源（聚合到 ~/.claude/skills/ 和 claude plugin list）：
#   自建 f-*      → symlink 到 ~/.claude/skills/（本仓 link/skills/）
#   私有 f-logme  → symlink（只本机，不发布）
#   外部 14 个     → claude plugin install 从 claude-skills marketplace
#   skill-template→ symlink（dev only，不在 marketplace）
#
# 4 个 skill 源独立：
#   lark-cli (npm)     → 系统层 CLI 工具，update.sh 独立管理
#   lark-* (8 skill)   → marketplace 装（在 lark-doc SKILL 里 requires lark-cli binary）
#   vinvcn 6 skill     → marketplace 装（自动跟 vinvcn/mattpocock-skills-zh-CN 仓更新）
#   f-* (8 self-built) → symlink（ccconfig 私有工作副本，claude-skills marketplace 同步发布）
#
# 使用：
#   bash ccconfig/init-skill.sh                  # 同步 + 装外部（默认 = sync）
#   bash ccconfig/init-skill.sh sync             # 同上（明确子命令）
#   bash ccconfig/init-skill.sh cleanup          # 单独清 ~/.claude/skills/ 断链
#   bash ccconfig/init-skill.sh list             # 查看已安装 skills（symlink + plugin）
#   bash ccconfig/init-skill.sh status           # 状态总览

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/link/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
MARKETPLACE_REPO="<your-github-username>/claude-skills"
MARKETPLACE_NAME="<your-github-username>-skills"

# 外部 plugin 列表（从 claude-skills marketplace 装）
# 14 = vinvcn 6 (mattpocock-skills-zh-CN) + lark-* 8 (larksuite/cli)
EXTERNAL_PLUGINS=(
    "caveman" "diagnose" "grill-me"
    "improve-codebase-architecture" "write-a-skill" "zoom-out"
    "lark-shared" "lark-doc" "lark-base" "lark-sheets"
    "lark-wiki" "lark-whiteboard" "lark-drive" "lark-calendar"
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

# 同步自建 skill（symlink）+ 装 14 个 external plugin（idempotent）
do_sync() {
    title "阶段 1/3: symlink 自建 skill → ~/.claude/skills/"

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
            rm -f "$target"
            good "  $name: ✓ 删断链（源已移走）"
            cleaned=$((cleaned + 1))
        elif [[ -L "$target" ]]; then
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
    good "  symlink: $linked 新建, $skipped 跳过, $cleaned 删断链"

    # 阶段 2: 检 marketplace 并 add
    title "阶段 2/3: marketplace 装 14 个 external plugin"

    info "检 marketplace: $MARKETPLACE_REPO"
    if claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE_NAME"; then
        good "  ✓ marketplace 已添加"
    else
        if claude plugin marketplace add "$MARKETPLACE_REPO" --scope user 2>&1 | tail -3; then
            good "  ✓ marketplace 已添加"
        else
            warn "  ! marketplace 添加失败（无网络？继续）"
        fi
    fi
    echo ""

    # 阶段 3: 14 个 external plugin install（idempotent）
    info "装 14 个 external plugin（已装就 skip）:"
    local installed=0 already=0 failed=0
    for plugin in "${EXTERNAL_PLUGINS[@]}"; do
        if claude plugin list 2>/dev/null | grep -q "$plugin@$MARKETPLACE_NAME"; then
            info "  $plugin: 已装"
            already=$((already + 1))
        else
            if claude plugin install "$plugin@$MARKETPLACE_NAME" --scope user 2>&1 | tail -1 | grep -qiE "installed|success|✓"; then
                good "  $plugin: ✓"
                installed=$((installed + 1))
            else
                warn "  $plugin: 失败（重试或检网络）"
                failed=$((failed + 1))
            fi
        fi
    done
    echo ""
    good "  external plugin: $installed 新装, $already 已装, $failed 失败"

    echo ""
    good "完成。验证: claude plugin list"
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

do_list() {
    echo "=== 自建 skill (link/skills/ 实体) ==="
    ls "$SKILLS_SRC" 2>/dev/null | while read n; do echo "  $n"; done
    echo ""
    echo "=== ~/.claude/skills/ (symlink) ==="
    for d in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -e "$d" ]] || continue
        local marker="✓"
        [[ -L "$d" ]] || marker="○"
        echo "  $marker $(basename "$d")"
    done
    echo ""
    echo "=== claude plugin list (marketplace 已装) ==="
    claude plugin list 2>&1 | head -30
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
    [[ $count -eq 0 ]] && echo -e "  ${GRAY}(空)${NC}"

    echo ""
    echo -e "${CYAN}claude plugin list (marketplace 已装)${NC}"
    claude plugin list 2>&1 | head -30
    echo ""
}

action="${1:-sync}"
case "$action" in
    sync)    do_sync ;;
    cleanup) do_cleanup ;;
    list)    do_list ;;
    status)  do_status ;;
    *)       echo "用法: $0 {sync|cleanup|list|status}"; exit 1 ;;
esac

echo ""
good "提示: 新环境先跑 sync (symlink + 装 14 external plugin 一条命令)"
exit 0

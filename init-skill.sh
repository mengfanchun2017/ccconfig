#!/bin/bash
# Claude Skills 管理脚本
# 功能：同步自建 skill 符号链接 + 装第三方 skill（npx skills 幂等）
#
# 三个 skill 来源（聚合到 ~/.claude/skills/ 和 claude plugin list）：
#   自建 f-*         → symlink 到 ~/.claude/skills/（本仓 link/skills/）
#   私有 f-logme     → symlink（只本机，不发布）
#   第三方 (npx)     → npx skills add 装到 ~/.agents/skills/，自动 symlink 到 ~/.claude/skills/
#   skill-template   → symlink（dev only，不在 marketplace）
#
# 3 层 skill 源独立：
#   lark-cli (npm)              → 系统层 CLI 工具，update.sh 独立管理（f-doc 编排）
#   第三方 (mattpocock)         → npx skills 装 6 个，conf/third-party-skills.txt 列表管理
#   f-* (8 self-built)          → symlink（ccconfig 私有工作副本，claude-skills marketplace 同步发布）
#
# 使用：
#   bash ccconfig/init-skill.sh sync             # 同步自建 + 装第三方
#   bash ccconfig/init-skill.sh cleanup          # 单独清 ~/.claude/skills/ 断链
#   bash ccconfig/init-skill.sh list             # 查看已安装 skills（symlink + plugin）
#   bash ccconfig/init-skill.sh status           # 状态总览

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/link/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
THIRD_PARTY_CONF="$SCRIPT_DIR/conf/third-party-skills.txt"
MARKETPLACE_REPO="<your-github-username>/claude-skills"
MARKETPLACE_NAME="<your-github-username>-skills"

# EXTERNAL_PLUGINS 留空（2026-06-06 改设计）：第三方 skill 走 npx skills（user-managed 干净显示）
# 保留数组兼容旧 sync 流程；marketplace.json 仍发布 mattpocock-skills 给其他人装
EXTERNAL_PLUGINS=()

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

# 阶段 1：symlink 自建 skill 到 ~/.claude/skills/
# 保护 npx skills 装的 symlink：目标不在 $SKILLS_SRC/ 下就跳过（user-managed）
do_link_self_built() {
    title "阶段 1/3: symlink 自建 skill → ~/.claude/skills/"

    mkdir -p "$CLAUDE_SKILLS_DIR"

    if [[ ! -d "$SKILLS_SRC" ]]; then
        bad "Skills 源目录不存在: $SKILLS_SRC"
        return 1
    fi

    local linked=0 skipped=0 cleaned=0 user_managed=0
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
            # symlink 目标存在但不在 $SKILLS_SRC/ → user-managed（npx skills 装的）
            if [[ "$(readlink -f "$target")" != "$(readlink -f "$skill_dir")" ]]; then
                info "  $name: user-managed (npx 等)，保留"
                user_managed=$((user_managed + 1))
            else
                rm -f "$target"
                ln -s "$skill_dir" "$target"
                good "  $name: ✓ (修复链接)"
                linked=$((linked + 1))
            fi
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
    good "  symlink: $linked 新建, $skipped 跳过, $cleaned 删断链, $user_managed user-managed"
}

# 阶段 2：检 marketplace（保留 <your-github-username>-skills 给 f-* 自动跟）
do_ensure_marketplace() {
    title "阶段 2/3: marketplace 检（<your-github-username>-skills）"

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
    info "  marketplace 保留 <your-github-username>-skills（自建 f-* plugin 在里面；第三方用户走 npx skills 装）"
}

# 阶段 3：npx skills 装第三方 skill（幂等，从 conf/third-party-skills.txt 读列表）
# 已装就 skip（npx skills add 本身幂等）；不重写 ~/.claude/skills/（npx 自己建 symlink）
do_install_third_party() {
    title "阶段 3/3: npx skills 装第三方 skill（conf/third-party-skills.txt）"

    if [[ ! -f "$THIRD_PARTY_CONF" ]]; then
        warn "  conf 清单不存在: $THIRD_PARTY_CONF — 跳过"
        return 0
    fi

    # 防御：github URL 走 HTTPS（init-ubuntu.sh 应已配，这里双保险）
    git config --global url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true

    local installed=0 already=0 failed=0
    while IFS= read -r line; do
        # 跳过空行/注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # 解析 `<source>  <skill-name>`（两个空格或 tab 分隔）
        local source=$(echo "$line" | awk '{print $1}')
        local skill=$(echo "$line" | awk '{print $2}')

        # 检查 ~/.claude/skills/<skill> 是否已存在（npx 装过会有 symlink）
        if [[ -e "$CLAUDE_SKILLS_DIR/$skill" ]]; then
            info "  $skill ($source): 已装"
            already=$((already + 1))
            continue
        fi

        # 调 npx skills add
        if npx --yes skills@latest add "$source" --skill "$skill" -g -y 2>&1 | grep -qE "Installed 1 skill|✓.*$skill"; then
            good "  $skill ($source): ✓"
            installed=$((installed + 1))
        else
            warn "  $skill ($source): 失败（重试或检网络）"
            failed=$((failed + 1))
        fi
    done < "$THIRD_PARTY_CONF"

    echo ""
    good "  第三方 skill: $installed 新装, $already 已装, $failed 失败"
}

do_sync() {
    do_link_self_built
    do_ensure_marketplace
    do_install_third_party

    echo ""
    good "完成。验证: bash init-skill.sh status"
}

# 清理所有 ~/.claude/skills/ 里源已不存在的断链（不删 npx-managed）
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
    echo "=== ~/.claude/skills/ (symlink + npx-installed) ==="
    for d in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -e "$d" ]] || continue
        local marker="✓"
        [[ -L "$d" ]] || marker="○"
        local src
        if [[ -L "$d" ]]; then
            src=$(readlink "$d" | sed 's|.*/\.agents/skills/|npx: |; s|.*/link/skills/|ccconfig: |')
        else
            src="(本地)"
        fi
        echo "  $marker $(basename "$d") — $src"
    done
    echo ""
    echo "=== 第三方 (npx skills 装) ==="
    if [[ -d "$HOME/.agents/skills" ]]; then
        ls "$HOME/.agents/skills" 2>/dev/null | while read n; do echo "  $n"; done
    else
        echo "  (无)"
    fi
    echo ""
    echo "=== claude plugin list (marketplace 已装) ==="
    claude plugin list 2>&1 | head -10
}

do_status() {
    title "Skills 状态"
    echo -e "${CYAN}link/skills/ (自建 $(ls "$SKILLS_SRC" 2>/dev/null | wc -l) 个)${NC}"
    for d in "$SKILLS_SRC"/*; do
        [[ -d "$d" ]] || continue
        echo -e "  ${GREEN}✓${NC} $(basename "$d")"
    done

    echo ""
    echo -e "${CYAN}~/.claude/skills/ ($(ls "$CLAUDE_SKILLS_DIR" 2>/dev/null | wc -l) 项)${NC}"
    for d in "$CLAUDE_SKILLS_DIR"/*; do
        [[ -e "$d" ]] || continue
        local marker="✓"
        [[ -L "$d" ]] || marker="○"
        local src
        if [[ -L "$d" ]]; then
            local target=$(readlink -f "$d")
            if [[ "$target" == *"$SKILLS_SRC"* ]]; then
                src="ccconfig"
            elif [[ "$target" == *".agents/skills"* ]]; then
                src="npx skills"
            else
                src="user"
            fi
        else
            src="(本地)"
        fi
        echo -e "  ${GREEN}$marker${NC} $(basename "$d") — $src"
    done

    echo ""
    echo -e "${CYAN}claude plugin list (marketplace 已装)${NC}"
    claude plugin list 2>&1 | head -10
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
good "提示: 新环境先跑 sync (symlink 自建 + 装 npx 第三方)；更新 npx 装跑 scripts/update-third-party-skills.sh"
exit 0

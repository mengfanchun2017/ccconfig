#!/bin/bash
# Claude Skills 管理脚本
# 功能：同步 skills 符号链接、查看状态、查询 marketplace
# Skills 文件统一存放在 link/skills/，通过 Git 同步
# 外部 skill（larksuite/cli + mattpocock-skills-zh-CN）推荐用 marketplace 装
#
# 使用：
#   bash ccconfig/init-skill.sh                  # 同步 skills 到 ~/.claude/skills/
#   bash ccconfig/init-skill.sh list             # 查看已安装 skills
#   bash ccconfig/init-skill.sh status           # 查看状态
#   bash ccconfig/init-skill.sh update           # 检查外部 skill 更新
#   bash ccconfig/init-skill.sh marketplace      # 查看外部 skill 的 marketplace 安装命令
#   bash ccconfig/init-skill.sh marketplace --install  # 实际安装（用 claude plugin）

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/link/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
MARKETPLACE_REPO="<your-github-username>/claude-skills"
MARKETPLACE_NAME="<your-github-username>-skills"

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
        elif [[ -L "$target" ]]; then
            # 断裂或指向错误目标 — 删除重建
            rm -f "$target"
            ln -s "$skill_dir" "$target"
            good "  $name: ✓ (修复断裂)"
            linked=$((linked + 1))
        elif [[ -d "$target" ]]; then
            info "  $name: 本地已有，跳过"
            skipped=$((skipped + 1))
        else
            ln -s "$skill_dir" "$target"
            good "  $name: ✓"
            linked=$((linked + 1))
        fi
    done

    echo ""
    good "同步完成: $linked 新建, $skipped 跳过"
}

do_update() {
    title "检查外部 Skill 更新"

    local lock_file="$SKILLS_SRC/skills-lock.json"
    if [[ ! -f "$lock_file" ]]; then
        info "无 skills-lock.json，跳过更新检查"
        return 0
    fi

    local updated=0 current=0 failed=0
    local names
    names=$(python3 -c "import json; print(' '.join(json.load(open('$lock_file'))['skills'].keys()))" 2>/dev/null)

    for name in $names; do
        local source source_type skill_path local_hash
        source=$(python3 -c "import json; print(json.load(open('$lock_file'))['skills']['$name']['source'])")
        source_type=$(python3 -c "import json; print(json.load(open('$lock_file'))['skills']['$name']['sourceType'])")
        skill_path=$(python3 -c "import json; print(json.load(open('$lock_file'))['skills']['$name']['skillPath'])")
        local_hash=$(python3 -c "import json; print(json.load(open('$lock_file'))['skills']['$name']['computedHash'])")

        if [[ "$source_type" != "github" ]]; then
            info "  $name: 非 GitHub 来源，跳过"
            continue
        fi

        local remote_url="https://raw.githubusercontent.com/$source/refs/heads/main/$skill_path"
        local remote_content
        remote_content=$(curl -fsSL --max-time 10 "$remote_url" 2>/dev/null)
        if [[ -z "$remote_content" ]]; then
            # 尝试 master 分支
            remote_url="https://raw.githubusercontent.com/$source/refs/heads/master/$skill_path"
            remote_content=$(curl -fsSL --max-time 10 "$remote_url" 2>/dev/null)
        fi

        if [[ -z "$remote_content" ]]; then
            warn "  $name: 获取远程失败 ($source)"
            failed=$((failed + 1))
            continue
        fi

        local remote_hash
        remote_hash=$(echo -n "$remote_content" | sha256sum | cut -d' ' -f1)

        if [[ "$local_hash" != "$remote_hash" ]]; then
            warn "  $name: 有更新! ($source)"
            warn "      远程 hash: ${remote_hash:0:16}..."
            warn "      本地 hash: ${local_hash:0:16}..."
            updated=$((updated + 1))
        else
            good "  $name: 已是最新"
            current=$((current + 1))
        fi
    done

    echo ""
    echo -e "${CYAN}检查完成: ${GREEN}$current 最新${NC}, ${YELLOW}$updated 有更新${NC}"
    [[ $failed -gt 0 ]] && echo -e "${RED}  $failed 检查失败${NC}"
    echo ""

    # 列出非外部 skill（不在 lock 中，跳过检查）
    local self_count=0
    for d in "$SKILLS_SRC"/*; do
        [[ -d "$d" ]] || continue
        local n=$(basename "$d")
        if ! echo "$names" | grep -qF "$n" 2>/dev/null; then
            self_count=$((self_count + 1))
        fi
    done
    [[ $self_count -gt 0 ]] && info "  自建 skill ($self_count 个) 跳过 — 你是源，无需检查"

    return 0
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

do_marketplace() {
    title "Marketplace 安装（外部 skill）"

    local lock_file="$SKILLS_SRC/skills-lock.json"
    if [[ ! -f "$lock_file" ]]; then
        bad "无 skills-lock.json: $lock_file"
        return 1
    fi

    info "外部 skill 维护在 marketplace: ${CYAN}$MARKETPLACE_REPO${NC}"
    info "用 claude plugin 安装 → 自动跟上游同步，不占 link/skills/ 空间"
    echo ""

    info "  # 1. 添加 marketplace（首次执行）"
    info "  ${GREEN}claude plugin marketplace add $MARKETPLACE_REPO --scope user${NC}"
    echo ""

    info "  # 2. 安装具体 skill（plugin@marketplace 格式）"
    local names
    names=$(python3 -c "import json; print(' '.join(json.load(open('$lock_file'))['skills'].keys()))" 2>/dev/null)
    for name in $names; do
        local source
        source=$(python3 -c "import json; print(json.load(open('$lock_file'))['skills']['$name']['source'])")
        info "  ${GREEN}claude plugin install $name@$MARKETPLACE_NAME${NC}    # $source"
    done
    echo ""

    info "  # 3. 更新所有已装的 skill"
    info "  ${GREEN}claude plugin marketplace update $MARKETPLACE_NAME${NC}"
    echo ""

    if [[ "${1:-}" == "--install" ]]; then
        warn "实际安装需要用户确认。手动复制上面的命令执行。"
        return 0
    fi

    info "提示: bash ccconfig/init-skill.sh marketplace --install  显示此 banner"
}

action="${1:-sync}"
case "$action" in
    sync)        do_sync ;;
    list)        echo "=== Skills (link/skills/) ==="; ls "$SKILLS_SRC" 2>/dev/null | while read n; do echo "  $n"; done ;;
    status)      do_status ;;
    update)      do_update ;;
    marketplace) do_marketplace "${2:-}" ;;
    *)           echo "用法: $0 {sync|list|status|update|marketplace}"; exit 1 ;;
esac

echo ""
good "提示: bash ccconfig/init-skill.sh sync 在新环境同步时使用"
exit 0

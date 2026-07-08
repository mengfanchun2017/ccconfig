#!/bin/bash
# git-conflict.sh — Git 冲突解决公共函数
# 被 sync.sh / update.sh source 使用

# 颜色（调用方可覆盖）
: ${RED:='\033[0;31m'} ${GREEN:='\033[0;32m'} ${YELLOW:='\033[1;33m'}
: ${CYAN:='\033[0;36m'} ${BOLD:='\033[1m'} ${NC:='\033[0m'}

# 显示冲突变更摘要
show_changed_since() {
    local before="$1" after="$2" dir="$3"
    local changed
    changed=$(git -C "$dir" diff --name-only "$before" "$after" 2>/dev/null || echo "")
    if [ -n "$changed" ]; then
        echo -e "${CYAN}变更文件:${NC}"
        echo "$changed" | while read f; do echo -e "  ${GRAY}$f${NC}"; done
    fi
}

# 强制拉取（远程覆盖本地）— 含确认
# 用法: git_force_pull <repo_dir> [branch] [repo_name]
git_force_pull() {
    local repo_dir="$1"
    local branch="${2:-$(git -C "$repo_dir" branch --show-current)}"
    local repo_name="${3:-$(basename "$repo_dir")}"

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  高危操作 — 远程覆盖本地                    ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  仓库: ${CYAN}$repo_name${NC} ($repo_dir)"
    echo -e "  分支: ${CYAN}$branch${NC}"
    echo -e "  方向: ${YELLOW}远程 → 本地${NC}（丢弃本地所有改动）"
    echo ""

    if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
        echo -e "  ${YELLOW}⚠️  本地未提交的改动（将被丢弃）：${NC}"
        git -C "$repo_dir" status --short 2>/dev/null | head -20
        echo ""
    fi
    local ahead
    ahead=$(git -C "$repo_dir" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "?")
    if [ "$ahead" != "?" ] && [ "$ahead" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  本地领先远程 $ahead 个提交（将被丢弃）${NC}"
        git -C "$repo_dir" log --oneline "origin/$branch..HEAD" 2>/dev/null | head -10
        echo ""
    fi

    echo -e "  ${RED}此操作不可逆！${NC}"
    echo ""
    read -p "  确认？输入仓库名 \"$repo_name\" 确认: " confirm

    if [ "$confirm" != "$repo_name" ]; then
        echo -e "  ${YELLOW}已取消${NC}"
        return 1
    fi

    echo ""
    echo -e "${CYAN}  🔃 远程 → 本地: $repo_name${NC}"

    if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
        echo "     丢弃本地改动..."
        git -C "$repo_dir" checkout -- . 2>/dev/null || true
    fi

    local before
    before=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)
    echo "     fetching origin/$branch..."
    git -C "$repo_dir" fetch origin "$branch" --prune
    git -C "$repo_dir" reset --hard "origin/$branch"
    git -C "$repo_dir" clean -fd 2>/dev/null || true

    local after
    after=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)
    echo -e "  ${GREEN}✅ $repo_name: $before → $after（本地已与远程一致）${NC}"
    show_changed_since "$before" "$after" "$repo_dir"
    return 0
}

# 强制推送（本地覆盖远程）— 含确认
git_force_push() {
    local repo_dir="$1"
    local branch="${2:-$(git -C "$repo_dir" branch --show-current)}"
    local repo_name="${3:-$(basename "$repo_dir")}"

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  高危操作 — 本地覆盖远程                    ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  仓库: ${CYAN}$repo_name${NC} ($repo_dir)"
    echo -e "  分支: ${CYAN}$branch${NC}"
    echo -e "  方向: ${YELLOW}本地 → 远程${NC}（强制推送覆盖远程，其他人会丢失工作）"
    echo ""

    local ahead
    ahead=$(git -C "$repo_dir" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
    if [ "$ahead" -gt 0 ]; then
        echo -e "  ${CYAN}本地领先远程 $ahead 个提交（将强制推送）：${NC}"
        git -C "$repo_dir" log --oneline "origin/$branch..HEAD" 2>/dev/null | head -10
        echo ""
    fi
    local behind
    behind=$(git -C "$repo_dir" rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo "0")
    if [ "$behind" -gt 0 ]; then
        echo -e "  ${RED}⚠️  远程有 $behind 个本地没有的提交（将被永久覆盖）：${NC}"
        git -C "$repo_dir" log --oneline "HEAD..origin/$branch" 2>/dev/null | head -10
        echo ""
    fi

    echo -e "  ${RED}此操作不可逆！${NC}"
    echo ""
    read -p "  确认？输入仓库名 \"$repo_name\" 确认: " confirm

    if [ "$confirm" != "$repo_name" ]; then
        echo -e "  ${YELLOW}已取消${NC}"
        return 1
    fi

    echo ""
    echo -e "${CYAN}  🔃 本地 → 远程: $repo_name${NC}"
    echo "     force pushing to origin/$branch..."
    git -C "$repo_dir" push --force origin "$branch"
    echo -e "  ${GREEN}✅ $repo_name → origin/$branch（远程已强制覆盖）${NC}"
    return 0
}

# 冲突解决菜单（用于 sync_one_repo fail 后的交互）
# 用法: git_conflict_menu <repo_dir> <branch> <before_hash> <after_hash> [--with-rebase]
git_conflict_menu() {
    local repo_dir="$1" branch="$2" before="$3" after="$4"
    local with_rebase=false
    [[ "${5:-}" == "--with-rebase" ]] && with_rebase=true

    local has_uncommitted=false
    if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
        has_uncommitted=true
    fi

    echo ""
    echo -e "  ${YELLOW}⚠️  自动拉取失败${NC}"
    if $has_uncommitted; then
        echo -e "  原因: 本地有未提交的改动"
        git -C "$repo_dir" status --short 2>/dev/null | head -10
    else
        echo -e "  原因: 本地与远程已分叉"
    fi
    echo ""
    echo -e "  本地: $before"
    echo -e "  远程: $after"
    echo ""
    echo -e "  ${BOLD}a)${NC} 远程覆盖本地（丢弃本地所有改动）"
    echo -e "  ${BOLD}b)${NC} 本地覆盖远程（强制推送本地到远程）"
    if $with_rebase; then
        echo -e "  ${BOLD}r)${NC} Rebase — 以远程为底，本地提交重放其上（推荐）"
    fi
    echo -e "  ${BOLD}c)${NC} 取消，手动处理"
    echo ""
    read -p "  选择 [a/b/${with_rebase:+r/}c]: " choice

    case "$choice" in
        a|A)
            echo ""
            echo -e "${CYAN}  🔃 远程 → 本地${NC}"
            if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
                git -C "$repo_dir" checkout -- . 2>/dev/null || true
            fi
            git -C "$repo_dir" reset --hard "origin/$branch"
            git -C "$repo_dir" clean -fd 2>/dev/null || true
            show_changed_since "$before" "$(git -C "$repo_dir" rev-parse --short HEAD)" "$repo_dir"
            echo -e "  ${GREEN}✅ 本地已与远程一致${NC}"
            return 0
            ;;
        b|B)
            echo ""
            echo -e "${CYAN}  🔃 本地 → 远程${NC}"
            git -C "$repo_dir" push --force origin "$branch"
            echo -e "  ${GREEN}✅ 远程已强制覆盖${NC}"
            return 0
            ;;
        r|R)
            if ! $with_rebase; then return 1; fi
            echo ""
            echo -e "${CYAN}  🔃 Rebase: 本地提交重放到远程之上${NC}"
            local rebase_ok=true
            if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
                echo "     暂存未提交改动..."
                git -C "$repo_dir" stash push -m "sync-rebase-auto-stash" 2>/dev/null || true
            fi
            if ! git -C "$repo_dir" pull --rebase origin "$branch" 2>&1; then
                rebase_ok=false
                echo -e "  ${RED}❌ Rebase 冲突，需要手动解决${NC}"
                echo -e "  ${GRAY}已中止 rebase，恢复到 rebase 前状态${NC}"
                git -C "$repo_dir" rebase --abort 2>/dev/null || true
                git -C "$repo_dir" stash pop 2>/dev/null || true
                return 1
            fi
            if $rebase_ok; then
                git -C "$repo_dir" stash pop 2>/dev/null || true
                show_changed_since "$before" "$(git -C "$repo_dir" rev-parse --short HEAD)" "$repo_dir"
                echo -e "  ${GREEN}✅ Rebase 成功，本地已整合远程${NC}"
                if timeout 60 git -C "$repo_dir" push origin "$branch" 2>&1; then
                    echo -e "  ${GREEN}✅ 已推送至 GitHub${NC}"
                else
                    echo -e "  ${YELLOW}⚠️ 推送失败，请手动推送${NC}"
                fi
            fi
            return 0
            ;;
        *)
            echo ""
            echo -e "  ${YELLOW}已取消${NC}"
            return 1
            ;;
    esac
}

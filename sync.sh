#!/bin/bash
# sync.sh — 多仓库 Git 同步（菜单式）
#
# 用法:
#   bash ccconfig/sync.sh                 # 菜单模式（推荐）
#   bash ccconfig/sync.sh <repo>          # 指定仓库智能同步
#   bash ccconfig/sync.sh --pull <repo>   # 强制远程覆盖本地
#   bash ccconfig/sync.sh --push <repo>   # 强制本地推远程
#   bash ccconfig/sync.sh --check         # 仅检查 ccconfig
#
# ccconfig 额外执行: 重建链接 + skills + 依赖检查 + 新配置模板 + 摘要
# 第三方依赖（_ext/）更新 → update.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

# ========== 仓库列表 ==========
list_repos() {
    local repos=()
    # ccconfig 始终第一位
    repos+=("ccconfig|$SCRIPT_DIR|rw")
    # ~/git/ 下其他自有仓库
    if [ -d "$HOME/git" ]; then
        for d in "$HOME/git"/*/; do
            [ -d "${d}.git" ] || continue
            local name=$(basename "$d")
            [ "$name" = "ccconfig" ] && continue
            [ "$name" = "_ext" ] && continue
            repos+=("$name|${d%/}|rw")
        done
    fi
    printf '%s\n' "${repos[@]}"
}

repo_status() {
    local dir="$1"
    local branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    local head=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
    local dirty=""
    if ! git -C "$dir" diff --quiet 2>/dev/null || ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
        dirty=" ⚡"
    fi
    echo -e "  ${GRAY}$branch${NC} ${GREEN}$head${NC}$dirty"
}

# ========== ccconfig 专属操作 ==========
do_cconfig_post() {
    echo ""
    echo -e "${CYAN}── 重建符号链接 ──${NC}"
    bash "$SCRIPT_DIR/setup-links.sh"

    echo ""
    echo -e "${CYAN}── 新配置模板检测 ──${NC}"
    local found=0
    for example in "$SCRIPT_DIR"/conf/*.json.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .example)
        local target="$SCRIPT_DIR/conf/$base"
        if [ ! -f "$target" ]; then
            cp "$example" "$target"
            echo -e "  ${GREEN}✅${NC} 新建 $base (从 .example 复制)"
            found=1
        fi
    done
    [ $found -eq 0 ] && echo -e "  ${GRAY}无新配置模板${NC}" || echo -e "  ${YELLOW}⚠️ 请编辑新配置文件填入个人凭证${NC}"

    echo ""
    echo -e "${CYAN}── 依赖检查 ──${NC}"
    [ -x "$SCRIPT_DIR/deps-check.sh" ] && bash "$SCRIPT_DIR/deps-check.sh" --required

    do_summary
}

do_summary() {
    echo ""
    echo -e "${CYAN}── 同步摘要 ──${NC}"
    echo ""

    local last_commit last_date
    last_commit=$(git -C "$SCRIPT_DIR" log -1 --format="%h %s" 2>/dev/null)
    last_date=$(git -C "$SCRIPT_DIR" log -1 --format="%ci" 2>/dev/null | cut -d' ' -f1)

    echo -e "  最后提交: ${GREEN}$last_commit${NC}"
    echo -e "  提交日期: ${GRAY}$last_date${NC}"

    local pid_file="$SCRIPT_DIR/.monitor-sync.pid"
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        echo -e "  auto-sync: ${GREEN}✅ 运行中${NC}"
    else
        echo -e "  auto-sync: ${YELLOW}○ 未运行${NC}"
    fi

    if [ -L "$HOME/.claude/settings.json" ]; then
        echo -e "  配置链接: ${GREEN}✅${NC}"
    else
        echo -e "  配置链接: ${YELLOW}○ 未就绪${NC}"
    fi

    echo ""
    echo -e "  ${GRAY}完整检查: bash ccconfig/status.sh${NC}"
    echo ""
}

# ========== 显示变更文件 ==========
show_changed() {
    local before="$1" after="$2" dir="$3"
    local changed
    changed=$(git -C "$dir" diff --name-only "$before" "$after" 2>/dev/null || echo "")
    if [ -n "$changed" ]; then
        echo ""
        echo -e "  ${GRAY}变更文件:${NC}"
        echo "$changed" | while read f; do
            echo -e "    ${GRAY}$f${NC}"
        done
    fi
}

# ========== 同步一个仓库 ==========
sync_one_repo() {
    local repo_dir="$1" repo_name="$2" writable="$3"
    local branch=$(git -C "$repo_dir" branch --show-current)

    echo ""
    echo -e "  ${GRAY}fetching origin...${NC}"

    set +e
    git -C "$repo_dir" fetch origin --prune 2>/dev/null
    local fetch_ok=$?
    set -e

    if [ $fetch_ok -ne 0 ]; then
        echo -e "  ${RED}❌ 无法连接远程${NC}"
        return 1
    fi

    # 远程跟踪分支：优先用 origin/HEAD（远程默认分支），其次 origin/<当前分支>
    local remote_ref
    remote_ref=$(git -C "$repo_dir" rev-parse --short origin/HEAD 2>/dev/null || \
                 git -C "$repo_dir" rev-parse --short "origin/$branch" 2>/dev/null || \
                 echo "")

    if [ -z "$remote_ref" ]; then
        echo -e "  ${YELLOW}⚠️  无法确定远程分支（本地: $branch）${NC}"
        echo -e "  ${GRAY}可能需要重克隆或手动修复远程跟踪${NC}"
        return 1
    fi

    local before after
    before=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)
    after="$remote_ref"

    if [ "$before" = "$after" ]; then
        local dirty=false
        if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
            dirty=true
        fi
        if [ -n "$(git -C "$repo_dir" ls-files -u 2>/dev/null)" ]; then
            dirty=true
        fi
        if $dirty; then
            echo -e "  ${YELLOW}⚠️  HEAD 与远程一致 ($before)，但工作区有未提交改动${NC}"
            echo ""
            git -C "$repo_dir" status --short 2>/dev/null | head -10
            echo ""
        else
            echo -e "  ${GREEN}✅ 已是最新: $before${NC}"
        fi
        return 0
    fi

    echo -e "  ${CYAN}$before → $after${NC}"

    set +e
    local pull_output
    pull_output=$(git -C "$repo_dir" pull --ff-only origin "$branch" 2>&1)
    local pull_status=$?
    set -e

    if [ $pull_status -eq 0 ]; then
        echo -e "  ${GREEN}✅ $repo_name: $before → $after${NC}"
        show_changed "$before" "$after" "$repo_dir"
        return 0
    fi

    # 冲突菜单
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
    echo -e "  ${BOLD}r)${NC} Rebase — 以远程为底，本地提交重放其上（推荐）"
    echo -e "  ${BOLD}c)${NC} 取消，手动处理"
    echo ""
    read -p "  选择 [a/b/r/c]: " choice

    case "$choice" in
        a|A)
            echo ""
            echo -e "${CYAN}  🔃 远程 → 本地${NC}"
            if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
                git -C "$repo_dir" checkout -- . 2>/dev/null || true
            fi
            git -C "$repo_dir" reset --hard "origin/$branch"
            git -C "$repo_dir" clean -fd 2>/dev/null || true
            show_changed "$before" "$(git -C "$repo_dir" rev-parse --short HEAD)" "$repo_dir"
            echo -e "  ${GREEN}✅ 本地已与远程一致${NC}"
            ;;
        b|B)
            echo ""
            echo -e "${CYAN}  🔃 本地 → 远程${NC}"
            git -C "$repo_dir" push --force origin "$branch"
            echo -e "  ${GREEN}✅ 远程已强制覆盖${NC}"
            ;;
        r|R)
            echo ""
            echo -e "${CYAN}  🔃 Rebase: 本地提交重放到远程之上${NC}"
            local rebase_output rebase_ok
            rebase_ok=true
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
                show_changed "$before" "$(git -C "$repo_dir" rev-parse --short HEAD)" "$repo_dir"
                echo -e "  ${GREEN}✅ Rebase 成功，本地已整合远程${NC}"
                # 推送 rebase 后的结果
                if timeout 60 git -C "$repo_dir" push origin "$branch" 2>&1; then
                    echo -e "  ${GREEN}✅ 已推送至 GitHub${NC}"
                else
                    echo -e "  ${YELLOW}⚠️ 推送失败，请手动推送${NC}"
                fi
            fi
            ;;
        *)
            echo ""
            echo -e "  ${YELLOW}已取消${NC}"
            return 1
            ;;
    esac
}

# ========== 强制拉取 ==========
force_pull() {
    local repo_dir="$1" repo_name="$2"
    local branch=$(git -C "$repo_dir" branch --show-current)

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  高危操作 — 云 → 本地                       ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  仓库: ${CYAN}$repo_name${NC} ($repo_dir)"
    echo -e "  分支: ${CYAN}$branch${NC}"
    echo -e "  方向: ${YELLOW}云 → 本地${NC}（丢弃本地所有改动）"
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
        return 0
    fi

    echo ""
    echo -e "${CYAN}  🔃 云 → 本地: $repo_name${NC}"

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
    show_changed "$before" "$after" "$repo_dir"
}

# ========== 强制推送 ==========
force_push() {
    local repo_dir="$1" repo_name="$2"
    local branch=$(git -C "$repo_dir" branch --show-current)

    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  高危操作 — 本地 → 云                       ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  仓库: ${CYAN}$repo_name${NC} ($repo_dir)"
    echo -e "  分支: ${CYAN}$branch${NC}"
    echo -e "  方向: ${YELLOW}本地 → 云${NC}（强制推送覆盖远程，其他人会丢失工作）"
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
        return 0
    fi

    echo ""
    echo -e "${CYAN}  🔃 本地 → 云: $repo_name${NC}"
    echo "     force pushing to origin/$branch..."
    git -C "$repo_dir" push --force origin "$branch"
    echo -e "  ${GREEN}✅ $repo_name → origin/$branch（远程已强制覆盖）${NC}"
}

# ========== 提交并推送 ==========
commitpush() {
    local repo_dir="$1" repo_name="$2"
    local message="${3:-Auto-save: $(date '+%Y-%m-%d %H:%M:%S')}"
    local branch=$(git -C "$repo_dir" branch --show-current)

    echo ""
    echo -e "${CYAN}── commitpush: ${BOLD}$repo_name${NC} ──${NC}"
    echo ""

    # 检查未提交改动
    if git -C "$repo_dir" diff --quiet 2>/dev/null && git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
        echo -e "  ${GREEN}✅ 工作区干净，无需提交${NC}"
        # 检查是否有未推送的提交
        local ahead
        ahead=$(git -C "$repo_dir" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo "0")
        if [ "$ahead" -gt 0 ]; then
            echo -e "  ${CYAN}本地领先远程 $ahead 个提交，直接推送...${NC}"
        else
            echo -e "  ${GREEN}✅ 已是最新${NC}"
            return 0
        fi
    else
        # 有改动 → 提交
        echo -e "  ${YELLOW}本地有改动：${NC}"
        git -C "$repo_dir" status --short 2>/dev/null | head -20
        echo ""

        git -C "$repo_dir" add -A
        local commit_output
        if commit_output=$(git -C "$repo_dir" commit -m "$message" 2>&1); then
            local commit_hash=$(echo "$commit_output" | grep -o '[a-f0-9]\{7\}' | tail -1)
            echo -e "  ${GREEN}✅ 已提交: $commit_hash${NC}"
        else
            echo -e "  ${RED}❌ 提交失败: $(echo "$commit_output" | head -1)${NC}"
            return 1
        fi
    fi

    echo ""
    echo -e "  ${CYAN}推送中...${NC}"
    if timeout 60 git -C "$repo_dir" push origin "$branch" 2>&1; then
        echo -e "  ${GREEN}✅ 已推送至 GitHub${NC}"
    else
        echo -e "  ${RED}❌ 推送失败${NC}"
        return 1
    fi
}

# ========== 检查模式 ==========
check_mode() {
    echo ""
    echo -e "${CYAN}🔄 ccconfig 状态检查${NC}"
    echo ""
    [ -x "$SCRIPT_DIR/deps-check.sh" ] && bash "$SCRIPT_DIR/deps-check.sh" --required
    do_summary
}

# ========== 菜单模式 ==========
menu_mode() {
    while true; do
    echo ""
    echo -e "${CYAN}━━━ ccconfig 多仓库同步 ━━━${NC}"
    echo ""

    # ---- 仓库列表 ----
    echo "  仓库同步"
    local repos_data
    repos_data=$(list_repos)
    local idx=1
    local -a dirs names modes
    local repo_count=0

    while IFS='|' read -r name dir mode; do
        [ -z "$name" ] && continue
        names+=("$name")
        dirs+=("$dir")
        modes+=("$mode")
        repo_count=$((repo_count + 1))
        echo -e "  ${BOLD}$idx)${NC} ${name}"
        repo_status "$dir"
        idx=$((idx + 1))
    done <<< "$repos_data"

    local all_id=$idx
    echo -e "  ${BOLD}$all_id)${NC} ★ 全部同步（ff-only）"

    echo ""
    echo "  检查维护"
    local check_id=$((idx + 1))
    echo -e "  ${BOLD}$check_id)${NC} ccconfig 完整检查（deps + 摘要）"

    echo ""
    echo "  0) 退出"
    echo ""
    read -p "  选择: " choice

    case "$choice" in
        0|"")
            break
            ;;
        $check_id)
            check_mode
            ;;
        $all_id)
            echo ""
            echo -e "${CYAN}── 全部仓库同步 ──${NC}"
            local all_ok=true
            for ((i=0; i<${#dirs[@]}; i++)); do
                echo ""
                echo -e "${BOLD}[$((i+1))/${#dirs[@]}] ${names[$i]}${NC}"
                if ! sync_one_repo "${dirs[$i]}" "${names[$i]}" "${modes[$i]}"; then
                    all_ok=false
                fi
            done
            echo ""
            echo -e "${CYAN}── ccconfig 额外检查 ──${NC}"
            do_cconfig_post
            echo ""
            if $all_ok; then
                echo -e "${GREEN}✅ 全部同步完成${NC}"
            else
                echo -e "${YELLOW}⚠️ 部分仓库同步失败${NC}"
            fi
            ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#dirs[@]} ]; then
                local i=$((choice - 1))
                local name="${names[$i]}" dir="${dirs[$i]}" mode="${modes[$i]}"

                # 子菜单（具体仓库）
                echo ""
                echo -e "${CYAN}── sync: ${BOLD}$name${NC} ──${NC}"
                echo ""
                echo "  1) 智能同步（推荐）"
                echo "  2) 强制拉取远程（丢弃本地改动）"
                echo "  3) 本地覆盖远程"
                echo "  0) 返回"
                echo ""
                read -p "  选择: " sub

                case "$sub" in
                    1)
                        sync_one_repo "$dir" "$name" "$mode"
                        [ "$name" = "cconfig" ] && { do_cconfig_post; echo -e "${GREEN}✅ 同步完成${NC}"; }
                        ;;
                    2)
                        force_pull "$dir" "$name"
                        [ "$name" = "cconfig" ] && do_cconfig_post
                        ;;
                    3)
                        force_push "$dir" "$name"
                        ;;
                    0|"") ;;
                    *) echo -e "  ${RED}无效选择${NC}" ;;
                esac
            else
                echo -e "  ${RED}无效选择${NC}"
            fi
            ;;
    esac
    done  # while true — loop back to main menu
}

# ========== 帮助 ==========
show_help() {
    echo ""
    echo -e "${CYAN}sync.sh${NC} — 多仓库 Git 同步（菜单式）"
    echo ""
    echo "用法:"
    echo "  bash ccconfig/sync.sh                 菜单模式（推荐）"
    echo "  bash ccconfig/sync.sh <repo>          指定仓库智能同步"
    echo "  bash ccconfig/sync.sh --pull <repo>   强制远程覆盖本地"
    echo "  bash ccconfig/sync.sh --push <repo>   强制本地推远程"
    echo "  bash ccconfig/sync.sh --commitpush [repo] 提交并推送（不拉取）"
    echo "  bash ccconfig/sync.sh --check         仅检查 ccconfig"
    echo "  bash ccconfig/sync.sh --all           全部仓库 ff-only"
    echo ""
    echo "ccconfig 额外执行: 重建链接 + skills + 新配置模板 + 依赖检查 + 摘要"
}

# ========== 主流程 ==========
case "${1:-}" in
    --pull)
        REPO_DIR="$SCRIPT_DIR"
        REPO_NAME="ccconfig"
        if [ -n "${2:-}" ]; then
            case "$2" in
                projectu) REPO_DIR="$HOME/git/projectu"; REPO_NAME="projectu" ;;
                *) REPO_DIR="$HOME/git/$2"; REPO_NAME="$2" ;;
            esac
        fi
        [ -d "$REPO_DIR/.git" ] || { echo -e "${RED}❌ 未找到仓库: $REPO_NAME${NC}"; exit 1; }
        force_pull "$REPO_DIR" "$REPO_NAME"
        [ "$REPO_NAME" = "cconfig" ] && do_cconfig_post
        ;;
    --push)
        REPO_DIR="$SCRIPT_DIR"
        REPO_NAME="ccconfig"
        if [ -n "${2:-}" ]; then
            case "$2" in
                projectu) REPO_DIR="$HOME/git/projectu"; REPO_NAME="projectu" ;;
                *) REPO_DIR="$HOME/git/$2"; REPO_NAME="$2" ;;
            esac
        fi
        [ -d "$REPO_DIR/.git" ] || { echo -e "${RED}❌ 未找到仓库: $REPO_NAME${NC}"; exit 1; }
        force_push "$REPO_DIR" "$REPO_NAME"
        ;;
    --commitpush)
        REPO_DIR="$SCRIPT_DIR"
        REPO_NAME="ccconfig"
        COMMIT_MSG="${3:-}"
        if [ -n "${2:-}" ]; then
            case "$2" in
                projectu) REPO_DIR="$HOME/git/projectu"; REPO_NAME="projectu" ;;
                *) REPO_DIR="$HOME/git/$2"; REPO_NAME="$2" ;;
            esac
        fi
        [ -d "$REPO_DIR/.git" ] || { echo -e "${RED}❌ 未找到仓库: $REPO_NAME${NC}"; exit 1; }
        if [ -n "$COMMIT_MSG" ]; then
            commitpush "$REPO_DIR" "$REPO_NAME" "$COMMIT_MSG"
        else
            commitpush "$REPO_DIR" "$REPO_NAME"
        fi
        [ "$REPO_NAME" = "cconfig" ] && do_cconfig_post
        ;;
    --check)
        check_mode
        exit 0
        ;;
    --all)
        echo ""
        echo -e "${CYAN}🔃 全部仓库同步...${NC}"
        repos_data=$(list_repos)
        while IFS='|' read -r name dir mode; do
            [ -z "$name" ] && continue
            echo ""
            echo -e "${BOLD}── $name ──${NC}"
            sync_one_repo "$dir" "$name" "$mode" || true
        done <<< "$repos_data"
        echo ""
        echo -e "${CYAN}── ccconfig 额外检查 ──${NC}"
        do_cconfig_post
        echo ""
        echo -e "${GREEN}✅ 全部同步完成${NC}"
        ;;
    --help|-h)
        show_help
        exit 0
        ;;
    "")
        menu_mode
        ;;
    *)
        # 直接指定仓库名
        REPO_DIR=""
        REPO_NAME="$1"
        case "$1" in
            ccconfig) REPO_DIR="$SCRIPT_DIR" ;;
            projectu) REPO_DIR="$HOME/git/projectu" ;;
            *)
                REPO_DIR="$HOME/git/$1"
                [ -d "$REPO_DIR/.git" ] || REPO_DIR=""
                ;;
        esac
        if [ -z "$REPO_DIR" ]; then
            echo -e "${RED}❌ 未找到仓库: $1${NC}"
            exit 1
        fi
        sync_one_repo "$REPO_DIR" "$REPO_NAME" "rw"
        if [ "$REPO_NAME" = "cconfig" ]; then
            do_cconfig_post
            echo -e "${GREEN}✅ 同步完成${NC}"
        fi
        ;;
esac

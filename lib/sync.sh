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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
# git-conflict.sh 函数已内联（原独立文件删除）

source "$SCRIPT_DIR/dry-run.sh"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/interact.sh"

# ========== 仓库列表 ==========
list_repos() {
    local repos=()
    # ccconfig 始终第一位
    repos+=("ccconfig|$CCCONFIG_ROOT|rw")
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
        dirty=" 有改动"
    fi
    echo -e "  ${GRAY}$branch${NC} ${GREEN}$head${NC}$dirty"
}

# ========== ccconfig 专属操作 ==========
do_cconfig_post() {
    echo ""
    echo -e "${CYAN}── 重建符号链接 ──${NC}"
    bash "$CCCONFIG_ROOT/lib/setup-links.sh" || echo -e "  ${YELLOW}⚠️ 部分链接失败（首次初始化正常）${NC}"

    echo ""
    echo -e "${CYAN}── 新配置模板检测（复制到 ccprivate）──${NC}"
    local ccpriv="${CCPRIVATE_DIR:-$HOME/git/ccprivate}"
    local found=0
    for example in "$CCCONFIG_ROOT"/conf/*.json.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .example)
        local target="$ccpriv/conf/$base"
        if [ ! -f "$target" ]; then
            mkdir -p "$ccpriv/conf"
            cp "$example" "$target"
            echo -e "  ${GREEN}✅${NC} 新建 $base (→ ccprivate/conf/$base)"
            found=1
        fi
    done
    [ $found -eq 0 ] && echo -e "  ${GRAY}无新配置模板${NC}" || echo -e "  ${YELLOW}⚠️ 请编辑新配置文件填入个人凭证${NC}"


    # rules 新模板检测
    local rules_found=0
    for example in "$CCCONFIG_ROOT"/templates/rules/*.md.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .md.example)
        local target="$ccpriv/rules/$base.md"
        if [ ! -f "$target" ]; then
            mkdir -p "$ccpriv/rules"
            cp "$example" "$target"
            echo -e "  ${GREEN}✅${NC} 新建 rules/$base.md (→ ccprivate/rules/)"
            rules_found=1
        fi
    done
    [ $rules_found -eq 0 ] || echo -e "  ${GRAY}rules 新模板已复制到 ccprivate${NC}"

    # agents 新模板检测
    local agents_found=0
    for example in "$CCCONFIG_ROOT"/templates/agents/*.md.example; do
        [ -f "$example" ] || continue
        local base=$(basename "$example" .md.example)
        local target="$ccpriv/agents/$base.md"
        if [ ! -f "$target" ]; then
            mkdir -p "$ccpriv/agents"
            cp "$example" "$target"
            echo -e "  ${GREEN}✅${NC} 新建 agents/$base.md (→ ccprivate/agents/)"
            agents_found=1
        fi
    done
    [ $agents_found -eq 0 ] || echo -e "  ${GRAY}agents 新模板已复制到 ccprivate${NC}"
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
    last_commit=$(git -C "$CCCONFIG_ROOT" log -1 --format="%h %s" 2>/dev/null)
    last_date=$(git -C "$CCCONFIG_ROOT" log -1 --format="%ci" 2>/dev/null | cut -d' ' -f1)

    echo -e "  最后提交: ${GREEN}$last_commit${NC}"
    echo -e "  提交日期: ${GRAY}$last_date${NC}"

    local pid_file="$CCCONFIG_ROOT/.monitor-sync.pid"
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
        show_changed_since "$before" "$after" "$repo_dir"
        return 0
    fi

    git_conflict_menu "$repo_dir" "$branch" "$before" "$after" --with-rebase || return 1
}

# force_pull / force_push → lib/git-conflict.sh

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
    clear 2>/dev/null || true
    echo ""
    echo -e "${CYAN}━━━ ccconfig 多仓库同步 ━━━${NC}"
    echo ""

    # ---- 构造菜单 ----
    local repos_data
    repos_data=$(list_repos)
    local -a dirs names modes menu_items
    while IFS='|' read -r name dir mode; do
        [ -z "$name" ] && continue
        names+=("$name"); dirs+=("$dir"); modes+=("$mode")
        local status; status=$(repo_status "$dir" 2>/dev/null)
        menu_items+=("$name  $status")
    done <<< "$repos_data"

    menu_items+=("★ 全部同步（ff-only）")
    menu_items+=("ccconfig 完整检查（deps + 摘要）")
    menu_items+=("退出")

    local choice
    choice=$(menu_select "多仓库同步" "${menu_items[@]}")
    [[ -z "$choice" ]] && continue

    local repo_count="${#names[@]}"
    local all_idx=$((repo_count + 1))        # "★ 全部同步" 选项序号
    local check_idx=$((repo_count + 2))       # "ccconfig 完整检查" 选项序号
    local exit_idx=$((repo_count + 3))        # "退出" 选项序号

    case "$choice" in
        0|$exit_idx) break ;;
        $all_idx)  # 全部同步
            echo ""
            echo -e "${CYAN}── 全部仓库同步 ──${NC}"
            local all_ok=true
            for ((i=0; i<${#dirs[@]}; i++)); do
                echo ""
                echo -e "${BOLD}[$((i+1))/${#dirs[@]}] ${names[$i]}${NC}"
                sync_one_repo "${dirs[$i]}" "${names[$i]}" "${modes[$i]}" || all_ok=false
            done
            echo ""
            echo -e "${CYAN}── ccconfig 额外检查 ──${NC}"
            do_cconfig_post
            $all_ok && echo -e "${GREEN}✅ 全部同步完成${NC}" || echo -e "${YELLOW}⚠️ 部分失败${NC}"
            ;;
        $check_idx)  # ccconfig 完整检查
            check_mode ;;
        *)
            # 找到了仓库索引
            local found=-1
            for ((i=0; i<${#names[@]}; i++)); do
                if echo "${menu_items[$i]}" | grep -q "^${names[$i]}" && echo "$choice" | grep -q "^${names[$i]}"; then
                    found=$i; break
                fi
            done
            if [ "$found" -ge 0 ]; then
                local name="${names[$found]}" dir="${dirs[$found]}" mode="${modes[$found]}"
                local sub
                sub=$(menu_select "sync: $name" \
                    "智能同步（推荐）" \
                    "强制拉取远程" \
                    "本地覆盖远程" \
                    "返回")
                [[ -z "$sub" || "$sub" = "0" ]] && continue
                case "$sub" in
                    "1") sync_one_repo "$dir" "$name" "$mode"
                       [ "$name" = "ccconfig" ] && { do_cconfig_post; echo -e "${GREEN}✅ 同步完成${NC}"; } ;;
                    "2") git_force_pull "$dir" "" "$name"
                       [ "$name" = "ccconfig" ] && do_cconfig_post ;;
                    "3") git_force_push "$dir" "" "$name" ;;
                esac
            fi
            ;;
    esac
    done  # while true
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
        REPO_DIR="$CCCONFIG_ROOT"
        REPO_NAME="ccconfig"
        if [ -n "${2:-}" ]; then
            case "$2" in
                *) REPO_DIR="$HOME/git/$2"; REPO_NAME="$2" ;;
            esac
        fi
        [ -d "$REPO_DIR/.git" ] || { echo -e "${RED}❌ 未找到仓库: $REPO_NAME${NC}"; exit 1; }
        git_force_pull "$REPO_DIR" "" "$REPO_NAME"
        [ "$REPO_NAME" = "cconfig" ] && do_cconfig_post
        ;;
    --push)
        REPO_DIR="$CCCONFIG_ROOT"
        REPO_NAME="ccconfig"
        if [ -n "${2:-}" ]; then
            case "$2" in
                *) REPO_DIR="$HOME/git/$2"; REPO_NAME="$2" ;;
            esac
        fi
        [ -d "$REPO_DIR/.git" ] || { echo -e "${RED}❌ 未找到仓库: $REPO_NAME${NC}"; exit 1; }
        git_force_push "$REPO_DIR" "" "$REPO_NAME"
        ;;
    --commitpush)
        REPO_DIR="$CCCONFIG_ROOT"
        REPO_NAME="ccconfig"
        COMMIT_MSG="${3:-}"
        if [ -n "${2:-}" ]; then
            case "$2" in
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
            ccconfig) REPO_DIR="$CCCONFIG_ROOT" ;;
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

# ── 以下函数原 lib/git-conflict.sh（已合并） ──

show_changed_since() {
    local before="$1" after="$2" dir="$3"
    local changed
    changed=$(git -C "$dir" diff --name-only "$before" "$after" 2>/dev/null || echo "")
    if [ -n "$changed" ]; then
        echo -e "${CYAN}变更文件:${NC}"
        echo "$changed" | while read f; do echo -e "  ${GRAY}$f${NC}"; done
    fi
}

git_force_pull() {
    local repo_dir="$1"
    local branch="${2:-$(git -C "$repo_dir" branch --show-current)}"
    local repo_name="${3:-$(basename "$repo_dir")}"
    echo ""
    echo -e "${RED}╔═════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  高危操作 — 远程覆盖本地     ║${NC}"
    echo -e "${RED}╚═════════════════════════════════════╝${NC}"
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
    if ! confirm "确认强制拉取？（高危）" n; then
        echo -e "  ${YELLOW}已取消${NC}"; return 1
    fi
    echo ""
    echo -e "${CYAN}  🔃 远程 → 本地: $repo_name${NC}"
    if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
        echo "     丢弃本地改动..."
        git -C "$repo_dir" checkout -- . 2>/dev/null || true
    fi
    local before
    before=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)
    local safety_stash="ccconfig-force-pull-safety-$(date +%s)"
    git -C "$repo_dir" stash push -u -m "$safety_stash" 2>/dev/null || true
    echo "     fetching origin/$branch..."
    git -C "$repo_dir" fetch origin "$branch" --prune
    git -C "$repo_dir" reset --hard "origin/$branch"
    git -C "$repo_dir" clean -fd 2>/dev/null || true
    if git -C "$repo_dir" stash list | grep -q "$safety_stash"; then
        echo "     ⚠  本地改动已存到 $safety_stash（reset 不会丢）"
    fi
    local after
    after=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)
    echo -e "  ${GREEN}✅ $repo_name: $before → $after（本地已与远程一致）${NC}"
    show_changed_since "$before" "$after" "$repo_dir"
    return 0
}

git_force_push() {
    local repo_dir="$1"
    local branch="${2:-$(git -C "$repo_dir" branch --show-current)}"
    local repo_name="${3:-$(basename "$repo_dir")}"
    echo ""
    echo -e "${RED}╔═════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  高危操作 — 本地覆盖远程     ║${NC}"
    echo -e "${RED}╚═════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  仓库: ${CYAN}$repo_name${NC} ($repo_dir)"
    echo -e "  分支: ${CYAN}$branch${NC}"
    echo -e "  方向: ${YELLOW}本地 → 远程${NC}（强制推送覆盖远程）"
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
    if ! confirm "确认强制推送？（高危）" n; then
        echo -e "  ${YELLOW}已取消${NC}"; return 1
    fi
    echo ""
    echo -e "${CYAN}  🔃 本地 → 远程: $repo_name${NC}"
    echo "     force pushing to origin/$branch..."
    git -C "$repo_dir" push --force origin "$branch"
    echo -e "  ${GREEN}✅ $repo_name → origin/$branch（远程已强制覆盖）${NC}"
    return 0
}

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
    local conflict_items=("远程覆盖本地" "本地覆盖远程")
    $with_rebase && conflict_items+=("Rebase（推荐）")
    conflict_items+=("取消")
    local cancel_idx=${#conflict_items[@]}  # 取消的序号（末项）
    choice=$(menu_select "冲突处理" "${conflict_items[@]}")
    [[ -z "$choice" || "$choice" == "0" || "$choice" == "$cancel_idx" ]] && { echo -e "  ${YELLOW}已取消${NC}"; return 1; }
    case "$choice" in
        1)  # 远程覆盖本地
            echo ""
            echo -e "${CYAN}  🔃 远程 → 本地${NC}"
            if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
                git -C "$repo_dir" checkout -- . 2>/dev/null || true
            fi
            local safety_stash="ccconfig-force-pull-safety-$(date +%s)"
            git -C "$repo_dir" stash push -u -m "$safety_stash" 2>/dev/null || true
            git -C "$repo_dir" reset --hard "origin/$branch"
            git -C "$repo_dir" clean -fd 2>/dev/null || true
            if git -C "$repo_dir" stash list | grep -q "$safety_stash"; then
                echo -e "  ${YELLOW}⚠  本地改动已存到 $safety_stash（reset 不会丢）${NC}"
            fi
            show_changed_since "$before" "$(git -C "$repo_dir" rev-parse --short HEAD)" "$repo_dir"
            echo -e "  ${GREEN}✅ 本地已与远程一致${NC}"; return 0
            ;;
        2)  # 本地覆盖远程
            echo ""
            echo -e "${CYAN}  🔃 本地 → 远程${NC}"
            git -C "$repo_dir" push --force origin "$branch"
            echo -e "  ${GREEN}✅ 远程已强制覆盖${NC}"; return 0
            ;;
        3)  # Rebase — 仅 $with_rebase=true 时才出现
            echo ""
            echo -e "${CYAN}  🔃 Rebase: 本地提交重放到远程之上${NC}"
            if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
                git -C "$repo_dir" stash push -m "sync-rebase-auto-stash" 2>/dev/null || true
            fi
            if ! git -C "$repo_dir" pull --rebase origin "$branch" 2>&1; then
                echo -e "  ${RED}❌ Rebase 冲突，需要手动解决${NC}"
                git -C "$repo_dir" rebase --abort 2>/dev/null || true
                git -C "$repo_dir" stash pop 2>/dev/null || true
                return 1
            fi
            git -C "$repo_dir" stash pop 2>/dev/null || true
            show_changed_since "$before" "$(git -C "$repo_dir" rev-parse --short HEAD)" "$repo_dir"
            echo -e "  ${GREEN}✅ Rebase 成功，本地已整合远程${NC}"
            timeout 60 git -C "$repo_dir" push origin "$branch" 2>&1 &&
                echo -e "  ${GREEN}✅ 已推送至 GitHub${NC}" ||
                echo -e "  ${YELLOW}⚠️ 推送失败，请手动推送${NC}"
            return 0
            ;;
    esac
}

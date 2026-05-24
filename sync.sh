#!/bin/bash
# sync.sh — 多仓库 Git 同步（智能 + 强制）
#
# 用法:
#   bash ccconfig/sync.sh [repo]              # 智能模式：先 ff-only，冲突时菜单选择
#   bash ccconfig/sync.sh --pull [repo]       # 云 → 本地（丢弃本地所有改动）
#   bash ccconfig/sync.sh --push [repo]       # 本地 → 云（强制推送覆盖远程）
#   bash ccconfig/sync.sh --check             # 仅检查（不拉取）
#
# ccconfig 仓库额外执行：重建链接 + skills + 依赖检查 + 新配置模板 + 摘要

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

# ========== 仓库解析 ==========
resolve_repo() {
    case "${1:-ccconfig}" in
        ccconfig)  echo "$SCRIPT_DIR" ;;
        projectu)  echo "$HOME/git/projectu" ;;
        *)
            local dir="$HOME/git/$1"
            if [ -d "$dir/.git" ]; then
                echo "$dir"
            else
                echo ""
            fi
            ;;
    esac
}

# ========== ccconfig 专属操作 ==========
do_cconfig_post() {
    if [ ! -f "$SCRIPT_DIR/setup-links.sh" ]; then
        return 0
    fi

    echo ""
    echo -e "${CYAN}── 重建符号链接 ──${NC}"
    bash "$SCRIPT_DIR/setup-links.sh"

    echo ""
    echo -e "${CYAN}── 同步 Skills ──${NC}"
    if [ -x "$SCRIPT_DIR/init-skill.sh" ]; then
        bash "$SCRIPT_DIR/init-skill.sh" sync
    fi

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
    if [ -x "$SCRIPT_DIR/deps-check.sh" ]; then
        bash "$SCRIPT_DIR/deps-check.sh" --required
    fi

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
    echo -e "  ${GRAY}启动同步: bash ccconfig/monitor.sh start${NC}"
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

# ========== ccconfig 同步后处理 ==========
cconfig_post_pull() {
    local before="$1" after="$2"
    show_changed "$before" "$after" "$SCRIPT_DIR"
    do_cconfig_post
    echo -e "${GREEN}✅ 同步完成${NC}"
}

# ========== 智能模式 ==========
smart_sync() {
    local repo_dir="$1" repo_name="$2"
    local branch=$(git -C "$repo_dir" branch --show-current)

    echo ""
    echo -e "${CYAN}🔃 sync 智能同步: ${BOLD}$repo_name${NC}"
    echo ""

    echo -e "  ${GRAY}fetching origin/$branch...${NC}"
    git -C "$repo_dir" fetch origin "$branch" --prune 2>/dev/null || {
        echo -e "  ${RED}❌ 无法连接远程${NC}"
        return 1
    }

    local before after
    before=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)
    after=$(git -C "$repo_dir" rev-parse --short "origin/$branch" 2>/dev/null)

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
            echo -e "  ${GREEN}✅ 已是最新且工作区干净: $before${NC}"
            if [ "$repo_name" = "cconfig" ]; then
                do_cconfig_post
                echo -e "${GREEN}✅ 同步完成${NC}"
            fi
            return 0
        fi
        return 0
    fi

    # 尝试 ff-only
    echo -e "  ${CYAN}$before → $after${NC}"
    set +e
    local pull_output
    pull_output=$(git -C "$repo_dir" pull --ff-only origin "$branch" 2>&1)
    local pull_status=$?
    set -e

    if [ $pull_status -eq 0 ]; then
        echo "$pull_output" | tail -2
        echo -e "  ${GREEN}✅ $repo_name: $before → $after${NC}"

        if [ "$repo_name" = "cconfig" ]; then
            cconfig_post_pull "$before" "$after"
        fi
        return 0
    fi

    # 拉取失败 — 冲突菜单
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
    echo -e "  ${BOLD}c)${NC} 取消，手动处理"
    echo ""
    read -p "  选择 [a/b/c]: " choice

    case "$choice" in
        a|A)
            echo ""
            echo -e "${CYAN}  🔃 远程 → 本地${NC}"
            if ! git -C "$repo_dir" diff --quiet 2>/dev/null || ! git -C "$repo_dir" diff --cached --quiet 2>/dev/null; then
                git -C "$repo_dir" checkout -- . 2>/dev/null || true
            fi
            git -C "$repo_dir" reset --hard "origin/$branch"
            git -C "$repo_dir" clean -fd 2>/dev/null || true
            echo -e "  ${GREEN}✅ 本地已与远程一致${NC}"

            if [ "$repo_name" = "cconfig" ]; then
                cconfig_post_pull "$before" "$(git -C "$repo_dir" rev-parse --short HEAD)"
            fi
            ;;
        b|B)
            echo ""
            echo -e "${CYAN}  🔃 本地 → 远程${NC}"
            git -C "$repo_dir" push --force origin "$branch"
            echo -e "  ${GREEN}✅ 远程已强制覆盖${NC}"
            ;;
        *)
            echo ""
            echo -e "  ${YELLOW}已取消，请在 Claude 中手动处理${NC}"
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

    if [ "$repo_name" = "cconfig" ]; then
        cconfig_post_pull "$before" "$after"
    fi
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

# ========== 检查模式 ==========
check_mode() {
    echo ""
    echo -e "${CYAN}🔄 ccconfig 状态检查${NC}"
    echo ""
    if [ -x "$SCRIPT_DIR/deps-check.sh" ]; then
        bash "$SCRIPT_DIR/deps-check.sh" --required
    fi
    do_summary
}

# ========== 帮助 ==========
show_help() {
    echo ""
    echo -e "${CYAN}sync.sh${NC} — 多仓库 Git 同步（智能 + 强制）"
    echo ""
    echo "用法:"
    echo "  bash ccconfig/sync.sh [repo]             智能模式（先 ff-only，冲突时菜单选择 a/b/c）"
    echo "  bash ccconfig/sync.sh --pull [repo]      云 → 本地（丢弃本地所有改动）"
    echo "  bash ccconfig/sync.sh --push [repo]      本地 → 云（强制推送覆盖远程）"
    echo "  bash ccconfig/sync.sh --check            仅检查（不拉取）"
    echo ""
    echo "已知仓库: ccconfig, projectu"
    echo "也可传入 ~/git/ 下任意仓库名"
    echo ""
    echo "ccconfig 仓库额外执行: 重建链接 + skills + 新配置模板 + 依赖检查 + 摘要"
}

# ========== 主流程 ==========
MODE="auto"
REPO_ARG=""

case "${1:-}" in
    --pull)
        MODE="pull"
        REPO_ARG="${2:-ccconfig}"
        ;;
    --push)
        MODE="push"
        REPO_ARG="${2:-ccconfig}"
        ;;
    --check)
        check_mode
        exit 0
        ;;
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        MODE="auto"
        REPO_ARG="${1:-ccconfig}"
        ;;
esac

REPO_DIR=$(resolve_repo "$REPO_ARG")
REPO_NAME="$REPO_ARG"

if [ -z "$REPO_DIR" ] || [ ! -d "$REPO_DIR/.git" ]; then
    echo -e "${RED}❌ 未找到仓库: $REPO_NAME${NC}"
    echo "  已知: ccconfig, projectu"
    echo "  或确保 ~/git/$REPO_NAME 是有效 git 仓库"
    exit 1
fi

case "$MODE" in
    auto)   smart_sync "$REPO_DIR" "$REPO_NAME" ;;
    pull)   force_pull "$REPO_DIR" "$REPO_NAME" ;;
    push)   force_push "$REPO_DIR" "$REPO_NAME" ;;
esac

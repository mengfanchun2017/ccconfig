#!/bin/bash
# gitforce — 智能同步 + 强制单向同步
#
# 用法:
#   bash ccconfig/gitforce.sh [repo]             # 智能模式：先 ff-only，冲突时菜单选择
#   bash ccconfig/gitforce.sh --pull [repo]       # 云 → 本地（丢弃本地所有改动）
#   bash ccconfig/gitforce.sh --push [repo]       # 本地 → 云（强制推送覆盖远程）
#
# ⚠️ --pull / --push 不可逆，使用前务必确认

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo ""
    echo -e "${CYAN}gitforce${NC} — 智能同步 + 强制单向同步"
    echo ""
    echo "用法:"
    echo "  bash ccconfig/gitforce.sh [repo]            智能模式（先 ff-only，冲突时选择）"
    echo "  bash ccconfig/gitforce.sh --pull [repo]      云 → 本地（丢弃所有本地改动）"
    echo "  bash ccconfig/gitforce.sh --push [repo]      本地 → 云（强制推送覆盖远程）"
    echo ""
    echo "已知仓库: ccconfig, projectu"
    exit 1
}

# === 仓库解析 ===
resolve_repo() {
    case "${1:-ccconfig}" in
        ccconfig)  echo "$HOME/git/ccconfig" ;;
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

# === 参数解析 ===
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
    --help|-h)
        usage
        ;;
    *)
        MODE="auto"
        REPO_ARG="${1:-ccconfig}"
        ;;
esac

REPO_NAME="$REPO_ARG"
REPO_DIR=$(resolve_repo "$REPO_NAME")

if [ -z "$REPO_DIR" ] || [ ! -d "$REPO_DIR/.git" ]; then
    echo -e "${RED}❌ 未找到仓库: $REPO_NAME${NC}"
    echo "   已知: ccconfig, projectu"
    echo "   或确保 ~/git/$REPO_NAME 是有效 git 仓库"
    exit 1
fi

BRANCH=$(git -C "$REPO_DIR" branch --show-current)

# === 智能模式 ===
if [ "$MODE" = "auto" ]; then
    echo ""
    echo -e "${CYAN}🔃 gitforce 智能同步: $REPO_NAME${NC}"
    echo ""

    # fetch
    echo "   fetching origin/$BRANCH..."
    git -C "$REPO_DIR" fetch origin "$BRANCH" --prune 2>/dev/null || {
        echo -e "${RED}❌ 无法连接远程${NC}"
        exit 1
    }

    local_commit=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null)
    remote_commit=$(git -C "$REPO_DIR" rev-parse --short "origin/$BRANCH" 2>/dev/null)

    if [ "$local_commit" = "$remote_commit" ]; then
        dirty=false
        if ! git -C "$REPO_DIR" diff --quiet 2>/dev/null || ! git -C "$REPO_DIR" diff --cached --quiet 2>/dev/null; then
            dirty=true
        fi
        if [ -n "$(git -C "$REPO_DIR" ls-files -u 2>/dev/null)" ]; then
            dirty=true
        fi
        if $dirty; then
            echo -e "${YELLOW}⚠️  HEAD 与远程一致 ($local_commit)，但工作区有未提交改动或冲突${NC}"
            echo ""
            git -C "$REPO_DIR" status --short 2>/dev/null | head -10
            echo ""
        else
            echo -e "${GREEN}✅ 已是最新且工作区干净: $local_commit${NC}"
            exit 0
        fi
    fi

    # 尝试 ff-only
    set +e
    pull_output=$(git -C "$REPO_DIR" pull --ff-only origin "$BRANCH" 2>&1)
    pull_status=$?
    set -e

    if [ $pull_status -eq 0 ]; then
        echo "$pull_output" | tail -2
        echo -e "${GREEN}✅ $REPO_NAME: $local_commit → $remote_commit${NC}"

        if [ "$REPO_NAME" = "cconfig" ] && [ -f "$REPO_DIR/setup-links.sh" ]; then
            echo "   🔗 重建符号链接..."
            bash "$REPO_DIR/setup-links.sh"
            echo "   🔄 同步 skills..."
            bash "$REPO_DIR/init-skill.sh" sync
        fi
        exit 0
    fi

    # 拉取失败 — 显示冲突菜单
    has_uncommitted=false
    if ! git -C "$REPO_DIR" diff --quiet 2>/dev/null || ! git -C "$REPO_DIR" diff --cached --quiet 2>/dev/null; then
        has_uncommitted=true
    fi

    echo ""
    echo -e "${YELLOW}⚠️  自动拉取失败${NC}"
    if $has_uncommitted; then
        echo "  原因: 本地有未提交的改动"
        git -C "$REPO_DIR" status --short 2>/dev/null | head -10
    else
        echo "  原因: 本地与远程已分叉"
    fi
    echo ""
    echo "  本地: $local_commit"
    echo "  远程: $remote_commit"
    echo ""
    echo "  a) 远程覆盖本地（丢弃本地所有改动）"
    echo "  b) 本地覆盖远程（强制推送本地到远程）"
    echo "  c) 取消，在 Claude 中手动处理"
    echo ""
    read -p "选择 [a/b/c]: " choice

    case "$choice" in
        a|A)
            echo ""
            echo -e "${CYAN}🔃 远程 → 本地${NC}"
            if ! git -C "$REPO_DIR" diff --quiet 2>/dev/null || ! git -C "$REPO_DIR" diff --cached --quiet 2>/dev/null; then
                git -C "$REPO_DIR" checkout -- . 2>/dev/null || true
            fi
            git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
            git -C "$REPO_DIR" clean -fd 2>/dev/null || true
            echo -e "${GREEN}✅ 本地已与远程一致${NC}"

            if [ "$REPO_NAME" = "cconfig" ] && [ -f "$REPO_DIR/setup-links.sh" ]; then
                echo "   🔗 重建符号链接..."
                bash "$REPO_DIR/setup-links.sh"
                echo "   🔄 同步 skills..."
                bash "$REPO_DIR/init-skill.sh" sync
            fi
            ;;
        b|B)
            echo ""
            echo -e "${CYAN}🔃 本地 → 远程${NC}"
            git -C "$REPO_DIR" push --force origin "$BRANCH"
            echo -e "${GREEN}✅ 远程已强制覆盖${NC}"
            ;;
        *)
            echo ""
            echo -e "${YELLOW}已取消，请在 Claude 中手动处理${NC}"
            exit 1
            ;;
    esac
    exit 0
fi

# === 强制模式（--pull / --push）===
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  ⚠️  高危操作警告                                 ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  仓库: ${CYAN}$REPO_NAME${NC} ($REPO_DIR)"
echo -e "  分支: ${CYAN}$BRANCH${NC}"

if [ "$MODE" = "pull" ]; then
    echo -e "  方向: ${YELLOW}云 → 本地${NC}（丢弃本地所有改动，强制对齐远程）"
    echo ""
    if ! git -C "$REPO_DIR" diff --quiet 2>/dev/null || ! git -C "$REPO_DIR" diff --cached --quiet 2>/dev/null; then
        echo -e "  ${YELLOW}⚠️  本地未提交的改动（将被丢弃）：${NC}"
        git -C "$REPO_DIR" status --short 2>/dev/null | head -20
        echo ""
    fi
    ahead=$(git -C "$REPO_DIR" rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "?")
    if [ "$ahead" != "?" ] && [ "$ahead" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  本地领先远程 $ahead 个提交（将被丢弃）${NC}"
        git -C "$REPO_DIR" log --oneline "origin/$BRANCH..HEAD" 2>/dev/null | head -10
        echo ""
    fi
else
    echo -e "  方向: ${YELLOW}本地 → 云${NC}（强制推送覆盖远程，其他人会丢失工作）"
    echo ""
    ahead=$(git -C "$REPO_DIR" rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "0")
    if [ "$ahead" -gt 0 ]; then
        echo -e "  ${CYAN}本地领先远程 $ahead 个提交（将强制推送）：${NC}"
        git -C "$REPO_DIR" log --oneline "origin/$BRANCH..HEAD" 2>/dev/null | head -10
        echo ""
    fi
    behind=$(git -C "$REPO_DIR" rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo "0")
    if [ "$behind" -gt 0 ]; then
        echo -e "  ${RED}⚠️  远程有 $behind 个本地没有的提交（将被永久覆盖）：${NC}"
        git -C "$REPO_DIR" log --oneline "HEAD..origin/$BRANCH" 2>/dev/null | head -10
        echo ""
    fi
fi

echo -e "  ${RED}此操作不可逆！${NC}"
echo ""
read -p "确认执行？输入仓库名 \"$REPO_NAME\" 确认: " confirm

if [ "$confirm" != "$REPO_NAME" ]; then
    echo -e "${YELLOW}已取消${NC}"
    exit 0
fi

echo ""

if [ "$MODE" = "pull" ]; then
    echo -e "${CYAN}🔃 云 → 本地: $REPO_NAME${NC}"

    if ! git -C "$REPO_DIR" diff --quiet 2>/dev/null || ! git -C "$REPO_DIR" diff --cached --quiet 2>/dev/null; then
        echo "   丢弃本地改动..."
        git -C "$REPO_DIR" checkout -- . 2>/dev/null || true
    fi

    echo "   fetching origin/$BRANCH..."
    git -C "$REPO_DIR" fetch origin "$BRANCH" --prune
    git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
    git -C "$REPO_DIR" clean -fd 2>/dev/null || true

    echo -e "${GREEN}✅ $REPO_NAME → origin/$BRANCH（本地已与远程一致）${NC}"

    if [ "$REPO_NAME" = "cconfig" ] && [ -f "$REPO_DIR/setup-links.sh" ]; then
        echo "   🔗 重建符号链接..."
        bash "$REPO_DIR/setup-links.sh"
        echo "   🔄 同步 skills..."
        bash "$REPO_DIR/init-skill.sh" sync
    fi
else
    echo -e "${CYAN}🔃 本地 → 云: $REPO_NAME${NC}"
    echo "   force pushing to origin/$BRANCH..."
    git -C "$REPO_DIR" push --force origin "$BRANCH"
    echo -e "${GREEN}✅ $REPO_NAME → origin/$BRANCH（远程已强制覆盖）${NC}"
fi

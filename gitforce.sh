#!/bin/bash
# gitforce — 强制单向同步（高危操作）
#
# 用法:
#   bash ccconfig/gitforce.sh [repo]             # 云强制覆盖本地（默认 --pull）
#   bash ccconfig/gitforce.sh --pull [repo]       # 云 → 本地（丢弃本地所有改动）
#   bash ccconfig/gitforce.sh --push [repo]       # 本地 → 云（强制推送覆盖远程）
#
# 行为:
#   --pull: git fetch + reset --hard → 本地完全与远程一致，丢弃本地改动
#   --push: git push --force → 远程完全与本地一致，覆盖远程历史
#
# ⚠️ 此操作不可逆，使用前务必确认

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo ""
    echo -e "${CYAN}gitforce${NC} — 强制单向同步（高危操作）"
    echo ""
    echo "用法:"
    echo "  bash ccconfig/gitforce.sh [repo]            云 → 本地（默认）"
    echo "  bash ccconfig/gitforce.sh --pull [repo]      云 → 本地"
    echo "  bash ccconfig/gitforce.sh --push [repo]      本地 → 云"
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
MODE=""
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
        MODE="pull"
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

cd "$REPO_DIR"
BRANCH=$(git branch --show-current)

# === 危险操作警告 ===
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
    # 显示本地待丢弃的改动
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        echo -e "  ${YELLOW}⚠️  本地未提交的改动（将被丢弃）：${NC}"
        git status --short 2>/dev/null | head -20
        echo ""
    fi
    # 显示本地独有的提交
    local ahead=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "?")
    if [ "$ahead" != "?" ] && [ "$ahead" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  本地领先远程 $ahead 个提交（将被丢弃）${NC}"
        git log --oneline "origin/$BRANCH..HEAD" 2>/dev/null | head -10
        echo ""
    fi
else
    echo -e "  方向: ${YELLOW}本地 → 云${NC}（强制推送覆盖远程，其他人会丢失工作）"
    echo ""
    # 显示将要推送的本地独有提交
    local ahead=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "0")
    if [ "$ahead" -gt 0 ]; then
        echo -e "  ${CYAN}本地领先远程 $ahead 个提交（将强制推送）：${NC}"
        git log --oneline "origin/$BRANCH..HEAD" 2>/dev/null | head -10
        echo ""
    fi
    # 检查远程是否有本地没有的提交
    local behind=$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo "0")
    if [ "$behind" -gt 0 ]; then
        echo -e "  ${RED}⚠️  远程有 $behind 个本地没有的提交（将被永久覆盖）：${NC}"
        git log --oneline "HEAD..origin/$BRANCH" 2>/dev/null | head -10
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

# === 执行 ===
if [ "$MODE" = "pull" ]; then
    echo -e "${CYAN}🔃 云 → 本地: $REPO_NAME${NC}"

    # 丢弃所有本地改动
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        echo "   丢弃本地改动..."
        git checkout -- . 2>/dev/null || true
    fi

    # 拉取远程并强制对齐
    echo "   fetching origin/$BRANCH..."
    git fetch origin "$BRANCH" --prune
    git reset --hard "origin/$BRANCH"

    # 清理未跟踪文件
    git clean -fd 2>/dev/null || true

    echo -e "${GREEN}✅ $REPO_NAME → origin/$BRANCH（本地已与远程一致）${NC}"

    # ccconfig 特有：重建符号链接 + 同步 skills
    if [ "$REPO_NAME" = "ccconfig" ] && [ -f "$REPO_DIR/setup-links.sh" ]; then
        echo "   🔗 重建符号链接..."
        bash "$REPO_DIR/setup-links.sh"
        echo "   🔄 同步 skills..."
        bash "$REPO_DIR/init-skill.sh" sync
    fi
else
    echo -e "${CYAN}🔃 本地 → 云: $REPO_NAME${NC}"

    # 强制推送
    echo "   force pushing to origin/$BRANCH..."
    git push --force origin "$BRANCH"

    echo -e "${GREEN}✅ $REPO_NAME → origin/$BRANCH（远程已强制覆盖）${NC}"
fi

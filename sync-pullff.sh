#!/bin/bash
# pullff - 强制拉取远程仓库覆盖本地
#
# 用法（暗号）:
#   pullff          → 拉取 ccconfig（默认）
#   pullff projectu → 拉取 projectu
#   pullff <name>   → 拉取 ~/git/<name>（通用路径）
#
# 行为: git fetch + git reset --hard → 本地完全与远程一致

set -e

# === 已知仓库映射 ===
resolve_repo() {
    case "${1:-ccconfig}" in
        ccconfig)  echo "/home/francis/git/ccconfig" ;;
        projectu)  echo "/home/francis/git/projectu" ;;
        *)
            # 尝试 ~/git/<name> 通用路径
            local dir="/home/francis/git/$1"
            if [ -d "$dir/.git" ]; then
                echo "$dir"
            else
                echo ""
            fi
            ;;
    esac
}

REPO_NAME="${1:-ccconfig}"
REPO_DIR=$(resolve_repo "$REPO_NAME")

if [ -z "$REPO_DIR" ] || [ ! -d "$REPO_DIR/.git" ]; then
    echo "❌ 未找到仓库: $REPO_NAME"
    echo "   已知: ccconfig, projectu"
    echo "   或确保 ~/git/$REPO_NAME 是有效 git 仓库"
    exit 1
fi

echo "🔃 pullff → $REPO_NAME ($REPO_DIR)"

cd "$REPO_DIR"

BRANCH=$(git branch --show-current)
echo "   当前分支: $BRANCH"

# 丢弃所有本地改动 + 清理未跟踪文件
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "   ⚠️  本地有未提交改动，已丢弃"
    git checkout -- . 2>/dev/null || true
fi

# 拉取远程 + 强制对齐
echo "   fetching origin/$BRANCH..."
git fetch origin "$BRANCH" --prune
git reset --hard "origin/$BRANCH"

# 清理未跟踪文件和目录
git clean -fd 2>/dev/null || true

echo "✅ $REPO_NAME → origin/$BRANCH (强制同步完成，本地与远程一致)"

# 如果是 ccconfig，重建符号链接 + 同步 skills
if [ "$REPO_NAME" = "ccconfig" ] && [ -f "$REPO_DIR/setup-links.sh" ]; then
    echo "   🔗 重建符号链接..."
    bash "$REPO_DIR/setup-links.sh"
    echo "   🔄 同步 skills..."
    bash "$REPO_DIR/init-skill.sh sync"
fi

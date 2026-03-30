#!/bin/bash
# Claude Config - 同步到 GitHub
#
# 功能：
# 1. 提交当前配置更改
# 2. 推送到 GitHub
#
# 使用：
#   bash claude-config/end.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $1"; }
good() { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 检查是否是 git 仓库
if [ ! -d ".git" ]; then
    warn "不是 git 仓库，跳过同步"
    exit 0
fi

# 检查远程仓库
if ! git remote get-url origin &>/dev/null; then
    warn "没有远程仓库，跳过同步"
    exit 0
fi

echo ""
echo "========================================"
echo "  Claude Config 同步"
echo "========================================"
echo ""

# 检查是否有变化
if git diff --quiet && git status --porcelain | grep -q .; then
    info "没有需要同步的更改"
    exit 0
fi

# 显示变化
echo "检测到以下更改："
git status --short
echo ""

# 添加所有更改
git add -A

# 获取更改统计
changes=$(git diff --cached --stat)
echo ""
echo "提交内容："
echo "$changes"
echo ""

# 生成提交消息（包含时间戳）
timestamp=$(date "+%Y-%m-%d %H:%M:%S")
commit_msg="同步配置: $timestamp

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

# 提交
if git commit -m "$commit_msg"; then
    good "✅ 已提交"
else
    warn "没有需要提交的更改"
    exit 0
fi

# 推送
echo ""
info "推送到 GitHub..."
if git push origin main; then
    good "✅ 已推送到 GitHub"
else
    warn "推送失败，请检查网络或认证状态"
    exit 1
fi

echo ""
echo "========================================"
echo "  同步完成 ✅"
echo "========================================"

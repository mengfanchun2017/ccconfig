#!/bin/bash
# Claude Code - 结束工作 (Linux/WSL)
#
# ============================================================
# 功能说明
# ============================================================
#
# 由于 start.sh 已通过符号链接建立双向同步，
# 本脚本主要完成 Git 操作：
#   1. git add .     - 暂存所有更改
#   2. git commit    - 提交更改
#   3. git push      - 推送到 GitHub
#
# 注意：MEMORY.md 等文件已通过符号链接同步，
#       无需额外复制操作。
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "========================================"
echo "  Claude Code - 结束工作"
echo "  当前系统: Linux/WSL"
echo "========================================"
echo ""
echo "仓库目录: $REPO_DIR"
echo ""

cd "$REPO_DIR"

# ========== Git 状态 ==========
echo "[1/3] 检查 git 状态..."
git status --short
echo ""

# ========== Git 提交 ==========
echo "[2/3] 提交更改..."
git add .

if [ -z "$1" ]; then
    read -p "请输入提交信息 (默认: 更新配置): " commit_msg
else
    commit_msg="$1"
fi
if [ -z "$commit_msg" ]; then
    commit_msg="更新配置"
fi
git commit -m "$commit_msg"
echo "✅ 已提交: $commit_msg"
echo ""

# ========== Git 推送 ==========
echo "[3/3] 推送到 GitHub..."
git push
echo "✅ 成功推送到 GitHub"
echo ""

echo "========================================"
echo "  ✅ 同步完成！"
echo "========================================"
echo ""

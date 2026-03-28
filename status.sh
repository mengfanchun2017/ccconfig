#!/bin/bash
# Claude Config - 状态检查与 Git 拉取
#
# 功能：
# 1. 自动从 GitHub 拉取最新配置
# 2. 检查符号链接状态
# 3. 检查 auto-sync 状态
# 4. 检查 MCP 配置
#
# 用途：每次启动终端时自动运行（通过 /etc/profile.d/ 或 ~/.bashrc）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========== Git 拉取 ==========
git_pull() {
    cd "$REPO_DIR"

    # 检查是否是 git 仓库
    if [ ! -d ".git" ]; then
        return 0
    fi

    # 尝试拉取
    if git fetch origin main 2>/dev/null; then
        local updates=$(git rev HEAD..origin/main 2>/dev/null | wc -l)
        if [ "$updates" -gt 0 ]; then
            echo -e "${CYAN}[config]${NC} 发现 $updates 个更新，正在拉取..."
            if git pull --rebase origin main 2>/dev/null; then
                echo -e "${GREEN}[config]${NC} ✅ 配置已更新"
            fi
        fi
    fi
}

# ========== 显示状态摘要 ==========
show_summary() {
    cd "$REPO_DIR"

    local issues=0

    # 检查符号链接
    if [ ! -L "$HOME/.claude/settings.json" ] || [ ! -e "$HOME/.claude/settings.json" ]; then
        issues=$((issues + 1))
    fi
    if [ ! -L "$HOME/CLAUDE.md" ] || [ ! -e "$HOME/CLAUDE.md" ]; then
        issues=$((issues + 1))
    fi

    # 检查 auto-sync
    if ! pgrep -f "auto-sync.sh start" >/dev/null 2>&1; then
        issues=$((issues + 1))
    fi

    # 显示简短摘要
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}[config]${NC} ✅ 配置就绪"
    else
        echo -e "${YELLOW}[config]${NC} ⚠️  有 $issues 个配置问题，运行 ${CYAN}bash $REPO_DIR/init.sh status${NC} 查看"
    fi
}

# 执行
git_pull
show_summary

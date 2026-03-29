#!/bin/bash
# Claude Config - 状态检查与 Git 拉取
#
# 功能：
# 1. 自动从 GitHub 拉取最新配置
# 2. 检查符号链接状态（含 MEMORY.md）
# 3. 检查 auto-sync 状态
# 4. 显示最近 5 次推送记录
#
# 用途：每次启动终端时自动运行（通过 /etc/profile.d/ 或 ~/.bashrc）
#       以及通过 SessionStart hook 在 Claude 启动时运行

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

    # 检查 MEMORY.md 符号链接
    local memory_link="$HOME/.claude/projects/-home-francis-git/memory/MEMORY.md"
    if [ ! -L "$memory_link" ] || [ ! -e "$memory_link" ]; then
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

# ========== 显示最近推送记录 ==========
show_recent_pushes() {
    cd "$REPO_DIR"

    # 检查是否是 git 仓库
    if [ ! -d ".git" ]; then
        return 0
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}[config]${NC} 📋 最近推送记录："

    # 获取最近5次推送的 note（第一条行是 commit hash，第二行是 message）
    local count=0
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            echo -e "  ${YELLOW}•${NC} $line"
            count=$((count + 1))
        fi
        if [ $count -ge 5 ]; then
            break
        fi
    done < <(git log --oneline -10 --format="%s" 2>/dev/null | head -5)
}

# 执行
git_pull
show_summary
show_recent_pushes

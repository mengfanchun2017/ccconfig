#!/bin/bash
# ==============================================
# setup-links.sh — 创建 ~/.claude/ 的符号链接
#
# 将 ccconfig/link/ 下的配置文件链接到 ~/.claude/：
#   settings.json, .config.json, agents, rules, commands
#   以及 ~/CLAUDE.md, memory 目录
#
# 使用：
#   bash ccconfig/setup-links.sh
#
# 调用方：
#   init-ubuntu.sh    — 首次初始化时
#   sync-pullff.sh    — 手动 pullff 后
#   sync-monitor.sh   — auto-sync pull 成功后
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# 颜色
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

setup_link() {
    local link="$1"
    local target="$2"
    local name="$3"

    mkdir -p "$(dirname "$link")"
    if [[ -L "$link" ]]; then
        local existing=$(readlink -f "$link")
        local expected=$(readlink -f "$target" 2>/dev/null)
        if [[ "$existing" = "$expected" ]]; then
            info "$name: 已链接，跳过"
            return 0
        fi
        rm -f "$link"
    elif [[ -e "$link" ]]; then
        rm -f "$link"
    fi
    ln -sf "$target" "$link"
    success "$name: 已链接"
}

setup_symlinks() {
    section "符号链接"

    cd "$SCRIPT_DIR"

    setup_link "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/link/settings.json" "settings.json"
    setup_link "$CLAUDE_DIR/.config.json" "$SCRIPT_DIR/link/.config.json" ".config.json"
    setup_link "$HOME/CLAUDE.md" "$SCRIPT_DIR/link/CLAUDE.md" "CLAUDE.md"

    # agents（指令分流 agent）
    if [[ -d "$SCRIPT_DIR/link/agents" ]]; then
        setup_link "$CLAUDE_DIR/agents" "$SCRIPT_DIR/link/agents" "agents"
    fi

    # rules（条件规则，按路径加载）
    if [[ -d "$SCRIPT_DIR/link/rules" ]]; then
        setup_link "$CLAUDE_DIR/rules" "$SCRIPT_DIR/link/rules" "rules"
    fi

    # commands（自定义斜杠命令）
    if [[ -d "$SCRIPT_DIR/link/commands" ]]; then
        setup_link "$CLAUDE_DIR/commands" "$SCRIPT_DIR/link/commands" "commands"
    fi

    # MEMORY.md - 自动检测所有项目
    for mem_dir in "$SCRIPT_DIR/link/projects"/-home-francis-*/; do
        if [[ -d "$mem_dir" ]] && [[ -f "${mem_dir}MEMORY.md" ]]; then
            REPO_MEMORY_NAME=$(basename "$mem_dir")
            MEMORY_DIR="$CLAUDE_DIR/projects/$REPO_MEMORY_NAME/memory"
            MEMORY_REPO_PATH="${mem_dir}MEMORY.md"

            mkdir -p "$MEMORY_DIR"
            setup_link "$MEMORY_DIR/MEMORY.md" "$MEMORY_REPO_PATH" "$REPO_MEMORY_NAME/MEMORY.md"
        fi
    done

    # 如果没有任何项目目录，确保至少有总目录链接
    if [[ ! -d "$SCRIPT_DIR/link/projects/-home-francis-git" ]]; then
        REPO_MEMORY_NAME="-home-francis-git"
        MEMORY_DIR="$CLAUDE_DIR/projects/$REPO_MEMORY_NAME/memory"
        MEMORY_REPO_PATH="$SCRIPT_DIR/link/projects/$REPO_MEMORY_NAME/MEMORY.md"

        mkdir -p "$MEMORY_DIR"
        setup_link "$MEMORY_DIR/MEMORY.md" "$MEMORY_REPO_PATH" "$REPO_MEMORY_NAME/MEMORY.md"
    fi
}

setup_symlinks

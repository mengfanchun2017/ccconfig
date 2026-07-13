#!/bin/bash
# ==============================================
# setup-links.sh — ccconfig 公开部分符号链接
#
# 仅处理公开内容：agents, rules, commands, skills → ~/.claude/
# 私有部分（CLAUDE.md, settings.json, .config.json, memory, projects）
# 由 ccprivate/setup.sh 管理。
#
# 使用：
#   bash ccconfig/setup-links.sh
#   （通常由 ccprivate/setup.sh 调用）
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
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

    # agents（指令分流 agent）
    if [[ -d "$CCCONFIG_ROOT/link/agents" ]]; then
        setup_link "$CLAUDE_DIR/agents" "$CCCONFIG_ROOT/link/agents" "agents"
    fi

    # rules（条件规则，按路径加载）
    if [[ -d "$CCCONFIG_ROOT/link/rules" ]]; then
        setup_link "$CLAUDE_DIR/rules" "$CCCONFIG_ROOT/link/rules" "rules"
    fi

    # commands（自定义斜杠命令）
    if [[ -d "$CCCONFIG_ROOT/link/commands" ]]; then
        setup_link "$CLAUDE_DIR/commands" "$CCCONFIG_ROOT/link/commands" "commands"
    fi

    # shell_aliases.sh（跨终端 shell 别名同步）
    if [[ -f "$CCCONFIG_ROOT/link/shell_aliases.sh" ]]; then
        setup_link "$CLAUDE_DIR/shell_aliases.sh" "$CCCONFIG_ROOT/link/shell_aliases.sh" "shell_aliases.sh"
    fi

    # skills 由 init.sh all 步骤 5 统一管理，此处不做，避免重复初始化
    # 如需单独初始化 skills: bash ccconfig/init-skill.sh sync

    # git pre-commit hook（防私密文件意外提交）
    local git_hook="$CCCONFIG_ROOT/.git/hooks/pre-commit"
    local hook_src="$CCCONFIG_ROOT/hooks/pre-commit"
    if [[ -f "$hook_src" ]]; then
        if [[ -L "$git_hook" ]] && [[ "$(readlink -f "$git_hook")" == "$(readlink -f "$hook_src")" ]]; then
            info "pre-commit hook: 已链接，跳过"
        else
            [[ -e "$git_hook" ]] && rm -f "$git_hook"
            ln -sf "$hook_src" "$git_hook"
            success "pre-commit hook: 已安装"
        fi
    fi
}

setup_symlinks

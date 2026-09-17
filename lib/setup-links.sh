#!/bin/bash
# ==============================================
# setup-links.sh — ccconfig 公开部分符号链接
#
# 处理：shell_init.sh + pre-commit hook
# rules/agents/commands 已移至 ccprivate/setup.sh 管理
# 私有部分（CLAUDE.md, settings.json, .config.json, memory, projects）
# 由 ccprivate/setup.sh 管理。
#
# 使用：
#   bash ccconfig/lib/setup-links.sh
#   （通常由 ccprivate/setup.sh 调用）
# ==============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
CLAUDE_DIR="$HOME/.claude"
source "$SCRIPT_DIR/dry-run.sh"
source "$SCRIPT_DIR/colors.sh"

setup_link() {
    local link="$1"
    local target="$2"
    local name="$3"

    run mkdir -p "$(dirname "$link")"
    # 死链必须 [ -e ] 才排除：readlink -f 对死链返回规范路径字符串（非空），
    # 只比字符串会把死链判成"已链接，跳过" → 永远不修
    if [[ -L "$link" ]] && [[ -e "$link" ]]; then
        local existing=$(readlink -f "$link" 2>/dev/null || true)
        local expected=$(readlink -f "$target" 2>/dev/null || true)
        if [[ -n "$existing" && "$existing" = "$expected" ]]; then
            info "$name: 已链接，跳过"
            return 0
        fi
        run rm -f "$link"
    elif [[ -L "$link" ]]; then
        warn "$name: 死链（目标不存在），重建"
        run rm -f "$link"
    elif [[ -e "$link" ]]; then
        run rm -f "$link"
    fi
    # 目标不存在时不建链：建出的死链会让问题更隐蔽（下次还被判"已链接，跳过"）
    if [[ ! -e "$target" ]]; then
        warn "$name: 目标不存在，跳过（$target）"
        return 0
    fi
    run ln -sf "$target" "$link"
    ok "$name: 已链接"
}

setup_symlinks() {
    echo -e "\n${CYAN}符号链接${NC}"

    # 清理旧 shell_aliases.sh（已重命名为 shell_init.sh）
    [[ -L "$CLAUDE_DIR/shell_aliases.sh" ]] && rm -f "$CLAUDE_DIR/shell_aliases.sh"

    # shell_init.sh（终端初始化：monitor 自启、memory symlink、别名/函数）
    if [[ -f "$CCCONFIG_ROOT/lib/shell_init.sh" ]]; then
        setup_link "$CLAUDE_DIR/shell_init.sh" "$CCCONFIG_ROOT/lib/shell_init.sh" "shell_init.sh"
    fi

    # skills 由 option-skill/init.sh 管理（可选组件），此处不做，避免重复初始化
    # 如需单独初始化 skills: bash ccconfig/init-skill.sh sync

    # rules/agents/commands 已移至 ccprivate/setup.sh 管理
    # ~/.claude/rules  → ccprivate/rules
    # ~/.claude/agents → ccprivate/agents
    # ~/.claude/commands → ccprivate/commands

    # git pre-commit hook（防私密文件意外提交）
    local git_hook="$CCCONFIG_ROOT/.git/hooks/pre-commit"
    local hook_src="$CCCONFIG_ROOT/hooks/pre-commit"
    if [[ -f "$hook_src" ]]; then
        if [[ -L "$git_hook" ]] && [[ -e "$git_hook" ]] && [[ "$(readlink -f "$git_hook")" == "$(readlink -f "$hook_src")" ]]; then
            info "pre-commit hook: 已链接，跳过"
        else
            [[ -e "$git_hook" ]] && run rm -f "$git_hook"
            run ln -sf "$hook_src" "$git_hook"
            ok "pre-commit hook: 已安装"
        fi
    fi
}

dry_run_banner
case "${1:-}" in
    ""|--link|--run)
        setup_symlinks
        ;;
    --dry-run)
        setup_symlinks
        ;;
    --help|-h)
        echo "用法: bash setup-links.sh [--dry-run]"
        echo "  --dry-run  显示将执行的操作，不实际修改"
        ;;
    *)
        echo "未知参数: $1" >&2
        exit 1
        ;;
esac
dry_run_footer

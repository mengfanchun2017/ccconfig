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

# 链接状态收集：正常态只计数（末尾一行汇总），动作/异常才逐行列出。
# 避免全就绪时刷 N 行「已链接，跳过」——看不出结论，还曾被 monitor 染黄。
_SL_READY=(); _SL_ACT=0; _SL_WARN=0
_sl_flush() {
    local title="$1"
    if [ "$_SL_ACT" -eq 0 ] && [ "$_SL_WARN" -eq 0 ]; then
        ok "$title：${#_SL_READY[@]} 项全部已就绪"
    else
        local msg="$title：${#_SL_READY[@]} 已就绪"
        [ "$_SL_ACT" -gt 0 ] && msg="$msg, $_SL_ACT 项变更"
        [ "$_SL_WARN" -gt 0 ] && msg="$msg, $_SL_WARN 项警告"
        if [ "$_SL_WARN" -gt 0 ]; then warn "$msg"; else ok "$msg"; fi
    fi
    _SL_READY=(); _SL_ACT=0; _SL_WARN=0
}

setup_link() {
    # 测试单独 eval 本函数体（不带顶层初始化）→ 自带兜底，set -u 下不炸
    [[ -v _SL_READY ]] || _SL_READY=()
    [[ -v _SL_ACT ]] || _SL_ACT=0
    [[ -v _SL_WARN ]] || _SL_WARN=0
    local link="$1"
    local target="$2"
    local name="$3"

    run mkdir -p "$(dirname "$link")"
    # 「先删后弃」防护（2026-10-30 事故，与 templates/ccprivate-setup.sh 同源缺陷）：
    # 目标缺失时不得动【健康】链接。旧顺序是先 rm 掉健康链接、才 warn "目标不存在，
    # 跳过"，残缺副本跑一次就把 ~/CLAUDE.md 这类全局链接凭空删掉（不是变死链，是没了）。
    # 只保护【健康】链接：目标缺失且链接本就断了，仍要按下面分支清理，否则死链留着
    # 下次又被 readlink -f 判成"已链接"，回到老 bug。
    if [[ ! -e "$target" ]] && [[ -e "$link" ]]; then
        _SL_WARN=$((_SL_WARN+1)); warn "$name: 目标不存在，跳过（保留现有健康链接，$target）"
        return 0
    fi
    # 死链必须 [ -e ] 才排除：readlink -f 对死链返回规范路径字符串（非空），
    # 只比字符串会把死链判成"已链接" → 永远不修
    if [[ -L "$link" ]] && [[ -e "$link" ]]; then
        local existing=$(readlink -f "$link" 2>/dev/null || true)
        local expected=$(readlink -f "$target" 2>/dev/null || true)
        if [[ -n "$existing" && "$existing" = "$expected" ]]; then
            _SL_READY+=("$name"); return 0
        fi
        run rm -f "$link"
    elif [[ -L "$link" ]]; then
        _SL_WARN=$((_SL_WARN+1)); warn "$name: 死链（目标不存在），重建"
        run rm -f "$link"
    elif [[ -e "$link" ]]; then
        run rm -f "$link"
    fi
    # 目标不存在时不建链：建出的死链会让问题更隐蔽（下次还被判"已链接"）
    if [[ ! -e "$target" ]]; then
        _SL_WARN=$((_SL_WARN+1)); warn "$name: 目标不存在，跳过（$target）"
        return 0
    fi
    run ln -sf "$target" "$link"
    _SL_ACT=$((_SL_ACT+1)); ok "$name: 已链接"
}

setup_symlinks() {
    echo -e "\n${LIGHT_BLUE}符号链接${NC}"

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

    # git pre-commit hook（防私密文件/密钥意外提交到【公开】仓库）
    # ccconfig 与 skill 都是公开仓 → 两个都要装。ccprivate 是私密仓（本来就存 key），
    # 不装，避免自拦截。
    local hook_src="$CCCONFIG_ROOT/hooks/pre-commit"
    if [[ -f "$hook_src" ]]; then
        local _repo
        for _repo in "$CCCONFIG_ROOT" "${SKILL_SRC:-$HOME/git/skill}"; do
            [ -d "$_repo/.git" ] || continue
            local git_hook="$_repo/.git/hooks/pre-commit"
            if [[ -L "$git_hook" ]] && [[ -e "$git_hook" ]] && \
               [[ "$(readlink -f "$git_hook")" == "$(readlink -f "$hook_src")" ]]; then
                _SL_READY+=("pre-commit hook ($(basename "$_repo"))")
            else
                [[ -e "$git_hook" ]] && run rm -f "$git_hook"
                run ln -sf "$hook_src" "$git_hook"
                _SL_ACT=$((_SL_ACT+1)); ok "pre-commit hook ($(basename "$_repo")): 已安装"
            fi
        done
        unset _repo
    fi
    _sl_flush "符号链接"
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

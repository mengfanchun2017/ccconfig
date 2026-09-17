#!/bin/bash
# ccprivate — 私有配置注入脚本
#
# ⚠️ 本文件是 ccprivate/setup.sh 的【唯一真相源】。
#    init-bootstrap.sh（新机引导）和 lib/ccprivate-upgrade.sh（老机升级）
#    都从这里 cp，不再各自内嵌副本 —— 三份副本漂移曾导致
#    "setup.sh 建本机文件、upgrade 建 symlink" 互相打架。
#
# 职责（v3）：
#   1. 用户级文件：共享的 symlink → ccprivate；本机的从 .example cp 一次
#   2. 触发 ccconfig 公开部分链接（agents/rules/commands/skills）
#   (ccconfig 脚本通过 resolve_conf() 直接读 ccprivate/conf/，无需中间目录)
#
# 分层（详见 ADR-0032）：
#   共享同步   link/CLAUDE.md、rules/、memory/
#   本机独立   ~/.claude/settings.json（LLM 选择）、.config.json（会话配置）、
#              .claudeignore（context 策略）—— symlink 会跨机覆盖，必须本机维护
#
# 用法：
#   bash ~/git/ccprivate/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="${CCCONFIG_DIR:-$HOME/git/ccconfig}"
CLAUDE_DIR="$HOME/.claude"

# 从 ccconfig 借 colors.sh；缺失时用本地 ANSI 兜底
source "$CCCONFIG_DIR/lib/colors.sh" 2>/dev/null || {
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    YELLOW='\033[0;33m'
    NC='\033[0m'

    section() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
    info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
    ok()      { echo -e "${GREEN}✅ $1${NC}"; }
    warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
}

setup_link() {
    local link="$1"
    local target="$2"
    local label="$3"
    mkdir -p "$(dirname "$link")"
    if [ -L "$link" ]; then
        local existing expected
        existing=$(readlink -f "$link" 2>/dev/null || true)
        expected=$(readlink -f "$target" 2>/dev/null || true)
        if [ "$existing" = "$expected" ] && [ -n "$existing" ]; then
            info "$label: 已链接"
            return 0
        fi
        rm -f "$link"
    elif [ -e "$link" ]; then
        rm -rf "$link"
    fi
    ln -s "$target" "$link"
    ok "$label"
}

# ============================================================
# 1. 用户级 ~/ 链接（直连 ccprivate/link/）
# ============================================================
section "用户级链接"
setup_link "$HOME/CLAUDE.md"           "$SCRIPT_DIR/link/CLAUDE.md"     "~/CLAUDE.md"
setup_link "$HOME/.lark-default-account" "$SCRIPT_DIR/link/.lark-default-account" ".lark-default-account → ccprivate"
setup_link "$CLAUDE_DIR/commands/should-compact.md" "$CCCONFIG_DIR/commands/should-compact.md" "~/.claude/commands/should-compact.md"

# 以下三文件是本机状态（LLM 选择 / 会话配置 / context 策略），symlink 会跨机覆盖
# 首次 setup 时从 .example 模板 cp；已存在则跳过，各机独立维护，永不回写 ccprivate
install_user_file() {
    local dst="$1" src_template="$2" desc="$3"
    mkdir -p "$(dirname "$dst")"
    if [ ! -f "$src_template" ]; then
        warn "$desc: 模板缺失 $src_template，跳过"
    elif [ -L "$dst" ]; then
        rm -f "$dst"
        cp "$src_template" "$dst"
        ok "$desc: symlink 转本机文件"
    elif [ ! -f "$dst" ]; then
        cp "$src_template" "$dst"
        ok "$desc: 已从模板创建"
    else
        info "$desc: 已存在，跳过"
    fi
}

install_user_file "$CLAUDE_DIR/.config.json"  "$SCRIPT_DIR/link/.config.json.example"  ".config.json"
install_user_file "$CLAUDE_DIR/.claudeignore" "$SCRIPT_DIR/link/.claudeignore.example" ".claudeignore"
install_user_file "$CLAUDE_DIR/settings.json" "$SCRIPT_DIR/link/settings.json.example" "settings.json"

# ============================================================
# 2. ccprivate 私有配置 — 由 resolve_conf() 直接读 ccprivate/conf/
#    无需中间目录。ccconfig/ 零 symlink。
# ============================================================
info "ccconfig 私有配置: ccconfig 脚本通过 resolve_conf() 直接读 ccprivate/conf/"

# 私有 skill 实体目录（不开源，跨机器同步）
mkdir -p "$SCRIPT_DIR/skill-local"
[ -f "$SCRIPT_DIR/skill-local/.gitkeep" ] || touch "$SCRIPT_DIR/skill-local/.gitkeep"
info "私有 skill 目录: $SCRIPT_DIR/skill-local/（用户自建 skill 存放处）"

# ============================================================
# 3. 用户级 memory symlink（动态计算 project ID，不硬编码用户名）
# ============================================================
section "用户级记忆"
_cconfig_id="$(echo "$HOME/git/ccconfig" | tr '/' '-')"
setup_link "$CLAUDE_DIR/projects/$_cconfig_id/memory" "$SCRIPT_DIR/link/memory" "memory → ccprivate/link/memory"
unset _cconfig_id

# ============================================================
# 4. 运行时链接（rules/agents/commands → ccprivate，用户可自定义）
# ============================================================
section "运行时链接"
if [ -d "$SCRIPT_DIR/rules" ]; then
    setup_link "$CLAUDE_DIR/rules" "$SCRIPT_DIR/rules" "rules → ccprivate/rules"
fi
if [ -d "$SCRIPT_DIR/agents" ]; then
    setup_link "$CLAUDE_DIR/agents" "$SCRIPT_DIR/agents" "agents → ccprivate/agents"
fi
if [ -d "$SCRIPT_DIR/commands" ]; then
    setup_link "$CLAUDE_DIR/commands" "$SCRIPT_DIR/commands" "commands → ccprivate/commands"
fi
# ~/.claude/workflows 是真实目录，每个 workflow .js 单独 symlink → ccprivate
# Claude 拒绝通过 symlink 目录保存新 workflow，且不递归扫描子目录
if [ -d "$SCRIPT_DIR/workflows" ]; then
    if [ -L "$CLAUDE_DIR/workflows" ]; then
        rm -f "$CLAUDE_DIR/workflows"
    fi
    mkdir -p "$CLAUDE_DIR/workflows"
    for _wf_dir in "$SCRIPT_DIR/workflows/"*/; do
        [ -d "$_wf_dir" ] || continue
        _wf_name=$(basename "$_wf_dir")
        _wf_dir="${_wf_dir%/}"
        _wf_js="$_wf_dir/workflow.js"
        if [ -f "$_wf_js" ]; then
            # workflow.js 用 HERE=$HOME/.claude/workflows/<name> 读同目录下的
            # paths.sh / translate-config*.sh，故目录 symlink 也必须建，缺了运行时报错
            setup_link "$CLAUDE_DIR/workflows/${_wf_name}" "$_wf_dir" "workflows/${_wf_name} → ccprivate"
            setup_link "$CLAUDE_DIR/workflows/${_wf_name}.js" "$_wf_js" "workflows/${_wf_name}.js → ccprivate"
        fi
    done
    unset _wf_dir _wf_name _wf_js
fi

# ============================================================
# 5. ccconfig 公开部分（shell_init.sh + pre-commit hook）
# ============================================================
section "ccconfig 公开链接"
if [ -x "$CCCONFIG_DIR/lib/setup-links.sh" ]; then
    bash "$CCCONFIG_DIR/lib/setup-links.sh"
else
    warn "ccconfig/lib/setup-links.sh 不存在，跳过（请确认 ccconfig 已 clone）"
fi

# 注册私有 skill 到 ~/.claude/skills/
if [ -x "$CCCONFIG_DIR/lib/init-skill.sh" ] && [ -d "$SCRIPT_DIR/skill-local" ] && ls "$SCRIPT_DIR/skill-local"/*/ &>/dev/null; then
    info "私有 skill → ~/.claude/skills/"
    bash "$CCCONFIG_DIR/lib/init-skill.sh" link-only
fi

echo ""
ok "ccprivate setup 完成"

#!/bin/bash
# ccconfig/option-cloudflare/init.sh — Cloudflare Claude Code 插件（可选组件）
#
# 通过 Claude Code 插件系统安装 cloudflare@cloudflare，
# 含 11 skills + 2 commands + 5 HTTP MCP 服务器。
# 适用场景：Workers/R2/D1/Pages 等 CF 小项目开发。
#
# 用法：
#   bash ccconfig/option-cloudflare/init.sh              # 交互式
#   bash ccconfig/option-cloudflare/init.sh --install    # 安装 marketplace + plugin
#   bash ccconfig/option-cloudflare/init.sh --uninstall  # 卸载 plugin
#   bash ccconfig/option-cloudflare/init.sh --status     # 状态检查
#   bash ccconfig/option-cloudflare/init.sh --update     # git pull marketplace 更新

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad()  { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
info() { echo -e "${GRAY}$1${NC}"; }

MARKETPLACE_REPO="cloudflare/skills"
PLUGIN_NAME="cloudflare@cloudflare"
PLUGIN_DIR="$HOME/.claude/plugins/cache/cloudflare/cloudflare"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/cloudflare"

banner() {
    echo -e "${CYAN}"
    echo "Cloudflare Plugin — Workers/Pages/D1/R2/AI"
    echo "═════════════════════════════════════════"
    echo "    11 skills + 2 commands + 5 MCP 服务器"
    echo "$NC"
}

# ========== 状态检查 ==========
check_installed() {
    # marketplace 已添加
    local mp_ok=false
    if claude plugin marketplace list 2>/dev/null | grep -q "cloudflare"; then
        mp_ok=true
    fi

    # plugin 已安装（检查 installed_plugins.json）
    local pl_ok=false
    if python3 -c "
import json
try:
    with open('$HOME/.claude/plugins/installed_plugins.json') as f:
        d = json.load(f)
    print('true' if 'cloudflare@cloudflare' in d.get('plugins', {}) else 'false')
except:
    print('false')
" 2>/dev/null | grep -q true; then
        pl_ok=true
    fi

    # 版本
    local ver=""
    if [ -d "$PLUGIN_DIR" ]; then
        ver=$(ls "$PLUGIN_DIR" 2>/dev/null | head -1)
    fi

    echo "$mp_ok|$pl_ok|$ver"
}

do_status() {
    banner
    local status
    status=$(check_installed)
    local mp_ok=$(echo "$status" | cut -d'|' -f1)
    local pl_ok=$(echo "$status" | cut -d'|' -f2)
    local ver=$(echo "$status" | cut -d'|' -f3)

    echo -e "  Marketplace (cloudflare/skills):  $([ "$mp_ok" = true ] && echo "${GREEN}✓${NC} 已添加" || echo "${RED}✗${NC} 未添加")"
    echo -e "  Plugin (cloudflare@cloudflare):   $([ "$pl_ok" = true ] && echo "${GREEN}✓${NC} 已安装 v$ver" || echo "${RED}✗${NC} 未安装")"
    echo ""

    if [ "$pl_ok" = true ]; then
        echo -e "${CYAN}── MCP 服务器状态 ──${NC}"
        claude mcp list 2>/dev/null | grep "plugin:cloudflare" | while read line; do
            local name=$(echo "$line" | awk '{print $1}')
            local status_mark=$(echo "$line" | grep -q "Connected" && echo "${GREEN}✓${NC}" || echo "${YELLOW}○${NC}")
            echo "  $status_mark $name"
        done
        echo ""
        echo -e "${GRAY}  4/5 需 OAuth（首次调用自动触发），详见 docs/cloudflare-plugin.md${NC}"
    fi
}

# ========== 安装 ==========
do_install() {
    banner
    local status
    status=$(check_installed)
    local mp_ok=$(echo "$status" | cut -d'|' -f1)
    local pl_ok=$(echo "$status" | cut -d'|' -f2)

    if [ "$pl_ok" = true ]; then
        good "  已安装，跳过"
        echo ""
        info "  如需重装：先 --uninstall 再 --install"
        info "  更新：--update"
        return 0
    fi

    if [ "$mp_ok" != true ]; then
        echo -e "${CYAN}── 添加 marketplace ──${NC}"
        if claude plugin marketplace add "$MARKETPLACE_REPO" 2>&1 | tail -3; then
            good "  marketplace 已添加"
        else
            bad "  marketplace 添加失败（检查网络）"
            return 1
        fi
    else
        info "  marketplace 已存在，跳过"
    fi

    echo ""
    echo -e "${CYAN}── 安装 plugin ──${NC}"
    if claude plugin install "$PLUGIN_NAME" 2>&1 | tail -3; then
        good "  plugin 已安装"
    else
        bad "  plugin 安装失败"
        return 1
    fi

    echo ""
    good "安装完成。重启 Claude Code 或 /reload-plugins 生效。"
    echo -e "${GRAY}  MCP 首次使用需 OAuth 认证（浏览器弹窗）。${NC}"
    echo -e "${GRAY}  建议从 wrangler.jsonc 所在目录启动 Claude Code。${NC}"
}

# ========== 卸载 ==========
do_uninstall() {
    banner
    local status
    status=$(check_installed)
    local pl_ok=$(echo "$status" | cut -d'|' -f2)

    if [ "$pl_ok" != true ]; then
        info "  plugin 未安装，跳过"
        return 0
    fi

    echo -e "${CYAN}── 卸载 plugin ──${NC}"
    if claude plugin uninstall "$PLUGIN_NAME" 2>&1 | tail -3; then
        good "  plugin 已卸载"
    else
        warn "  plugin 卸载失败（可能已手动删除）"
    fi

    echo ""
    info "  marketplace 保留（如需清理：手动删除 ~/.claude/plugins/ 下 cloudflare 条目）"
}

# ========== 更新 ==========
do_update() {
    banner
    local status
    status=$(check_installed)
    local mp_ok=$(echo "$status" | cut -d'|' -f1)
    local pl_ok=$(echo "$status" | cut -d'|' -f2)
    local ver=$(echo "$status" | cut -d'|' -f3)

    if [ "$pl_ok" != true ]; then
        info "  未安装，请先 --install"
        return 1
    fi

    echo -e "${CYAN}── 更新 marketplace (git pull) ──${NC}"
    if [ -d "$MARKETPLACE_DIR" ]; then
        local before
        before=$(git -C "$MARKETPLACE_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
        if git -C "$MARKETPLACE_DIR" pull --ff-only 2>&1 | tail -3; then
            local after
            after=$(git -C "$MARKETPLACE_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
            if [ "$before" != "$after" ]; then
                good "  marketplace: $before → $after"
            else
                good "  marketplace 已是最新"
            fi
        else
            warn "  git pull 失败（可能有本地修改）"
        fi
    else
        warn "  marketplace 目录不存在，请重装"
    fi

    echo ""
    echo -e "${CYAN}── 重装 plugin（取最新版本）──${NC}"
    if claude plugin uninstall "$PLUGIN_NAME" 2>&1 | tail -1; then
        if claude plugin install "$PLUGIN_NAME" 2>&1 | tail -3; then
            local new_ver
            new_ver=$(ls "$PLUGIN_DIR" 2>/dev/null | head -1)
            good "  plugin: v$ver → v$new_ver"
        else
            bad "  plugin 重装失败"
            return 1
        fi
    else
        bad "  卸载旧版本失败"
        return 1
    fi

    echo ""
    good "更新完成。重启 Claude Code 或 /reload-plugins 生效。"
}

# ========== 交互式 ==========
do_interactive() {
    do_status
    echo ""
    echo "  操作:"
    echo "    i) 安装"
    echo "    u) 卸载"
    echo "    p) 更新"
    echo "    q) 退出"
    echo ""
    read -p "选择 [i/u/p/q]: " choice
    case "$choice" in
        i) echo ""; do_install ;;
        u) echo ""; do_uninstall ;;
        p) echo ""; do_update ;;
        q) exit 0 ;;
        *) warn "无效选择" ;;
    esac
}

case "${1:-}" in
    --install)   do_install ;;
    --uninstall) do_uninstall ;;
    --status)    do_status ;;
    --update)    do_update ;;
    "")          do_interactive ;;
    *)
        echo "用法: $0 [--install|--uninstall|--status|--update]"
        exit 1
        ;;
esac

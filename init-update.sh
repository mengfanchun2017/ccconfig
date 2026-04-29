#!/bin/bash
# ==============================================
# 组件升级脚本 - 一键升级所有相关组件
#
# 升级组件：
#   Claude Code   - claude install (原生二进制升级)
#   Node.js       - 检查新 LTS 版本
#   lark-cli      - npm update @larksuite/cli
#   cc-connect    - 下载最新 GitHub Release
#   MCP 服务器    - 刷新 npx 缓存 + 重新注册
#   Skills        - 从 GitHub 拉取最新（需网络）
#   GitHub CLI    - 检查新版本
#
# 使用：
#   bash ccconfig/init-update.sh              # 交互式选择
#   bash ccconfig/init-update.sh all          # 一键升级全部
#   bash ccconfig/init-update.sh claude       # 仅升级 Claude
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
NODE_VERSION="20.11.0"      # 当前使用的版本，升级时改为 latest

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ========== 1. Claude Code ==========
update_claude() {
    section "Claude Code"
    export PATH="$LOCAL_BIN:$PATH"

    if ! command -v claude &>/dev/null; then
        error "Claude Code 未安装"
        return 1
    fi

    local before=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
    info "当前版本: $before"

    info "正在升级..."
    if claude install 2>&1 | tail -3; then
        local after=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        if [[ "$before" != "$after" ]]; then
            success "Claude Code: $before → $after"
        else
            success "Claude Code 已是最新: $after"
        fi
    else
        warn "升级失败，保留当前版本"
        return 1
    fi
}

# ========== 2. Node.js ==========
update_nodejs() {
    section "Node.js"
    export PATH="$LOCAL_BIN:$PATH"

    local current=$(node --version 2>/dev/null | tr -d 'v' || echo "0")
    info "当前版本: v$current"

    # 获取最新 LTS 版本号（从 nodejs.org）
    local latest=$(curl -s https://nodejs.org/dist/index.json | python3 -c "
import json,sys
data=json.load(sys.stdin)
for v in data:
    if v.get('lts'):
        print(v['version'].lstrip('v'))
        break
" 2>/dev/null || echo "")

    if [[ -z "$latest" ]]; then
        warn "无法获取最新版本"
        return 1
    fi

    if [[ "$current" == "$latest" ]]; then
        success "Node.js 已是最新 LTS: v$latest"
        return 0
    fi

    info "最新 LTS: v$latest, 正在安装..."
    local url="https://nodejs.org/dist/v${latest}/node-v${latest}-linux-x64.tar.gz"
    if curl -fsSL "$url" -o /tmp/node-update.tar.gz; then
        tar -xzf /tmp/node-update.tar.gz -C "$HOME/.local/"
        mkdir -p "$LOCAL_BIN"
        ln -sf "$HOME/.local/node-v${latest}-linux-x64/bin/node" "$LOCAL_BIN/node"
        ln -sf "$HOME/.local/node-v${latest}-linux-x64/bin/npm" "$LOCAL_BIN/npm"
        ln -sf "$HOME/.local/node-v${latest}-linux-x64/bin/npx" "$LOCAL_BIN/npx"
        rm -f /tmp/node-update.tar.gz
        success "Node.js: v$current → v$latest"
    else
        error "下载失败"
        return 1
    fi
}

# ========== 3. lark-cli ==========
update_larkcli() {
    section "lark-cli"
    export PATH="${HOME}/.local/node-v${NODE_VERSION}-linux-x64/bin:$LOCAL_BIN:$PATH"

    if ! command -v lark-cli &>/dev/null; then
        warn "lark-cli 未安装，跳过"
        return 0
    fi

    info "更新 @larksuite/cli..."
    if npm update -g @larksuite/cli 2>&1 | tail -3; then
        success "lark-cli 已更新"
    else
        npm install -g @larksuite/cli@latest 2>&1 | tail -3 && success "lark-cli 已重装" || warn "更新失败"
    fi
}

# ========== 4. cc-connect ==========
update_cconnect() {
    section "cc-connect"
    CC_CONNECT_BIN="$LOCAL_BIN/cc-connect"

    if [[ ! -x "$CC_CONNECT_BIN" ]]; then
        info "cc-connect 未安装，跳过"
        return 0
    fi

    local current=$("$CC_CONNECT_BIN" --version 2>/dev/null | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || echo "?")
    info "当前版本: $current"

    # 获取最新 release
    local latest=$(curl -s https://api.github.com/repos/chenhg5/cc-connect/releases/latest | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "")

    if [[ -z "$latest" ]]; then
        warn "无法获取最新版本"
        return 1
    fi

    if [[ "$current" == "$latest" ]]; then
        success "cc-connect 已是最新: $latest"
        return 0
    fi

    info "下载 $latest..."
    local url="https://github.com/chenhg5/cc-connect/releases/download/${latest}/cc-connect-${latest}-linux-amd64.tar.gz"
    local tmp="/tmp/cc-connect-update"
    mkdir -p "$tmp"
    if curl -fsSL "$url" -o "$tmp/cc-connect.tar.gz"; then
        tar -xzf "$tmp/cc-connect.tar.gz" -C "$tmp"
        local bin=$(find "$tmp" -name "cc-connect" -type f | head -1)
        [[ -n "$bin" ]] && cp "$bin" "$CC_CONNECT_BIN" && success "cc-connect: $current → $latest"
        rm -rf "$tmp"
    else
        error "下载失败"
        return 1
    fi
}

# ========== 5. MCP 缓存刷新 ==========
update_mcp() {
    section "MCP 缓存刷新"

    info "刷新 npx 缓存..."
    rm -rf "$HOME/.npm/_npx" 2>/dev/null || true

    local mcp_conf="$SCRIPT_DIR/conf/claude.json"
    if [[ -f "$mcp_conf" ]]; then
        python3 - "$mcp_conf" << 'PYEOF'
import json, sys, subprocess
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for s in data.get('mcp_servers', []):
        name = s.get('name', '')
        cmd = s.get('command', '')
        args = s.get('args', [])
        if cmd == 'npx' and args:
            pkg = args[0]
            if pkg != '-y':
                pkg = args[1] if len(args) > 1 else pkg
            print(f"缓存 {name} ({pkg}) ... ", end='')
            try:
                subprocess.run(['npx', '--yes', pkg, '--version'], capture_output=True, timeout=60)
                print("✅")
            except:
                print("跳过")
        elif cmd == 'uvx' and args:
            pkg = args[0]
            print(f"缓存 {name} ({pkg}) ... ", end='')
            try:
                subprocess.run(['uvx', pkg, '--version'], capture_output=True, timeout=60)
                print("✅")
            except:
                print("跳过")
except Exception as e:
    print(f"错误: {e}")
PYEOF
    fi

    success "MCP 缓存已刷新"
}

# ========== 6. Skills ==========
update_skills() {
    section "Skills"

    info "Skills 通过 Git 管理，拉取最新即可获取所有更新"
    info "运行: cd ~/git/ccconfig && git pull"

    # 用 npx skills update 更新内置 skill 索引
    if command -v npx &>/dev/null; then
        info "更新内置 skills 索引..."
        npx skills update 2>/dev/null && success "Skills 索引已更新" || warn "Skills 索引更新失败（不影响使用）"
    fi
}

# ========== 7. GitHub CLI ==========
update_gh() {
    section "GitHub CLI"
    export PATH="$LOCAL_BIN:$PATH"

    if ! command -v gh &>/dev/null; then
        info "gh 未安装，跳过"
        return 0
    fi

    local current=$(gh --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")
    info "当前版本: $current"

    local latest=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" 2>/dev/null || echo "")

    if [[ -z "$latest" ]]; then
        warn "无法获取最新版本"
        return 1
    fi

    if [[ "$current" == "$latest" ]]; then
        success "GitHub CLI 已是最新: v$latest"
        return 0
    fi

    info "下载 gh v$latest..."
    local url="https://github.com/cli/cli/releases/download/v${latest}/gh_${latest}_linux_amd64.tar.gz"
    local tmp="/tmp/gh-update"
    mkdir -p "$tmp"
    if curl -fsSL "$url" -o "$tmp/gh.tar.gz"; then
        tar -xzf "$tmp/gh.tar.gz" -C "$tmp"
        cp "$tmp/gh_${latest}_linux_amd64/bin/gh" "$LOCAL_BIN/gh"
        chmod +x "$LOCAL_BIN/gh"
        rm -rf "$tmp"
        success "GitHub CLI: $current → v$latest"
    else
        error "下载失败"
        return 1
    fi
}

# ========== 交互式菜单 ==========
show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      ccconfig 组件升级               ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) Claude Code（原生二进制）"
    echo "  2) Node.js（最新 LTS）"
    echo "  3) lark-cli（飞书 CLI）"
    echo "  4) cc-connect（Bridge）"
    echo "  5) MCP 缓存刷新"
    echo "  6) Skills 索引更新"
    echo "  7) GitHub CLI"
    echo "  8) 一键全部升级"
    echo "  0) 退出"
    echo ""
    read -p "选择 [1-8,0]: " choice

    case "$choice" in
        1) update_claude ;;
        2) update_nodejs ;;
        3) update_larkcli ;;
        4) update_cconnect ;;
        5) update_mcp ;;
        6) update_skills ;;
        7) update_gh ;;
        8) update_all ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
}

update_all() {
    update_claude
    update_nodejs
    update_larkcli
    update_cconnect
    update_mcp
    update_skills
    update_gh

    echo ""
    success "全部升级完成"
    echo ""
    info "提示：升级完 Claude Code 后建议重启终端"
}

# ========== 主程序 ==========
case "${1:-menu}" in
    all)     update_all ;;
    claude)  update_claude ;;
    node)    update_nodejs ;;
    lark)    update_larkcli ;;
    cconnect) update_cconnect ;;
    mcp)     update_mcp ;;
    skills)  update_skills ;;
    gh)      update_gh ;;
    menu|"") show_menu ;;
    *)       echo "用法: $0 [all|claude|node|lark|cconnect|mcp|skills|gh|menu]" ;;
esac

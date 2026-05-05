#!/bin/bash
# ==============================================
# ccconfig 组件升级脚本 v2
#
# 每月一键升级所有组件，可靠、幂等、可恢复。
#
# 升级组件：
#   [1] ccconfig 自更新   → git pull
#   [2] Node.js           → 最新 LTS
#   [3] npm 全局包        → lark-cli + skills 更新
#   [4] cc-connect        → GitHub Release
#   [5] GitHub CLI        → GitHub Release
#   [6] Claude Code       → claude install
#   [7] uv                → curl | sh
#   [8] MCP 缓存          → 刷新 npx/uvx 缓存
#   [9] Skills 索引       → npx skills update
#   [10] systemd 服务     → 重建 + 重启
#
# 使用：
#   bash ccconfig/init-update.sh              # 交互式菜单
#   bash ccconfig/init-update.sh all          # 一键升级全部
#   bash ccconfig/init-update.sh <component>  # 升级单个组件
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/path-helper.sh"

LOCAL_BIN="$HOME/.local/bin"
VERSION_FILE="$SCRIPT_DIR/conf/versions.json"
LOCK_FILE="/tmp/ccconfig-update.lock"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ   $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠  $1${NC}"; }
err()   { echo -e "${RED}❌ $1${NC}"; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ========== 锁 ==========

acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            err "升级已在运行中 (pid=$pid)，$LOCK_FILE"
            exit 1
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# ========== 快照 ==========

take_snapshot() {
    local label="$1"
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    local snap_file="$SCRIPT_DIR/conf/versions.json.${label}.${ts}"

    # 记录 live versions
    python3 - "$snap_file" "$VERSION_FILE" << 'PYEOF'
import json, sys, subprocess, os

snap_file = sys.argv[1]
version_file = sys.argv[2]

def get_ver(cmd):
    try:
        out = subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, timeout=30).decode().strip()
        if out:
            return out.split('\n')[0].strip()
    except:
        pass
    return ''

snapshot = {
    'snapshot_time': __import__('datetime').datetime.now().astimezone().isoformat(),
    'components': {
        'node':      {'version': get_ver('node --version')},
        'npm':       {'version': get_ver('npm --version')},
        'gh':        {'version': get_ver('gh --version')},
        'claude':    {'version': get_ver('claude --version')},
        'uv':        {'version': get_ver('uv --version')},
        'lark_cli':  {'version': get_ver('lark-cli version')},
        'cc_connect':{'version': get_ver('cc-connect --version 2>/dev/null || echo not_installed')},
    }
}

# Also include versions.json
try:
    with open(version_file) as f:
        pinned = json.load(f)
    snapshot['pinned_versions'] = pinned.get('components', {})
except:
    pass

with open(snap_file, 'w') as f:
    json.dump(snapshot, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(snap_file)
PYEOF
}

# 清理过期快照（保留 3 个月）
cleanup_old_snapshots() {
    find "$SCRIPT_DIR/conf" -name "versions.json.*" -mtime +90 -delete 2>/dev/null || true
}

# ========== 1. ccconfig 自更新 ==========

self_update() {
    section "ccconfig 自更新"

    cd "$SCRIPT_DIR"

    # 检查是否有未提交的本地改动
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        warn "本地有未提交改动，跳过自更新"
        return 0
    fi

    local before=$(git rev-parse --short HEAD 2>/dev/null || echo "?")

    info "git pull..."
    git fetch origin main 2>/dev/null || { warn "无法连接远程，跳过自更新"; return 0; }

    local remote=$(git rev-parse --short origin/main 2>/dev/null)
    local local_commit=$(git rev-parse --short HEAD 2>/dev/null)

    if [ "$local_commit" = "$remote" ]; then
        success "ccconfig 已是最新: $local_commit"
        return 0
    fi

    # 检查 init-update.sh 是否会被更新
    local update_files
    update_files=$(git diff --name-only "HEAD..origin/main" 2>/dev/null || echo "")

    if git pull --ff-only origin main 2>&1 | tail -2; then
        local after=$(git rev-parse --short HEAD)
        success "ccconfig: $before → $after"

        # 如果 init-update.sh 或 path-helper.sh 被更新，重新加载自身
        if echo "$update_files" | grep -qE "init-update.sh|lib/path-helper.sh|conf/versions.json"; then
            warn "关键文件已更新，重新加载..."
            exec bash "$SCRIPT_DIR/init-update.sh" "${1:-menu}"
            # exec 不返回
        fi
    else
        warn "git pull 失败（可能有冲突），保留当前版本"
        return 1
    fi
}

# ========== 2. Node.js ==========

update_nodejs() {
    section "Node.js"

    local current
    current=$(node --version 2>/dev/null | tr -d 'v' || echo "0")
    info "当前版本: v$current"

    # 获取最新 LTS
    local latest
    latest=$(curl -s https://nodejs.org/dist/index.json | python3 -c "
import json,sys
data=json.load(sys.stdin)
for v in data:
    if v.get('lts'):
        print(v['version'].lstrip('v'))
        break
" 2>/dev/null || echo "")

    if [ -z "$latest" ]; then
        warn "无法获取最新 Node.js 版本"
        return 1
    fi

    if [ "$current" = "$latest" ]; then
        success "Node.js 已是最新 LTS: v$latest"
        return 0
    fi

    info "最新 LTS: v$latest, 正在升级..."

    local url="https://nodejs.org/dist/v${latest}/node-v${latest}-linux-x64.tar.gz"
    if ! curl -fsSL "$url" -o /tmp/node-update.tar.gz; then
        err "下载失败: $url"
        return 1
    fi

    local old_node_dir
    old_node_dir=$(dirname "$(dirname "$(find_node_bin)")")

    tar -xzf /tmp/node-update.tar.gz -C "$HOME/.local/"
    rm -f /tmp/node-update.tar.gz

    local new_node_dir="$HOME/.local/node-v${latest}-linux-x64"
    if [ ! -d "$new_node_dir" ]; then
        err "解压失败，未找到 $new_node_dir"
        return 1
    fi

    # 重建符号链接
    recreate_node_symlinks "$new_node_dir/bin"

    # 更新版本文件
    save_version "node" "$latest"

    # 清理旧 Node
    if [ -n "$old_node_dir" ] && [ -d "$old_node_dir" ] && [ "$old_node_dir" != "$new_node_dir" ]; then
        info "清理旧 Node: $old_node_dir"
        rm -rf "$old_node_dir" 2>/dev/null || warn "无法完全删除旧 Node 目录（可能在使用）"
    fi

    success "Node.js: v$current → v$latest"
}

# ========== 3. npm 全局包 ==========

update_npm_globals() {
    section "npm 全局包"

    local node_bin
    node_bin=$(find_node_bin)
    export PATH="$node_bin:$LOCAL_BIN:$PATH"

    local updated=0

    # lark-cli
    if command -v lark-cli &>/dev/null; then
        local before
        before=$(lark-cli version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        info "lark-cli 当前: $before"

        if npm update -g @larksuite/cli 2>&1 | tail -3; then
            local after
            after=$(lark-cli version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
            if [ "$before" != "$after" ]; then
                success "lark-cli: $before → $after"
                ((updated++))
            else
                success "lark-cli 已是最新: $after"
            fi
        else
            # 尝试重装
            if npm install -g @larksuite/cli@latest 2>&1 | tail -3; then
                success "lark-cli 已重装"
                ((updated++))
            else
                warn "lark-cli 更新失败"
            fi
        fi

        # 重建 lark-cli 符号链接
        rebuild_larkcli_symlink
    else
        info "lark-cli 未安装，跳过"
    fi

    echo ""
    if [ $updated -gt 0 ]; then
        success "npm 全局包更新完成"
    else
        info "npm 全局包无需更新"
    fi
}

rebuild_larkcli_symlink() {
    local npm_root
    npm_root=$(npm root -g 2>/dev/null || echo "")
    if [ -z "$npm_root" ]; then
        return
    fi

    local lark_src
    for candidate in \
        "$npm_root/@larksuite/cli/bin/lark-cli.js" \
        "$npm_root/@larksuite/cli/bin/cli.js" \
        "$npm_root/@larksuite/cli/scripts/run.js"; do
        if [ -f "$candidate" ]; then
            lark_src="$candidate"
            break
        fi
    done

    if [ -n "$lark_src" ]; then
        rm -f "$LOCAL_BIN/lark-cli"
        ln -sf "$lark_src" "$LOCAL_BIN/lark-cli"
        info "lark-cli 符号链接已更新"
    fi
}

# ========== 4. cc-connect ==========

update_cconnect() {
    section "cc-connect"

    local bin="$LOCAL_BIN/cc-connect"

    # 检查是否安装
    if [ ! -x "$bin" ]; then
        info "cc-connect 未安装，跳过"
        info "如需安装: bash ccconfig/feishu/init-cconnect.sh"
        return 0
    fi

    local current
    current=$("$bin" --version 2>/dev/null | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || echo "?")
    info "当前版本: $current"

    # 获取最新 release
    local latest
    latest=$(curl -s https://api.github.com/repos/chenhg5/cc-connect/releases/latest | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "")

    if [ -z "$latest" ]; then
        warn "无法获取最新 cc-connect 版本"
        return 1
    fi

    if [ "$current" = "$latest" ]; then
        success "cc-connect 已是最新: $latest"
        return 0
    fi

    info "下载 $latest..."
    local url="https://github.com/chenhg5/cc-connect/releases/download/${latest}/cc-connect-${latest}-linux-amd64.tar.gz"
    local tmp="/tmp/cc-connect-update.$$"
    mkdir -p "$tmp"

    if ! curl -fsSL "$url" -o "$tmp/cc-connect.tar.gz"; then
        err "下载失败: $url"
        rm -rf "$tmp"
        return 1
    fi

    tar -xzf "$tmp/cc-connect.tar.gz" -C "$tmp"
    local new_bin
    new_bin=$(find "$tmp" -name "cc-connect" -type f | head -1)

    if [ -n "$new_bin" ]; then
        cp "$new_bin" "$bin"
        chmod +x "$bin"
        save_version "cc_connect" "${latest#v}"
        success "cc-connect: $current → $latest"
    else
        err "未在压缩包中找到 cc-connect 二进制"
        rm -rf "$tmp"
        return 1
    fi

    rm -rf "$tmp"
}

# ========== 5. GitHub CLI ==========

update_gh() {
    section "GitHub CLI"

    if ! command -v gh &>/dev/null; then
        info "gh 未安装，跳过"
        return 0
    fi

    local current
    current=$(gh --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?")
    info "当前版本: $current"

    local latest
    latest=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" 2>/dev/null || echo "")

    if [ -z "$latest" ]; then
        warn "无法获取最新 GitHub CLI 版本"
        return 1
    fi

    if [ "$current" = "$latest" ]; then
        success "GitHub CLI 已是最新: v$latest"
        return 0
    fi

    info "下载 gh v$latest..."
    local url="https://github.com/cli/cli/releases/download/v${latest}/gh_${latest}_linux_amd64.tar.gz"
    local tmp="/tmp/gh-update.$$"
    mkdir -p "$tmp"

    if ! curl -fsSL "$url" -o "$tmp/gh.tar.gz"; then
        err "下载失败: $url"
        rm -rf "$tmp"
        return 1
    fi

    tar -xzf "$tmp/gh.tar.gz" -C "$tmp"
    cp "$tmp/gh_${latest}_linux_amd64/bin/gh" "$LOCAL_BIN/gh"
    chmod +x "$LOCAL_BIN/gh"
    rm -rf "$tmp"
    save_version "gh" "$latest"
    success "GitHub CLI: $current → v$latest"
}

# ========== 6. Claude Code ==========

update_claude() {
    section "Claude Code"

    local clean_path
    clean_path=$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':' | sed 's/:$//')
    export PATH="$LOCAL_BIN:$clean_path"

    if ! command -v claude &>/dev/null; then
        warn "Claude Code 未安装，跳过"
        return 0
    fi

    local before
    before=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
    info "当前版本: $before"

    info "正在升级..."
    if claude install 2>&1 | tail -5; then
        local after
        after=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        if [ "$before" != "$after" ]; then
            success "Claude Code: $before → $after"
        else
            success "Claude Code 已是最新: $after"
        fi
    else
        warn "Claude Code 升级失败，保留当前版本"
        return 1
    fi
}

# ========== 7. uv ==========

update_uv() {
    section "uv"

    if command -v uv &>/dev/null; then
        local before
        before=$(uv --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        info "当前版本: $before"
    else
        info "uv 未安装，正在安装..."
    fi

    if curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1 | tail -3; then
        local after
        after=$(uv --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        if command -v uv &>/dev/null; then
            success "uv 已更新: $after"
        else
            warn "uv 更新失败"
            return 1
        fi
    else
        warn "uv 更新失败（不影响使用）"
        return 1
    fi
}

# ========== 8. MCP 缓存刷新 ==========

update_mcp() {
    section "MCP 缓存刷新"

    info "清除 npx 缓存..."
    rm -rf "$HOME/.npm/_npx" 2>/dev/null || true

    # 预拉取 MCP 包
    local mcp_conf="$SCRIPT_DIR/conf/claude.json"
    if [ -f "$mcp_conf" ]; then
        python3 - "$mcp_conf" << 'PYEOF'
import json, sys, subprocess

with open(sys.argv[1]) as f:
    data = json.load(f)

for s in data.get('mcp_servers', []):
    name = s.get('name', '')
    cmd = s.get('command', '')
    args = s.get('args', [])

    if cmd == 'npx' and args:
        pkg = args[1] if args[0] == '-y' and len(args) > 1 else args[0]
        print(f"拉取 {name} ({pkg}) ... ", end='', flush=True)
        try:
            subprocess.run(['npx', '--yes', pkg, '--version'], capture_output=True, timeout=60)
            print("OK")
        except Exception:
            print("跳过")
    elif cmd == 'uvx' and args:
        pkg = args[0]
        print(f"拉取 {name} ({pkg}) ... ", end='', flush=True)
        try:
            subprocess.run(['uvx', pkg, '--version'], capture_output=True, timeout=60)
            print("OK")
        except Exception:
            print("跳过")
PYEOF
    fi

    success "MCP 缓存已刷新"
}

# ========== 9. Skills 索引 ==========

update_skills() {
    section "Skills"

    info "Skills 由 ccconfig 自更新管理（git pull）"

    if command -v npx &>/dev/null; then
        info "更新内置 skills 索引..."
        if npx skills update 2>/dev/null; then
            success "Skills 索引已更新"
        else
            warn "Skills 索引更新失败（不影响使用）"
        fi
    fi
}

# ========== 10. systemd 服务重建 ==========

fix_systemd_services() {
    section "systemd 服务"

    local node_bin
    node_bin=$(find_node_bin)

    info "Node bin 路径: $node_bin"

    # 重建 cc-connect service
    local service_file="$HOME/.config/systemd/user/cc-connect.service"
    if [ -f "$service_file" ]; then
        # 更新 PATH
        sed -i "s|^Environment=PATH=.*|Environment=PATH=$node_bin:$LOCAL_BIN:/usr/local/bin:/usr/bin:/bin|" "$service_file" 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user restart cc-connect 2>/dev/null && success "cc-connect 服务已重启" || warn "cc-connect 服务重启失败（可能未运行）"
    else
        info "cc-connect 服务文件不存在，跳过"
    fi
}

# ========== 全部升级 ==========

update_all() {
    local overall_status=0
    local results=()

    run_step() {
        local desc="$1"
        shift
        echo ""
        if "$@"; then
            results+=("${GREEN}✅${NC} $desc")
        else
            results+=("${RED}❌${NC} $desc")
            overall_status=1
        fi
    }

    run_step "cconfig 自更新"   self_update "$@"
    run_step "Node.js"          update_nodejs
    run_step "npm 全局包"       update_npm_globals
    run_step "cc-connect"       update_cconnect
    run_step "GitHub CLI"       update_gh
    run_step "Claude Code"      update_claude
    run_step "uv"               update_uv
    run_step "MCP 缓存"         update_mcp
    run_step "Skills 索引"      update_skills
    run_step "systemd 服务"     fix_systemd_services

    # 后快照
    echo ""
    section "升级总结"
    take_snapshot "after" > /dev/null

    for r in "${results[@]}"; do
        echo -e "  $r"
    done

    cleanup_old_snapshots

    echo ""
    if [ $overall_status -eq 0 ]; then
        success "全部升级完成"
    else
        warn "部分升级失败，详见上述错误"
    fi

    echo ""
    info "提示：升级完 Claude Code 后建议新开会话以使用新版本"
}

# ========== 交互式菜单 ==========

show_menu() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      ccconfig 组件升级 v2            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "   1) ccconfig 自更新 (git pull)"
    echo "   2) Node.js（最新 LTS）"
    echo "   3) npm 全局包（lark-cli）"
    echo "   4) cc-connect（Bridge）"
    echo "   5) GitHub CLI"
    echo "   6) Claude Code"
    echo "   7) uv（Python 包管理）"
    echo "   8) MCP 缓存刷新"
    echo "   9) Skills 索引更新"
    echo "  10) systemd 服务重建"
    echo "  11) ★ 一键全部升级"
    echo "   0) 退出"
    echo ""
    read -p "选择 [1-11,0]: " choice

    case "$choice" in
        1)  self_update; show_menu ;;
        2)  update_nodejs; show_menu ;;
        3)  update_npm_globals; show_menu ;;
        4)  update_cconnect; show_menu ;;
        5)  update_gh; show_menu ;;
        6)  update_claude; show_menu ;;
        7)  update_uv; show_menu ;;
        8)  update_mcp; show_menu ;;
        9)  update_skills; show_menu ;;
        10) fix_systemd_services; show_menu ;;
        11) update_all; show_menu ;;
        0)  echo ""; exit 0 ;;
        *)  echo "无效选择"; show_menu ;;
    esac
}

# ========== 主程序 ==========
acquire_lock
trap release_lock EXIT

case "${1:-menu}" in
    all)
        echo -e "${CYAN}ccconfig 组件升级 v2 - $(date '+%Y-%m-%d')${NC}"
        take_snapshot "pre" > /dev/null
        update_all
        ;;
    self-update)   self_update "${@:2}" ;;
    node)          update_nodejs ;;
    npm)           update_npm_globals ;;
    cconnect)      update_cconnect ;;
    gh)            update_gh ;;
    claude)        update_claude ;;
    uv)            update_uv ;;
    mcp)           update_mcp ;;
    skills)        update_skills ;;
    services)      fix_systemd_services ;;
    menu|"")       show_menu ;;
    *)
        echo "用法: $0 [all|self-update|node|npm|cconnect|gh|claude|uv|mcp|skills|services|menu]"
        exit 1
        ;;
esac

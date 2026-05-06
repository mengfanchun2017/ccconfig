#!/bin/bash
# ==============================================
# ccconfig 组件升级脚本 v2
#
# 每月一键升级所有组件，可靠、幂等、可恢复。
#
# 升级组件：
#   [1] Node.js           → 最新 LTS
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
    mkdir -p "$SCRIPT_DIR/.snapshots"
    local snap_file="$SCRIPT_DIR/.snapshots/versions.json.${label}.${ts}"

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
    find "$SCRIPT_DIR/.snapshots" -name "versions.json.*" -mtime +90 -delete 2>/dev/null || true
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

    # 国内镜像（阿里云 CDN，比 nodejs.org 快 10x+）
    local MIRROR_INDEX="https://cdn.npmmirror.com/binaries/node/index.json"
    local MIRROR_DOWNLOAD="https://cdn.npmmirror.com/binaries/node"
    local FALLBACK_INDEX="https://nodejs.org/dist/index.json"
    local FALLBACK_DOWNLOAD="https://nodejs.org/dist"

    # curl 通用参数
    local CURL_OPTS="-s --connect-timeout 5 --max-time 10"

    # 读取版本锁定（pin 大版本号，如 "22"）
    local pin
    pin=$(get_node_pin)

    # 获取 index.json（优先镜像）
    local index_json
    index_json=$(curl $CURL_OPTS "$MIRROR_INDEX" 2>/dev/null)
    if [ -z "$index_json" ]; then
        info "镜像不可用，回退到 nodejs.org..."
        index_json=$(curl $CURL_OPTS "$FALLBACK_INDEX" 2>/dev/null)
    fi

    # 获取目标 LTS 版本
    local target
    if [ -n "$pin" ] && [ "$pin" != "latest" ]; then
        # 锁定大版本：取该大版本下的最新 LTS
        info "版本锁定: v${pin}.x（编辑 conf/versions.json node.pin 修改）"
        target=$(echo "$index_json" | python3 -c "
import json,sys
pin='$pin'
data=json.load(sys.stdin)
for v in data:
    vn=v['version'].lstrip('v')
    if vn.startswith(pin+'.') and v.get('lts'):
        print(vn)
        break
" 2>/dev/null || echo "")
    else
        # 默认：最新 LTS
        target=$(echo "$index_json" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for v in data:
    if v.get('lts'):
        print(v['version'].lstrip('v'))
        break
" 2>/dev/null || echo "")
    fi

    if [ -z "$target" ]; then
        warn "无法获取目标 Node.js 版本"
        return 1
    fi

    if [ "$current" = "$target" ]; then
        success "Node.js 已是最新: v$target"
        return 0
    fi

    info "目标版本: v$target, 正在下载..."

    # 下载（镜像优先，超时降级到官方源）
    local url="$MIRROR_DOWNLOAD/v${target}/node-v${target}-linux-x64.tar.gz"
    local fallback_url="$FALLBACK_DOWNLOAD/v${target}/node-v${target}-linux-x64.tar.gz"
    info "下载: $url"
    if ! curl -fsSL --connect-timeout 10 --max-time 120 --retry 2 "$url" -o /tmp/node-update.tar.gz 2>&1; then
        info "镜像下载失败，尝试 nodejs.org..."
        if ! curl -fsSL --connect-timeout 10 --max-time 300 --retry 2 "$fallback_url" -o /tmp/node-update.tar.gz 2>&1; then
            err "下载失败（镜像和官方源均不可用）"
            return 1
        fi
    fi
    # 验证下载的是有效的 tar.gz（防止 CDN 返回 HTML 错误页）
    if [ ! -s /tmp/node-update.tar.gz ] || ! file /tmp/node-update.tar.gz | grep -q "gzip compressed"; then
        err "下载的文件不是有效的 tar.gz（可能是 HTML 错误页）"
        rm -f /tmp/node-update.tar.gz
        return 1
    fi

    local old_node_dir
    old_node_dir=$(dirname "$(find_node_bin)")

    tar -xzf /tmp/node-update.tar.gz -C "$HOME/.local/"
    rm -f /tmp/node-update.tar.gz

    local new_node_dir="$HOME/.local/node-v${target}-linux-x64"
    if [ ! -d "$new_node_dir" ]; then
        err "解压失败，未找到 $new_node_dir"
        return 1
    fi

    # 重建符号链接
    recreate_node_symlinks "$new_node_dir/bin"

    # 更新版本文件（保留 pin 等字段）
    save_version "node" "$target"

    # 清理旧 Node
    if [ -n "$old_node_dir" ] && [ -d "$old_node_dir" ] && [ "$old_node_dir" != "$new_node_dir" ]; then
        info "清理旧 Node: $old_node_dir"
        rm -rf "$old_node_dir" 2>/dev/null || warn "无法完全删除旧 Node 目录（可能在使用）"
    fi

    success "Node.js: v$current → v$target"
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
        local before latest
        before=$(lark-cli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        info "lark-cli 当前: $before"

        # 先用 npm registry 检查最新版本（避免盲目更新）
        latest=$(npm view @larksuite/cli version 2>/dev/null || echo "")
        if [ -n "$latest" ] && [ "$before" = "$latest" ]; then
            success "lark-cli 已是最新: $latest"
        elif ! npm update -g @larksuite/cli 2>&1 | tail -3; then
            # update 失败，尝试重装
            if npm install -g @larksuite/cli@latest 2>&1 | tail -3; then
                success "lark-cli 已重装"
                updated=$((updated + 1))
            else
                warn "lark-cli 更新失败"
            fi
        else
            local after
            after=$(lark-cli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
            if [ "$before" != "$after" ]; then
                success "lark-cli: $before → $after"
                updated=$((updated + 1))
            else
                success "lark-cli 已是最新: $after"
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
        info "如需安装: bash ccconfig/cconnect/init-cconnect.sh"
        return 0
    fi

    local current
    current=$("$bin" --version 2>/dev/null | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || echo "?")
    info "当前版本: $current"

    # 获取最新 release
    local latest
    latest=$(curl -s --connect-timeout 5 --max-time 10 https://api.github.com/repos/chenhg5/cc-connect/releases/latest 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || echo "")

    if [ -z "$latest" ]; then
        warn "无法获取最新 cc-connect 版本（可能被限流），跳过"
        return 0
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
    latest=$(curl -s --connect-timeout 5 --max-time 10 https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null || echo "")

    if [ -z "$latest" ]; then
        warn "无法获取最新 GitHub CLI 版本（可能被限流），跳过"
        return 0
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

    if ! command -v claude &>/dev/null; then
        warn "Claude Code 未安装，跳过"
        return 0
    fi

    local clean_path
    clean_path=$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | tr '\n' ':' | sed 's/:$//')
    export PATH="$LOCAL_BIN:$clean_path"

    local before
    before=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
    info "当前版本: $before"

    # 用 npm registry 检查最新版本（比 claude install 快，避免 download.claude.ai 超时）
    local latest
    info "检查最新版本..."
    latest=$(npm view @anthropic-ai/claude-code version 2>/dev/null || echo "")
    if [ -n "$latest" ] && [ "$before" = "$latest" ]; then
        success "Claude Code 已是最新: $latest"
        return 0
    fi

    info "正在升级到 ${latest:-latest}..."
    if claude install --force 2>&1 | tail -5; then
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

        # 30 天内已检查过则跳过（uv 更新不频繁）
        local uv_stamp="$HOME/.local/state/uv-update-stamp"
        if [ -f "$uv_stamp" ] && [ "$(find "$uv_stamp" -mmin -43200 2>/dev/null)" ]; then
            info "30 天内已检查过 uv 更新，跳过（删除 $uv_stamp 强制刷新）"
            return 0
        fi
    else
        info "uv 未安装，正在安装..."
    fi

    if curl -LsSf https://astral.sh/uv/install.sh | sh 2>&1 | tail -3; then
        local after
        after=$(uv --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        if command -v uv &>/dev/null; then
            mkdir -p "$HOME/.local/state"
            touch "$HOME/.local/state/uv-update-stamp"
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

    # 如果最近 24 小时内已刷新过，跳过
    local stamp="$HOME/.npm/.mcp-cache-stamp"
    if [ -f "$stamp" ] && [ "$(find "$stamp" -mmin -1440 2>/dev/null)" ]; then
        info "MCP 缓存在 24 小时内已刷新，跳过（删除 $stamp 强制刷新）"
        return 0
    fi

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

    touch "$stamp"
    success "MCP 缓存已刷新"
}

# ========== 9. Skills 索引 ==========

update_skills() {
    section "Skills"

    info "Skills 由 auto-sync 自动同步，无需额外更新"
    success "Skills 无需额外更新"
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

# ========== 版本信息收集 ==========

get_live_version() {
    local comp="$1"
    case "$comp" in
        node)       node --version 2>/dev/null | tr -d 'v' || echo "?" ;;
        lark-cli)   lark-cli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?" ;;
        cconnect)   "$LOCAL_BIN/cc-connect" --version 2>/dev/null | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || echo "?" ;;
        gh)         gh --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "?" ;;
        claude)     claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?" ;;
        uv)         uv --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?" ;;
        *)          echo "?" ;;
    esac
}

# ========== 兼容性预检查 ==========

compatibility_check() {
    section "兼容性预检查"
    echo ""

    local warnings=0

    # Node.js: 检查大版本跳跃（使用镜像，回退到官方源）
    local node_current node_target
    node_current=$(get_live_version "node")
    local pin=$(get_node_pin)
    local COMPAT_MIRROR="https://cdn.npmmirror.com/binaries/node/index.json"
    local COMPAT_FALLBACK="https://nodejs.org/dist/index.json"
    local compat_index
    compat_index=$(curl -s --connect-timeout 5 --max-time 10 "$COMPAT_MIRROR" 2>/dev/null)
    if [ -z "$compat_index" ]; then
        compat_index=$(curl -s --connect-timeout 5 --max-time 10 "$COMPAT_FALLBACK" 2>/dev/null)
    fi
    if [ -n "$pin" ] && [ "$pin" != "latest" ]; then
        node_target=$(echo "$compat_index" | python3 -c "
import json,sys
pin='$pin'
data=json.load(sys.stdin)
for v in data:
    vn=v['version'].lstrip('v')
    if vn.startswith(pin+'.') and v.get('lts'):
        print(vn)
        break
" 2>/dev/null || echo "")
    else
        node_target=$(echo "$compat_index" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for v in data:
    if v.get('lts'):
        print(v['version'].lstrip('v'))
        break
" 2>/dev/null || echo "")
    fi

    if [ -n "$node_current" ] && [ -n "$node_target" ] && [ "$node_current" != "$node_target" ]; then
        local cur_major=$(echo "$node_current" | cut -d. -f1)
        local tgt_major=$(echo "$node_target" | cut -d. -f1)
        if [ "$cur_major" != "$tgt_major" ]; then
            if [ -n "$pin" ] && [ "$pin" != "latest" ]; then
                info "Node.js: v$node_current → v$node_target（锁定 v${pin}.x）"
            else
                warn "Node.js 大版本跳跃: v$node_current → v$node_target"
                warn "  如需保守升级，编辑 conf/versions.json node.pin 设为 \"$cur_major\" 或 \"$tgt_major\""
                warnings=$((warnings + 1))
            fi
        else
            info "Node.js: v$node_current → v$node_target（同大版本升级）"
        fi
    fi

    # GitHub API 调用（有速率限制，加短超时）
    # cc-connect: 检查新版本
    local cc_current cc_latest
    cc_current=$(get_live_version "cconnect")
    cc_latest=$(curl -s --connect-timeout 5 --max-time 10 https://api.github.com/repos/chenhg5/cc-connect/releases/latest 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null || echo "")
    if [ -n "$cc_current" ] && [ -n "$cc_latest" ] && [ "$cc_current" != "$cc_latest" ]; then
        info "cc-connect: $cc_current → $cc_latest"
    fi

    # gh: 检查新版本
    local gh_current gh_latest
    gh_current=$(get_live_version "gh")
    gh_latest=$(curl -s --connect-timeout 5 --max-time 10 https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null || echo "")
    if [ -n "$gh_current" ] && [ -n "$gh_latest" ] && [ "$gh_current" != "$gh_latest" ]; then
        info "GitHub CLI: $gh_current → v$gh_latest"
    fi

    if [ $warnings -eq 0 ]; then
        success "兼容性检查通过"
    fi
    echo ""
}

# ========== 全部升级 ==========

update_all() {
    local overall_status=0
    local results=()

    # 收集升级前版本
    declare -A before_ver after_ver
    local components=( "node" "lark-cli" "cconnect" "gh" "claude" "uv" )
    for c in "${components[@]}"; do
        before_ver[$c]=$(get_live_version "$c")
    done

    # 预检查
    compatibility_check

    run_step() {
        local comp_key="$1"
        local desc="$2"
        shift 2
        echo ""
        if "$@"; then
            results+=("${GREEN}✅${NC} $desc")
        else
            results+=("${RED}❌${NC} $desc")
            overall_status=1
        fi
        # 只对有 comp_key 的步骤记录版本（MCP/Skills/systemd 没有版本号）
        if [ -n "$comp_key" ]; then
            after_ver[$comp_key]=$(get_live_version "$comp_key")
        fi
    }

    run_step "node"     "Node.js"           update_nodejs
    run_step "lark-cli" "npm 全局包"        update_npm_globals
    run_step "cconnect" "cc-connect"        update_cconnect
    run_step "gh"       "GitHub CLI"        update_gh
    run_step "claude"   "Claude Code"       update_claude
    run_step "uv"       "uv"                update_uv
    run_step ""         "MCP 缓存"          update_mcp
    run_step ""         "Skills 索引"       update_skills
    run_step ""         "systemd 服务"      fix_systemd_services

    # 后快照
    take_snapshot "after" > /dev/null

    # 打印总结
    echo ""
    section "升级总结"
    echo ""

    # 版本对比：只显示有变化的组件
    local changed=0
    local labels=( "node" "lark-cli" "cconnect" "gh" "claude" "uv" )
    local names=( "Node.js" "lark-cli" "cc-connect" "GitHub CLI" "Claude Code" "uv" )
    for i in "${!labels[@]}"; do
        local key="${labels[$i]}"
        local b="${before_ver[$key]:-?}"
        local a="${after_ver[$key]:-?}"
        # 跳过未安装的
        if [ "$b" = "?" ] && [ "$a" = "?" ]; then
            continue
        fi
        if [ "$b" != "$a" ] && [ "$a" != "?" ] && [ "$b" != "?" ]; then
            if [ $changed -eq 0 ]; then
                echo ""
                printf "  %-16s %-16s %-16s %s\n" "组件" "升级前" "升级后" "状态"
                printf "  %-16s %-16s %-16s %s\n" "────" "──────" "──────" "────"
            fi
            local name="${names[$i]}"
            printf "  %-16s %-16s %-16s %b\n" "$name" "v$b" "v$a" "${GREEN}↑${NC}"
            changed=$((changed + 1))
        fi
    done
    if [ $changed -eq 0 ]; then
        echo ""
        success "所有组件已是最新"
    fi

    echo ""
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
    echo "   1) Node.js（最新 LTS）"
    echo "   2) npm 全局包（lark-cli）"
    echo "   3) cc-connect（Bridge）"
    echo "   4) GitHub CLI"
    echo "   5) Claude Code"
    echo "   6) uv（Python 包管理）"
    echo "   7) MCP 缓存刷新"
    echo "   8) Skills 索引更新"
    echo "   9) systemd 服务重建"
    echo "  10) ★ 一键全部升级"
    echo "   0) 退出"
    echo ""
    read -p "选择 [1-10,0]: " choice

    case "$choice" in
        1)  update_nodejs; show_menu ;;
        2)  update_npm_globals; show_menu ;;
        3)  update_cconnect; show_menu ;;
        4)  update_gh; show_menu ;;
        5)  update_claude; show_menu ;;
        6)  update_uv; show_menu ;;
        7)  update_mcp; show_menu ;;
        8)  update_skills; show_menu ;;
        9)  fix_systemd_services; show_menu ;;
        10) update_all; show_menu ;;
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
        echo "用法: $0 [all|node|npm|cconnect|gh|claude|uv|mcp|skills|services|menu]"
        exit 1
        ;;
esac

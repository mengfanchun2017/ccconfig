#!/bin/bash
# ==============================================
# ccconfig 组件升级脚本 v2
#
# 每月一键升级所有组件，可靠、幂等、可恢复。
#
# 升级组件：
#   [1] 基础组件        → Node.js 最新 LTS + pip 包
#   [2] GitHub CLI      → GitHub Release
#   [3] Claude Code     → claude install
#   [4] uv             → curl | sh
#   [5] MCP 缓存        → 刷新 npx/uvx 缓存
#   [6] cc-connect     → GitHub Release [option]
#   [7] systemd 服务    → 重建 + 重启 [option]
#
# 使用：
#   bash ccconfig/update.sh               # 交互式菜单（支持多选，如 "1 3 4"）
#   bash ccconfig/update.sh all          # 升级基础+升级（不含 option）
#   bash ccconfig/update.sh <component>  # 升级单个组件
#   bash ccconfig/update.sh --dry-run    # 只检查不升级，输出版本差异
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/path-helper.sh"
source "$SCRIPT_DIR/lib/git-conflict.sh"

LOCAL_BIN="$HOME/.local/bin"
VERSION_FILE="$SCRIPT_DIR/conf/versions.json"
LOCK_FILE="/tmp/ccconfig-update.lock"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
DIM='\033[2m'
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

# 清理过期快照（保留 30 天）
cleanup_old_snapshots() {
    find "$SCRIPT_DIR/.snapshots" -name "versions.json.*" -mtime +30 -delete 2>/dev/null || true
}

# ========== 1. ccconfig 自更新 ==========

self_update() {
    section "ccconfig 自更新"

    info "fetching origin/main..."
    git -C "$SCRIPT_DIR" fetch origin main 2>/dev/null || { warn "无法连接远程，跳过自更新"; return 0; }

    local remote=$(git -C "$SCRIPT_DIR" rev-parse --short origin/main 2>/dev/null)
    local local_commit=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null)

    if [ "$local_commit" = "$remote" ]; then
        success "ccconfig 已是最新: $local_commit"
        return 0
    fi

    # 尝试 fast-forward
    local pull_output pull_ok=true
    set +e
    pull_output=$(git -C "$SCRIPT_DIR" pull --ff-only origin main 2>&1)
    local pull_status=$?
    set -e

    if [ $pull_status -eq 0 ]; then
        echo "$pull_output" | tail -2
        local after=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
        success "ccconfig: $local_commit → $after"

        local update_files
        update_files=$(git -C "$SCRIPT_DIR" diff --name-only "$local_commit..$after" 2>/dev/null || echo "")
        if echo "$update_files" | grep -qE "update.sh|lib/path-helper.sh|conf/versions.json"; then
            warn "关键文件已更新，重新加载..."
            exec bash "$SCRIPT_DIR/update.sh" "${1:-menu}"
        fi
        return 0
    fi

    # 拉取失败 — 冲突处理菜单 → lib/git-conflict.sh
    git_conflict_menu "$SCRIPT_DIR" "main" "$local_commit" "$remote" || return 1
}

# 从 Node.js index.json (stdin) 解析目标版本
# $1: pin (大版本号如 "22", 或 "latest" / "")
parse_node_target() {
    local pin="$1"
    python3 -c "
import json,sys
pin='$pin'
data=json.load(sys.stdin)
if pin and pin != 'latest':
    for v in data:
        vn=v['version'].lstrip('v')
        if vn.startswith(pin+'.') and v.get('lts'):
            print(vn)
            break
else:
    for v in data:
        if v.get('lts'):
            print(v['version'].lstrip('v'))
            break
" 2>/dev/null
}

# ========== 2. Node.js ==========

update_nodejs() {
    section "Node.js"

    local current
    current=$(node --version 2>/dev/null | tr -d 'v' || echo "0")
    info "当前版本: v$current"

    local MIRROR_INDEX="https://cdn.npmmirror.com/binaries/node/index.json"
    local MIRROR_DOWNLOAD="https://cdn.npmmirror.com/binaries/node"
    local FALLBACK_INDEX="https://nodejs.org/dist/index.json"
    local FALLBACK_DOWNLOAD="https://nodejs.org/dist"
    local CURL_OPTS="-s --connect-timeout 5 --max-time 10"

    local pin
    pin=$(get_node_pin)

    local index_json
    index_json=$(curl $CURL_OPTS "$MIRROR_INDEX" 2>/dev/null)
    if [ -z "$index_json" ]; then
        info "镜像不可用，回退到 nodejs.org..."
        index_json=$(curl $CURL_OPTS "$FALLBACK_INDEX" 2>/dev/null)
    fi

    if [ -n "$pin" ] && [ "$pin" != "latest" ]; then
        info "版本锁定: v${pin}.x（编辑 conf/versions.json node.pin 修改）"
    fi

    local target
    target=$(echo "$index_json" | parse_node_target "$pin")

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

    # lark-cli：检测是否已安装（含 Node 升级后符号链接失效的情况）
    local lark_was_installed=false
    if command -v lark-cli &>/dev/null; then
        lark_was_installed=true
    elif [ -L "$LOCAL_BIN/lark-cli" ] || [ -d "$HOME/.local/share/lark-cli" ]; then
        lark_was_installed=true
        info "lark-cli 需要重装（Node 升级后符号链接失效）"
    fi

    if $lark_was_installed; then
        local before latest
        before=$(lark-cli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
        info "lark-cli 当前: $before"

        # 先用 npm registry 检查最新版本（避免盲目更新）
        latest=$(npm view @larksuite/cli version 2>/dev/null || echo "")
        if [ -n "$latest" ] && [ "$before" = "$latest" ] && [ "$before" != "?" ]; then
            success "lark-cli 已是最新: $latest"
        elif ! npm install -g @larksuite/cli@latest 2>&1 | tail -3; then
            warn "lark-cli 更新失败"
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

# ========== 4. Python pip 包 ==========

update_python_packages() {
    section "Python pip 包"

    local req_file="$SCRIPT_DIR/conf/python-requirements.txt"

    if [ ! -f "$req_file" ]; then
        info "未找到 $req_file，跳过"
        return 0
    fi

    # 升级前版本（只取 requirements.txt 中列出的包）
    local before
    before=$(pip3 freeze --user 2>/dev/null | grep -Ff <(sed -n 's/^\([a-zA-Z0-9_-]*\)==.*/\1/p' "$req_file") | sort)

    info "升级 pip 包..."
    local out
    out=$(pip3 install --upgrade -r "$req_file" 2>&1)

    # 只更新已列出的包的版本号，保留注释和分组结构
    python3 - "$req_file" << 'PYEOF'
import sys, subprocess, re

req_file = sys.argv[1]
installed = {}
try:
    out = subprocess.check_output([sys.executable, '-m', 'pip', 'freeze', '--user'], text=True)
    for line in out.strip().split('\n'):
        if '==' in line:
            pkg, ver = line.split('==', 1)
            installed[pkg.lower()] = ver.strip()
except Exception:
    pass

lines = []
with open(req_file, 'r') as f:
    for line in f:
        m = re.match(r'^([a-zA-Z0-9_-]+)==(.+)$', line.rstrip('\n'))
        if m:
            pkg = m.group(1)
            new_ver = installed.get(pkg.lower())
            if new_ver:
                lines.append(f"{pkg}=={new_ver}\n")
            else:
                lines.append(line)
        else:
            lines.append(line)

with open(req_file, 'w') as f:
    f.writelines(lines)
PYEOF

    # 升级后版本
    local after
    after=$(pip3 freeze --user 2>/dev/null | grep -Ff <(sed -n 's/^\([a-zA-Z0-9_-]*\)==.*/\1/p' "$req_file") | sort)

    if [ "$before" = "$after" ]; then
        success "Python pip 包已是最新"
    else
        local upgraded
        upgraded=$(comm -13 <(echo "$before") <(echo "$after") | wc -l)
        success "Python pip 包已升级 ($upgraded 个变动)"
        echo "$out" | grep -E "Successfully|Requirement" | sed 's/^/  /' || true
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

# ========== 版本比较 ==========
# 比较两个语义版本，返回 0 如果 v1 >= v2
version_ge() {
    local v1="$1"
    local v2="$2"
    # 去除 v 前缀
    v1="${v1#v}"
    v2="${v2#v}"
    # 提取主版本号（忽略预发布后缀如 -beta.1）
    local v1_major v1_minor v1_patch v2_major v2_minor v2_patch
    IFS='.' read -r v1_major v1_minor v1_patch <<< "$v1"
    IFS='.' read -r v2_major v2_minor v2_patch <<< "$v2"
    # 去除 v1_patch 中的预发布后缀
    v1_patch="${v1_patch%%-*}"

    if [ "$v1_major" -gt "$v2_major" ]; then return 0; fi
    if [ "$v1_major" -lt "$v2_major" ]; then return 1; fi
    if [ "$v1_minor" -gt "$v2_minor" ]; then return 0; fi
    if [ "$v1_minor" -lt "$v2_minor" ]; then return 1; fi
    if [ "$v1_patch" -ge "$v2_patch" ]; then return 0; fi
    return 1
}

# ========== 4. cc-connect ==========

update_cconnect() {
    section "cc-connect"

    local bin="$LOCAL_BIN/cc-connect"

    # 检查是否安装
    if [ ! -x "$bin" ]; then
        info "cc-connect 未安装，跳过"
        info "如需安装: bash ccconfig/option-bridge/init.sh --cc-connect"
        return 0
    fi

    # 获取当前版本（完整输出，用于显示）
    local current_full
    current_full=$("$bin" --version 2>/dev/null | head -1 || echo "?")
    # 提取主版本号（用于比较）
    local current
    current=$(echo "$current_full" | grep -oP 'v?\d+\.\d+\.\d+' | head -1 || echo "?")
    info "当前版本: $current_full"

    # 获取最新稳定版 release（过滤预发布版本）
    local latest
    latest=$(curl -s --connect-timeout 5 --max-time 10 \
        'https://api.github.com/repos/chenhg5/cc-connect/releases?per_page=10' 2>/dev/null | \
        python3 -c "import json,sys; releases=json.load(sys.stdin); stable=[r for r in releases if not r.get('prerelease',True)]; print(stable[0]['tag_name'] if stable else '')" 2>/dev/null || echo "")

    if [ -z "$latest" ]; then
        warn "无法获取最新 cc-connect 稳定版（可能被限流），跳过"
        return 0
    fi

    # 去除 latest 的 v 前缀
    latest="${latest#v}"

    # 如果本地版本 >= 最新稳定版，则无需更新
    if version_ge "$current" "$latest"; then
        success "cc-connect 已是最新稳定版: $current"
        return 0
    fi

    info "下载 v$latest..."
    local url="https://github.com/chenhg5/cc-connect/releases/download/v${latest}/cc-connect-v${latest}-linux-amd64.tar.gz"
    local tmp="/tmp/cc-connect-update.$$"
    mkdir -p "$tmp"

    if ! curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp/cc-connect.tar.gz"; then
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

    if ! curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp/gh.tar.gz"; then
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

# npm registry 回退 — download.claude.ai (Google IP) 在国内被墙时使用
# @anthropic-ai/claude-code-linux-x64 等包包含原生二进制，由 npmjs.org 分发
install_claude_via_npm() {
    local before="$1"

    if ! command -v npm &>/dev/null; then
        warn "npm 不可用，无法回退"
        return 1
    fi

    local arch
    arch=$(uname -m)
    local npm_pkg
    case "$(uname -s)-$arch" in
        Linux-x86_64)  npm_pkg="@anthropic-ai/claude-code-linux-x64" ;;
        Linux-aarch64) npm_pkg="@anthropic-ai/claude-code-linux-arm64" ;;
        Darwin-x86_64) npm_pkg="@anthropic-ai/claude-code-darwin-x64" ;;
        Darwin-arm64)  npm_pkg="@anthropic-ai/claude-code-darwin-arm64" ;;
        *) warn "系统架构不支持 npm 回退"; return 1 ;;
    esac

    local latest
    latest=$(npm view "$npm_pkg" version 2>/dev/null || echo "")
    if [ -z "$latest" ]; then
        warn "获取 npm 版本失败"
        return 1
    fi

    if [ "$before" = "$latest" ]; then
        success "Claude Code 已是最新稳定版 ($before)"
        return 0
    fi

    info "CDN 不可达，通过 npm registry 下载 v$latest..."
    local tmp="/tmp/claude-npm.$$"
    mkdir -p "$tmp"

    if ! npm pack "$npm_pkg@$latest" --pack-destination "$tmp" 2>&1 | tail -3; then
        err "npm pack 失败"
        rm -rf "$tmp"
        return 1
    fi

    local tgz
    tgz=$(find "$tmp" -name "*.tgz" | head -1)
    if [ -z "$tgz" ]; then
        err "下载失败，未找到包文件"
        rm -rf "$tmp"
        return 1
    fi

    tar xzf "$tgz" -C "$tmp"
    local new_bin="$tmp/package/claude"
    if [ ! -x "$new_bin" ]; then
        err "npm 包中未找到 claude 二进制"
        rm -rf "$tmp"
        return 1
    fi

    local install_dir="$HOME/.local/share/claude/versions/$latest"
    mkdir -p "$HOME/.local/share/claude/versions"
    cp "$new_bin" "$install_dir"
    chmod +x "$install_dir"
    rm -f "$LOCAL_BIN/claude"
    ln -sf "$install_dir" "$LOCAL_BIN/claude"
    rm -rf "$tmp"

    save_version "claude" "$latest"
    success "Claude Code (npm): $before → v$latest"
    return 0
}

update_claude() {
    section "Claude Code"

    if ! command -v claude &>/dev/null; then
        warn "Claude Code 未安装，跳过"
        return 0
    fi

    # 清残留 0 字节半成品（之前 claude install 下载失败留下的）
    find "$HOME/.local/share/claude/versions/" -maxdepth 1 -type f -size 0 -delete 2>/dev/null || true

    local before
    before=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
    info "当前版本: $before"

    set +e
    claude install --force >/dev/null 2>&1
    local install_rc=$?
    set -e

    local after
    after=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?")
    if [ "$before" != "$after" ]; then
        success "Claude Code: $before → $after"
        return 0
    fi

    if [ $install_rc -eq 0 ]; then
        success "Claude Code 已是最新稳定版 ($after)"
        return 0
    fi

    # CDN 不可达，回退到 npm registry
    install_claude_via_npm "$before"
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

    if curl --connect-timeout 10 --max-time 30 -LsSf https://astral.sh/uv/install.sh | sh 2>&1 | tail -3; then
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

# ========== 9. OfficeCLI ==========

update_officecli() {
    section "OfficeCLI"
    bash "$SCRIPT_DIR/option-officecli/init.sh" --update
}

# ========== 10. Skills 同步 ==========

update_skills() {
    section "Skills (claude-skills + ccprivate overlay)"
    bash "$SCRIPT_DIR/init-skill.sh" sync
}

# ========== 11. systemd 服务重建 ==========

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
    node_target=$(echo "$compat_index" | parse_node_target "$pin")

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

# ========== dry-run 检查模式 ==========

do_dry_run() {
    section "dry-run 版本检查（不执行升级）"
    echo ""

    local node_bin
    node_bin=$(find_node_bin)
    export PATH="$node_bin:$LOCAL_BIN:$PATH"

    local checks=0 updates=0

    check_component() {
        local label="$1" current="$2" target="$3"
        checks=$((checks + 1))
        if [ "$current" = "$target" ] || [ "$target" = "?" ] || [ -z "$target" ]; then
            printf "  %-18s %-16s %s\n" "$label" "v$current" "${GREEN}最新${NC}"
        else
            printf "  %-18s %-16s ${YELLOW}→ v%-12s${NC}\n" "$label" "v$current" "$target"
            updates=$((updates + 1))
        fi
    }

    # Node.js
    local node_current node_target node_pin
    node_current=$(get_live_version "node")
    node_pin=$(get_node_pin)
    local MIRROR="https://cdn.npmmirror.com/binaries/node/index.json"
    local FALLBACK="https://nodejs.org/dist/index.json"
    local index_json
    index_json=$(curl -s --connect-timeout 5 --max-time 10 "$MIRROR" 2>/dev/null)
    [ -z "$index_json" ] && index_json=$(curl -s --connect-timeout 5 --max-time 10 "$FALLBACK" 2>/dev/null)
    node_target=$(echo "$index_json" | parse_node_target "$node_pin")
    check_component "Node.js" "$node_current" "$node_target"

    # lark-cli
    local lark_current lark_target
    lark_current=$(get_live_version "lark-cli")
    lark_target=$(npm view @larksuite/cli version 2>/dev/null || echo "?")
    check_component "lark-cli" "$lark_current" "$lark_target"

    # gh
    local gh_current gh_target
    gh_current=$(get_live_version "gh")
    gh_target=$(curl -s --connect-timeout 5 --max-time 10 https://api.github.com/repos/cli/cli/releases/latest 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null || echo "?")
    check_component "GitHub CLI" "$gh_current" "$gh_target"

    # Claude Code
    local claude_current claude_target
    claude_current=$(get_live_version "claude")
    local npm_pkg="@anthropic-ai/claude-code-linux-x64"
    claude_target=$(npm view "$npm_pkg" version 2>/dev/null || echo "?")
    check_component "Claude Code" "$claude_current" "$claude_target"

    # uv
    local uv_current uv_target
    uv_current=$(get_live_version "uv")
    uv_target=$(curl -s --connect-timeout 5 --max-time 10 https://api.github.com/repos/astral-sh/uv/releases/latest 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null || echo "?")
    check_component "uv" "$uv_current" "$uv_target"

    # cc-connect
    if command -v cc-connect &>/dev/null; then
        local cc_current cc_target
        cc_current=$(get_live_version "cconnect")
        cc_target=$(curl -s --connect-timeout 5 --max-time 10 https://api.github.com/repos/chenhg5/cc-connect/releases/latest 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null || echo "?")
        check_component "cc-connect" "$cc_current" "$cc_target"
    fi

    # Python pip
    if command -v pip3 &>/dev/null; then
        local pip_outdated
        pip_outdated=$(pip3 list --user --outdated --format=columns 2>/dev/null | tail -n +3 | grep -Ff <(sed -n 's/^\([a-zA-Z0-9_-]*\)==.*/\1/p' "$SCRIPT_DIR/conf/python-requirements.txt" 2>/dev/null) | wc -l || echo "0")
        checks=$((checks + 1))
        if [ "$pip_outdated" -eq 0 ]; then
            printf "  %-18s %-16s %s\n" "Python pip" "-" "${GREEN}最新${NC}"
        else
            printf "  %-18s %-16s ${YELLOW}%s 个包可升级${NC}\n" "Python pip" "-" "$pip_outdated"
            updates=$((updates + 1))
        fi
    fi

    echo ""
    if [ $updates -eq 0 ]; then
        success "所有 $checks 个组件已是最新"
    else
        warn "$updates/$checks 个组件可升级 → bash ccconfig/update.sh all"
    fi
}

update_all() {
    local include_option="${1:-true}"
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
        # 只对有 comp_key 的步骤记录版本（MCP/systemd 没有版本号）
        if [ -n "$comp_key" ]; then
            after_ver[$comp_key]=$(get_live_version "$comp_key")
        fi
    }

    run_step "node"     "Node.js"           update_nodejs
    run_step "lark-cli" "npm 全局包"        update_npm_globals
    run_step ""         "Python pip 包"     update_python_packages
    run_step ""         "Skills 同步"       update_skills
    if [ "$include_option" = "true" ]; then
        run_step "cconnect" "cc-connect"        update_cconnect
        run_step ""         "OfficeCLI"          update_officecli
    fi
    run_step "gh"       "GitHub CLI"        update_gh
    run_step "claude"   "Claude Code"       update_claude
    run_step "uv"       "uv"                update_uv
    run_step ""         "MCP 缓存"          update_mcp
    if [ "$include_option" = "true" ]; then
        run_step ""         "systemd 服务"      fix_systemd_services
    fi

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
    local today
    today=$(date +%Y-%m)
    echo ""
    echo -e "${CYAN}━━━ ccconfig 组件升级 $today ━━━${NC}"
    echo ""
    echo "   基础组件"
    echo "   1) Node.js + lark-cli + pip 包"
    echo -e "      ${DIM}(自动触发 systemd 服务重建)${NC}"
    echo ""
    echo "   扩展组件"
    echo "   2) GitHub CLI"
    echo "   3) Claude Code"
    echo "   4) uv"
    echo "   5) MCP 缓存刷新"
    echo ""
    echo "   可选组件"
    echo "   6) cc-connect（Bridge）"
    echo "   7) systemd 服务重建"
    echo "   8) OfficeCLI"
    echo "   9) Skills 同步"
    echo ""
    echo "   0) 退出"
    echo ""
    echo -e "   ${YELLOW}all${NC} = 升级基础+扩展（不含可选）"
    echo -e "   ${YELLOW}1 3 5${NC} = 多选（如升级 1、3、5 项）"
    echo ""
    read -p "选择 [1-9, all, 0]: " choice

    # 多选支持：空格/逗号分隔如 "1 3 4" 或 "1,3,4"
    local selections
    selections=$(echo "$choice" | tr ',' ' ' | tr '[:space:]' '\n' | grep -E '^[1-9]$|^all$' | sort -u | tr '\n' ' ')

    local did_something=0
    for sel in $selections; do
        case "$sel" in
            1)  update_nodejs; update_npm_globals; update_python_packages; fix_systemd_services; did_something=1 ;;
            2)  update_gh; did_something=1 ;;
            3)  update_claude; did_something=1 ;;
            4)  update_uv; did_something=1 ;;
            5)  update_mcp; did_something=1 ;;
            6)  update_cconnect; did_something=1 ;;
            7)  fix_systemd_services; did_something=1 ;;
            8)  update_officecli; did_something=1 ;;
            9)  update_skills; did_something=1 ;;
            all)
                take_snapshot "pre" > /dev/null
                update_all false
                did_something=1
                break
                ;;
        esac
    done

    if [ $did_something -eq 0 ] && [ "$choice" != "0" ]; then
        echo "无效选择: $choice"
    fi

    if [ "$choice" != "0" ]; then
        show_menu
    fi
}

# ========== 主程序 ==========
acquire_lock
trap release_lock EXIT

case "${1:-menu}" in
    all)
        self_update "${1:-menu}"
        today=$(date +%Y-%m-%d)
        echo -e "${CYAN}ccconfig 组件升级 $today（基础+扩展）${NC}"
        take_snapshot "pre" > /dev/null
        update_all false
        ;;
    --no-option)
        self_update "${1:-menu}"
        today=$(date +%Y-%m-%d)
        echo -e "${CYAN}ccconfig 组件升级 $today（不含可选）${NC}"
        take_snapshot "pre" > /dev/null
        update_all false
        ;;
    node)          update_nodejs ;;
    npm)           update_npm_globals ;;
    python)        update_python_packages ;;
    cconnect)      update_cconnect ;;
    gh)            update_gh ;;
    claude)        update_claude ;;
    uv)            update_uv ;;
    mcp)           update_mcp ;;
    services)      fix_systemd_services ;;
    officecli)     update_officecli ;;
    skills)        update_skills ;;
    menu|"")
        self_update "menu"
        show_menu ;;
    --dry-run|--check|check)
        do_dry_run ;;
    *)
        echo "用法: $0 [all|node|npm|python|cconnect|gh|claude|uv|mcp|services|menu]"
        exit 1
        ;;
esac

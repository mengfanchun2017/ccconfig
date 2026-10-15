#!/bin/bash
# ccconfig/option-playwright/init.sh — Playwright MCP 可选组件（浏览器自动化）
#
# 用途：给 Claude 提供浏览器控制能力（fmashwork 图生3D 走网页通道需要）。
# 组成（4 层，WSL 下缺一不可）：
#   1. @playwright/mcp  npm 包   → npx 自动拉，无需装
#   2. Chromium 二进制           → npx playwright install chromium → ~/.cache/ms-playwright/
#   3. 系统 .so 依赖             → 免 root 装载到 ~/.local/state/pw-chromium/deps/
#                                  （apt-get download + dpkg-deb -x，无需 sudo）
#   4. MCP 注册                  → 已在 conf/mcp-servers.json 定义，init-mcp.sh sync 注册
#
# 用法：
#   bash init.sh --status   状态检查
#   bash init.sh --install  安装（首次；自动跑 chromium + 依赖）
#   bash init.sh --update   更新
#
# 依赖免 root 装载：
#   WSL 后台 agent 无法交互输 sudo 密码，install-deps 会卡死。改为：
#     apt-get download <libs>  → dpkg-deb -x 解包到用户目录
#     wrapper（$PW_CHROME）设 LD_LIBRARY_PATH 指向解包目录
#   包名用 `npx playwright install-deps chromium --dry-run` 动态取（随 Playwright
#   版本变化，不硬编码）。只需 lib*/x11-xkb-utils，字体/xvfb headless 用不到。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_ROOT/lib/dry-run.sh"
source "$CCCONFIG_ROOT/lib/colors.sh"
source "$CCCONFIG_ROOT/lib/path-helper.sh"

# Playwright 的 chromium 缓存目录（判断二进制是否已装）
PW_CACHE_DIR="${HOME}/.cache/ms-playwright"

# 稳定目录（MCP --executable-path 指向此处的 wrapper，chromium 升级不破 MCP）
PW_STATE_DIR="${HOME}/.local/state/pw-chromium"
PW_CHROME="$PW_STATE_DIR/chrome"          # wrapper（下方生成，设 LD_LIBRARY_PATH）
PW_CHROME_REAL="$PW_STATE_DIR/chrome-real" # symlink → 实际 chromium 二进制
PW_DEPS_DIR="$PW_STATE_DIR/deps"           # 免 root 解包的 .so 依赖

# 判断 Chromium 是否已下载（Playwright 下载目录存在且含 chromium-X 版本目录）
chromium_installed() {
    [[ -d "$PW_CACHE_DIR" ]] && find "$PW_CACHE_DIR" -maxdepth 1 -type d -name 'chromium-*' | grep -q . && return 0
    return 1
}

# 定位实际 chromium 二进制（新 Playwright 是 chrome-linux64，兼容旧 chrome-linux）
chromium_bin() {
    find "$PW_CACHE_DIR" -path '*/chrome-linux64/chrome' 2>/dev/null | head -1
}

# 判断系统 .so 依赖是否齐全：经 wrapper 跑 chromium --version 探活最可靠
deps_installed() {
    [[ -z "$(chromium_bin)" ]] && return 1  # 没二进制，依赖无从验证
    [[ -x "$PW_CHROME" ]] || return 1       # wrapper 未生成 = 依赖未装载
    "$PW_CHROME" --version >/dev/null 2>&1
}

# 重建 wrapper + symlink（chromium 升级后路径漂移不破 MCP）
refresh_chromium_symlink() {
    local target
    target=$(chromium_bin)
    [[ -z "$target" ]] && return 1
    mkdir -p "$PW_STATE_DIR"
    ln -sfn "$target" "$PW_CHROME_REAL"
    cat > "$PW_CHROME" <<'PWWRAP'
#!/bin/bash
# ccconfig option-playwright 生成：设 LD_LIBRARY_PATH 指向用户态解包的 .so，再 exec 真二进制
DIR="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$DIR/deps${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$DIR/chrome-real" "$@"
PWWRAP
    chmod +x "$PW_CHROME"
    info "chromium wrapper → $PW_CHROME"
}

# 取本机 chromium 缺的系统包名（Playwright 官方 dry-run，随版本动态变化）
missing_deps_pkgs() {
    timeout 180 npx --yes playwright install-deps chromium --dry-run 2>/dev/null \
        | sed 's/^[[:space:]]*//' \
        | grep -E '^(lib|x11-xkb-utils)' | grep -vE 'data$'
}

# 免 root 装载系统 .so：apt-get download（免 root）→ dpkg-deb -x 解包到 PW_DEPS_DIR
install_deps_userland() {
    local pkgs
    pkgs=$(missing_deps_pkgs)
    [[ -z "$pkgs" ]] && { info "Playwright 报告无需系统包（或已具备）"; return 0; }

    local tmp; tmp=$(mktemp -d) || return 1
    echo -n "→ 下载系统依赖（免 root，$(echo "$pkgs" | wc -l) 包）... "
    if ! ( cd "$tmp" && apt-get download $pkgs ) >/dev/null 2>&1; then
        bad "fail"
        warn "apt-get download 失败（源不可达？）"
        rm -rf "$tmp"; return 1
    fi
    good "ok"

    mkdir -p "$PW_DEPS_DIR"
    local n=0
    for f in "$tmp"/*.deb; do
        [[ -f "$f" ]] || continue
        dpkg-deb -x "$f" "$tmp/root" || { warn "解包失败: $f"; continue; }
        n=$((n+1))
    done
    rm -rf "$PW_DEPS_DIR"
    mkdir -p "$PW_DEPS_DIR"
    cp -r "$tmp/root/usr/lib/x86_64-linux-gnu/." "$PW_DEPS_DIR/" 2>/dev/null || true
    rm -rf "$tmp"
    info "依赖已装载到 $PW_DEPS_DIR（$n 包免 root）"
}

# 判断 MCP 是否已注册：看运行时 .config.json 有没有 playwright 条目
mcp_registered() {
    local conf="${HOME}/.claude/.config.json"
    [[ -f "$conf" ]] && grep -q '"playwright"' "$conf"
}

do_status() {
    local missing=""

    if ! command -v npx &>/dev/null; then
        echo "MISSING Playwright 缺 npx (需要 Node.js ≥ 22)"
        return 1
    fi

    chromium_installed || missing="${missing}chromium "

    deps_installed || missing="${missing}系统依赖(.so) "

    mcp_registered || missing="${missing}MCP注册 "

    if [[ -z "$missing" ]]; then
        echo "OK Playwright 就绪（Chromium + 系统依赖 + MCP 齐全）"
    else
        echo "WARN Playwright 缺: ${missing}（运行 --install）"
    fi
}

do_install() {
    echo -e "${CYAN}── Playwright MCP 安装 ──${NC}"

    # 1. npx 直接拉包（无需显式 npm install）
    if ! command -v npx &>/dev/null; then
        err "缺 npx，需 Node.js ≥ 22（bash ccconfig/init-base.sh 或手动装）"
        return 1
    fi

    # 2. Chromium 二进制（用国内镜像，微软 CDN 在 WSL 常卡死）
    if chromium_installed; then
        info "Chromium 已装（$PW_CACHE_DIR）"
    else
        echo -n "→ 下载 Chromium（npmmirror 镜像）... "
        if run env PLAYWRIGHT_DOWNLOAD_HOST="https://npmmirror.com/mirrors/playwright/" npx --yes playwright install chromium; then
            good "ok"
        else
            bad "fail"
            return 1
        fi
    fi
    # 重建稳定 symlink，MCP --executable-path 指向它（版本漂移不破 MCP）
    refresh_chromium_symlink || warn "symlink 重建失败（不影响下载，MCP 可能仍指旧版）"

    # 3. 系统 .so 依赖（免 root 装载到用户目录，无需 sudo）
    if deps_installed; then
        info "系统依赖已就绪"
    else
        install_deps_userland || return 1
        refresh_chromium_symlink || warn "wrapper 重建失败"
        if ! deps_installed; then
            warn "依赖装载后 chromium 仍无法启动，请检查 $PW_DEPS_DIR"
            return 1
        fi
        good "chromium 现已可启动（用户态依赖）"
    fi

    # 4. 注册 MCP（用 ccconfig 标准机制）
    echo ""
    info "注册 MCP 到 conf ..."
    bash "$CCCONFIG_ROOT/lib/init-mcp.sh" sync 2>&1 | tail -15 || true
    echo ""
    good "✅ Playwright 安装完成。restart Claude session 生效。"
}

do_update() {
    echo -e "${CYAN}── 更新 Playwright ──${NC}"
    # 清缓存重装（Playwright 无版本管理脚本，直接重下 chromium 最新）
    if chromium_installed; then
        echo -n "→ 清旧 Chromium 缓存 ... "
        find "$PW_CACHE_DIR" -mindepth 1 -maxdepth 1 -exec rm -r {} + && good "ok"
    fi
    do_install
}

case "${1:-menu}" in
    --status) do_status ;;
    --install) do_install ;;
    --update) do_update ;;
    menu|"") do_install ;;
    *) echo "用法: $0 [--status|--install|--update|menu]" ;;
esac
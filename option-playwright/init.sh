#!/bin/bash
# ccconfig/option-playwright/init.sh — Playwright MCP 可选组件（浏览器自动化）
#
# 用途：给 Claude 提供浏览器控制能力（fmashwork 图生3D 走网页通道需要）。
# 组成（4 层，WSL 下缺一不可）：
#   1. @playwright/mcp  npm 包   → npx 自动拉，无需装
#   2. Chromium 二进制           → npx playwright install chromium → ~/.cache/ms-playwright/
#   3. 系统 .so 依赖             → npx playwright install-deps chromium（需 sudo apt，跑一次）
#   4. MCP 注册                  → 已在 conf/mcp-servers.json 定义，init-mcp.sh sync 注册
#
# 用法：
#   bash init.sh --status   状态检查
#   bash init.sh --install  安装（首次；自动跑 chromium + install-deps）
#   bash init.sh --update   更新
#
# 注意：install-deps 需要 sudo（apt-get）。WSL 后台 agent 无法交互输密码，
#   首次手动跑一次 `sudo npx playwright install-deps chromium` 后即永久可用。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_ROOT/lib/dry-run.sh"
source "$CCCONFIG_ROOT/lib/colors.sh"
source "$CCCONFIG_ROOT/lib/path-helper.sh"

# Playwright 的 chromium 缓存目录（判断二进制是否已装）
PW_CACHE_DIR="${HOME}/.cache/ms-playwright"

# 判断 Chromium 是否已下载（Playwright 下载目录存在且含 chromium-X 版本目录）
chromium_installed() {
    [[ -d "$PW_CACHE_DIR" ]] && find "$PW_CACHE_DIR" -maxdepth 1 -type d -name 'chromium-*' | grep -q . && return 0
    return 1
}

# 判断系统 .so 依赖是否齐全：跑 chromium --version 探活最可靠
# 注意目录是 chrome-linux64（新 Playwright），兼容旧 chrome-linux
deps_installed() {
    local browser_bin
    browser_bin=$(find "$PW_CACHE_DIR" \( -path '*/chrome-linux*/chrome' -o -path '*/chrome-linux*/headless_shell' \) 2>/dev/null | head -1)
    [[ -z "$browser_bin" ]] && return 1  # 没二进制，依赖无从验证
    "$browser_bin" --version >/dev/null 2>&1
}

# MCP 配置里 --executable-path 指向稳定 symlink（避免 chromium 升级后路径漂移）。
# 每次 install/update 后重建 symlink → MCP 配置无需改。
PW_SYMLINK="${HOME}/.local/state/pw-chromium/chrome"
refresh_chromium_symlink() {
    local target
    target=$(find "$PW_CACHE_DIR" -path '*/chrome-linux64/chrome' 2>/dev/null | head -1)
    [[ -z "$target" ]] && return 1
    mkdir -p "$(dirname "$PW_SYMLINK")"
    ln -sfn "$target" "$PW_SYMLINK"
    info "chromium symlink → $PW_SYMLINK"
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

    # 3. 系统 .so 依赖（唯一需 sudo 的一步，一次性）
    if deps_installed; then
        info "系统依赖已就绪"
    else
        echo -e "${YELLOW}→ 需装系统依赖（sudo apt-get）...${NC}"
        echo ""
        echo -e "  ${GRAY}Playwright 的 chromium 需要 ~20 个系统 .so 库，由 install-deps 自动装。${NC}"
        echo -e "  ${GRAY}WSL 后台无法交互输 sudo 密码，请在终端手动跑一次（一次性）：${NC}"
        echo ""
        echo "      sudo env \"PATH=\$PATH\" npx --yes playwright install-deps chromium"
        echo ""
        echo -e "  ${GRAY}(playwright 包已装则这条只 apt 装 .so,很快。npx 在 user-local 路径,sudo 需显式传 PATH)${NC}"
        echo ""
        return 1
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
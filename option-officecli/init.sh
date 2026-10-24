#!/bin/bash
# ccconfig/option-officecli/init.sh — OfficeCLI 初始化（可选组件）
#
# OfficeCLI（⭐5k）是 AI-native 的命令行 Office 工具，单二进制零依赖。
# 支持创建/编辑/读取 .pptx .docx .xlsx，JSON 输出，批量模式，MCP 协议。
#
# 用法：
#   bash ccconfig/option-officecli/init.sh              # 交互式
#   bash ccconfig/option-officecli/init.sh --install    # 仅安装
#   bash ccconfig/option-officecli/init.sh --status     # 状态检查
#   bash ccconfig/option-officecli/init.sh --update     # 更新

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$CCCONFIG_DIR/lib/dry-run.sh"
source "$CCCONFIG_DIR/lib/path-helper.sh"
source "$CCCONFIG_DIR/lib/net.sh"
export PATH="${HOME}/.local/bin:$(find_node_bin):$PATH"

source "$CCCONFIG_DIR/lib/colors.sh"
source "$CCCONFIG_DIR/lib/interact.sh"

OFFICECLI_BIN="$HOME/.local/bin/officecli"
GITHUB_REPO="iOfficeAI/OfficeCLI"
MIRROR_BASE="https://d.officecli.ai"
NPM_PKG="@officecli/officecli"

# ── 发行版资产名（与 npm 包 detectAsset 一致：linux glibc/musl 分档）──
_detect_asset() {
    local os arch
    os=$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m 2>/dev/null)
    case "$arch" in x86_64|amd64) arch="x64" ;; aarch64|arm64) arch="arm64" ;; esac
    case "$os" in
        linux)
            if ldd --version 2>&1 | grep -qi musl || [ -f /etc/alpine-release ]; then
                echo "officecli-linux-alpine-${arch}"
            else
                echo "officecli-linux-${arch}"
            fi ;;
        darwin) echo "officecli-mac-${arch}" ;;
        mingw*|msys*|cygwin*) echo "officecli-win-${arch}.exe" ;;
        *)      echo "officecli-linux-${arch}" ;;
    esac
}

# ── 就绪判定：必须能真跑出版本号 ──
# ⚠️ 只判 -x 不够：npm 的 officecli 是 JS shim，平台二进制缺失时会**懒下载**，
# 从 d.officecli.ai 拉（国内限速到 ~250B/s）→ 每个调用静默卡死几分钟。
# 这正是"2D 装 officecli 卡住"的直接原因，故用带超时的版本探测做就绪条件。
_officli_ready() {
    [ -x "$OFFICECLI_BIN" ] || return 1
    timeout 8 "$OFFICECLI_BIN" --version >/dev/null 2>&1
}

_cli_version() {
    timeout 8 "$OFFICECLI_BIN" --version 2>/dev/null | head -1 | tr -d '\r'
}

banner() {
    echo -e "${CYAN}"
    echo "OfficeCLI — AI-native Office 工具"
    echo "═══════════════════════════════════"
    echo "    .pptx .docx .xlsx 单二进制零依赖"
    echo "$NC"
}

# ========== 获取最新版本 ==========
get_latest_version() {
    curl -sL --max-time 15 "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | \
        python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || echo ""
}

# ========== libicu 依赖 ==========
# 复用 lib/ensure-libicu.sh（发行版自适应包名，24.04→libicu74 / 26.04→libicu78）
source "$CCCONFIG_DIR/lib/ensure-libicu.sh"

# ========== 安装 ==========
# 两条路，按顺序试：
#   1) npm 全局装 @officecli/officecli（shim + postinstall 抓平台二进制；
#      postinstall 走 d.officecli.ai，国内慢但能过）
#   2) npm 失败 → 直接用 Clash 代理从 GitHub releases 下平台二进制到 ~/.local/bin
#      （逐个 tag 试，因为 latest 在 GitHub 上被代理重定向后不一定解析得对）
install_officecli() {
    echo -e "${CYAN}── 安装 OfficeCLI ──${NC}"

    ensure_libicu || true

    if _officli_ready; then
        echo -n "  OfficeCLI ... "
        good "✅ $(_cli_version)"
        return 0
    fi

    if [ -x "$OFFICECLI_BIN" ]; then
        warn "  officecli 存在但无法运行（二进制缺失，npm shim 会静默懒下载卡死）→ 重装"
    fi

    # ── 路 1: npm ──
    if command -v npm >/dev/null 2>&1; then
        info "  npm install -g $NPM_PKG ..."
        if timeout 600 npm install -g "$NPM_PKG" 2>&1 | tail -5 | sed 's/^/    /'; then
            ensure_path_officecli
            _officli_ready && { good "✅ 已装（npm）: $(_cli_version)"; return 0; }
            warn "  npm 装完但仍无法运行（平台二进制没抓到），改走代理直下"
        else
            warn "  npm 安装失败，改走代理直下二进制"
        fi
    fi

    # ── 路 2: 代理直下 GitHub 二进制 ──
    install_officecli_binary
}

# 把 npm 全局 bin 里的 officecli 链到 ~/.local/bin（PATH 兜底）
ensure_path_officecli() {
    command -v officecli >/dev/null 2>&1 && return 0
    local npm_bin; npm_bin="$(npm prefix -g 2>/dev/null)/bin"
    if [ -x "$npm_bin/officecli" ] && [ -d "$HOME/.local/bin" ]; then
        ln -sf "$npm_bin/officecli" "$OFFICECLI_BIN"
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

install_officecli_binary() {
    local asset; asset=$(_detect_asset)
    local proxy; proxy=$(net_gh_proxy)
    [ -z "$proxy" ] && warn "  未取到本机代理，直连 GitHub 大概率超时"

    # 先拿候选 tag：API（走代理可达）→ latest
    local -a tags=()
    local api_tag
    api_tag=$(curl -s --max-time 15 ${proxy:+-x "$proxy"} \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || true)
    [ -n "$api_tag" ] && tags+=("$api_tag")

    mkdir -p "$HOME/.local/bin"
    local tmp="$HOME/.local/bin/.officecli.tmp"

    local url
    for tag in "${tags[@]}" "latest"; do
        url="https://github.com/${GITHUB_REPO}/releases/download/${tag}/${asset}"
        echo -n "  下载 ($tag, $asset) ... "
        if curl -L ${proxy:+-x "$proxy"} --connect-timeout 15 ${proxy:--m 300} \
             --max-time 600 --progress-bar -C - -o "$tmp" "$url" 2>&1 | tail -1 | sed 's/^/    /'; then
            local size; size=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
            if [ "$size" -lt 3000000 ]; then
                bad "❌ 文件异常小 ($size bytes，非完整二进制)"
                rm -f "$tmp"; continue
            fi
            chmod +x "$tmp"
            if timeout 15 "$tmp" --version >/dev/null 2>&1; then
                mv "$tmp" "$OFFICECLI_BIN"
                good "✅ ($(numfmt --to=iec "$size" 2>/dev/null || echo "$size")) $(_cli_version)"
                return 0
            fi
            bad "❌ 下载物无法执行"
            rm -f "$tmp"
        else
            bad "❌ 下载失败"
        fi
    done

    rm -f "$tmp"
    err "❌ OfficeCLI 安装失败"
    warn "  手动: curl -L -x http://127.0.0.1:7897 \\"
    warn "    https://github.com/${GITHUB_REPO}/releases/download/<tag>/${asset} -o ~/.local/bin/officecli"
    return 1
}

# ========== 更新 ==========
update_officecli() {
    echo -e "${CYAN}── 更新 OfficeCLI ──${NC}"

    # 网络预检（直连被 GFW 阻断时自动走本机 Clash 代理）
    if ! github_reachable; then
        warn "GitHub 不可达，跳过"
        return 0
    fi

    ensure_libicu || true

    local current=""
    _officli_ready && current=$(_cli_version)
    info "  当前版本: ${current:-未安装/不可用}"

    local latest; latest=$(get_latest_version)
    [ -z "$latest" ] && { bad "无法获取最新版本"; return 1; }
    info "  最新版本: $latest"

    # tag_name 带 v 前缀（v1.0.143），本地版本不带 → 统一去 v 比较
    if [ -n "$current" ] && [ "${current#v}" = "${latest#v}" ]; then
        good "  已是最新"
        return 0
    fi

    # 备份旧版本（仅当它能跑，避免备份一个懒惰下载的 shim）
    if _officli_ready; then
        cp "$OFFICECLI_BIN" "${OFFICECLI_BIN}.bak.${current}" 2>/dev/null || true
    fi

    install_officecli
}

# ========== 状态检查 ==========
show_status() {
    local ready=true
    _officli_ready || ready=false
    if $ready; then
        echo "OK OfficeCLI 已安装（$(_cli_version)）"
    elif [ -x "$OFFICECLI_BIN" ]; then
        echo "WARN OfficeCLI 存在但无法运行 → bash option-officecli/init.sh --install"
    else
        echo "MISSING OfficeCLI 未安装"
    fi

    echo -e "${CYAN}── OfficeCLI 状态 ──${NC}"

    echo -n "  二进制 ... "
    if $ready; then
        good "✅ $(_cli_version)"
    elif [ -x "$OFFICECLI_BIN" ]; then
        bad "❌ 存在但跑不起来（平台二进制缺失，npm shim 会静默懒下载）"
    else
        bad "❌ 未安装"
    fi

    echo -n "  libicu ... "
    if ldconfig -p 2>/dev/null | grep -q "libicuuc\.so"; then
        good "✅"
    else
        warn "○ 缺 libicu（.NET 二进制无法启动）"
        warn "  安装: sudo apt-get install -y libicu78"
    fi

    # MCP 检查必须带超时：shim 懒下载会把这里也拖死
    echo -n "  MCP 注册 ... "
    local mcp_out
    mcp_out=$(timeout 10 "$OFFICECLI_BIN" mcp list 2>/dev/null || true)
    if echo "$mcp_out" | grep -q "Claude Code.*registered"; then
        good "✅"
    elif echo "$mcp_out" | grep -q "Claude Code"; then
        warn "○ 未注册"
    else
        info "○ 未检查"
    fi

    echo ""
    $ready || return 1
}

# ========== 交互式 ==========
interactive_mode() {
    banner
    echo ""

    show_status
    echo ""

    echo -e "${BOLD}OfficeCLI${NC} — AI-native Office 命令行工具"
    echo -e "  ${GRAY}创建/编辑 .pptx .docx .xlsx，JSON 输出，批量模式${NC}"
    echo ""
    echo "  ┌─ 安装内容 ─────────────────────────────┐"
    echo "  │ • 单二进制文件 (~33MB)                   │"
    echo "  │ • 依赖 libicu（.NET 必需，自动安装）    │"
    echo "  │ • 可选: MCP 注册到 Claude Code          │"
    echo "  └─────────────────────────────────────────┘"
    echo ""

    local need_install=false
    [ -x "$OFFICECLI_BIN" ] || need_install=true

    if $need_install; then
        if confirm "安装 OfficeCLI？" y; then
            echo ""; install_officecli
        else
            info "跳过"; return 0
        fi
    else
        ok "已安装"
        echo ""
        if confirm "更新到最新？" n; then
            update_officecli
        fi
    fi

    echo ""
    good "✅ OfficeCLI 就绪"
    echo ""
    echo "后续操作:"
    echo "  创建 PPT:   officecli create deck.pptx"
    echo "  批量模式:   officecli batch deck.pptx --input cmds.json"
    echo "  状态检查:   bash ccconfig/option-officecli/init.sh --status"
    echo "  更新:       bash ccconfig/option-officecli/init.sh --update"
}

# ========== 主程序 ==========
main() {
    case "${1:-}" in
        --install|-i)
            install_officecli
            echo ""
            good "✅ OfficeCLI 安装完成"
            ;;
        --update|-u)
            update_officecli
            ;;
        --status|-s)
            show_status
            ;;
        --help|-h)
            echo "用法: $0 [--install|--update|--status]"
            echo ""
            echo "  (无参数)     交互式模式（推荐）"
            echo "  --install    安装 OfficeCLI"
            echo "  --update     更新到最新版本"
            echo "  --status     状态检查"
            ;;
        "")
            interactive_mode
            ;;
        *)
            bad "❌ 未知参数: $1"; exit 1
            ;;
    esac
}

main "$@"

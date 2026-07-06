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

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$CCCONFIG_DIR/lib/path-helper.sh"
export PATH="${HOME}/.local/bin:$(find_node_bin):$PATH"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad()  { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
info() { echo -e "${GRAY}$1${NC}"; }

OFFICECLI_BIN="$HOME/.local/bin/officecli"
GITHUB_REPO="iOfficeAI/OfficeCLI"
DOWNLOAD_URL="https://github.com/iOfficeAI/OfficeCLI/releases/latest/download/OfficeCLI-linux-x64"

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║     OfficeCLI — AI-native Office 工具            ║"
    echo "║     .pptx .docx .xlsx 单二进制零依赖             ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"
}

# ========== 获取最新版本 ==========
get_latest_version() {
    curl -sL --max-time 15 "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | \
        python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || echo ""
}

# ========== 安装 ==========
install_officecli() {
    echo -e "${CYAN}── 安装 OfficeCLI ──${NC}"

    if [ -x "$OFFICECLI_BIN" ]; then
        local ver=$("$OFFICECLI_BIN" --version 2>/dev/null)
        echo -n "  OfficeCLI ... "
        good "✅ $ver"
        return 0
    fi

    local latest=$(get_latest_version)
    [ -n "$latest" ] && info "  最新版本: $latest"

    echo -n "  下载 ... "
    local tmp="/tmp/officecli-$(date +%s)"
    if curl -L --progress-bar -o "$tmp" "$DOWNLOAD_URL" 2>&1; then
        local size=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
        if [ "$size" -lt 1000000 ]; then
            bad "❌ 下载文件异常小 ($size bytes)"
            rm -f "$tmp"
            return 1
        fi
        good "✅ ($(numfmt --to=iec $size 2>/dev/null || echo ${size} bytes))"
    else
        bad "❌ 下载失败"
        warn "  手动: curl -L $DOWNLOAD_URL -o $OFFICECLI_BIN"
        rm -f "$tmp"
        return 1
    fi

    echo -n "  安装到 ~/.local/bin ... "
    mkdir -p "$HOME/.local/bin"
    mv "$tmp" "$OFFICECLI_BIN"
    chmod +x "$OFFICECLI_BIN"
    good "✅"

    local ver=$("$OFFICECLI_BIN" --version 2>/dev/null)
    info "  版本: $ver"
}

# ========== 更新 ==========
update_officecli() {
    echo -e "${CYAN}── 更新 OfficeCLI ──${NC}"

    local current=""
    if [ -x "$OFFICECLI_BIN" ]; then
        current=$("$OFFICECLI_BIN" --version 2>/dev/null)
    fi
    info "  当前版本: ${current:-未安装}"

    local latest=$(get_latest_version)
    [ -z "$latest" ] && { bad "❌ 无法获取最新版本"; return 1; }
    info "  最新版本: $latest"

    if [ "$current" = "$latest" ]; then
        good "  已是最新"
        return 0
    fi

    # 备份旧版本
    if [ -x "$OFFICECLI_BIN" ]; then
        cp "$OFFICECLI_BIN" "${OFFICECLI_BIN}.bak.${current}"
    fi

    install_officecli
}

# ========== 状态检查 ==========
show_status() {
    local ok=true
    [ -x "$OFFICECLI_BIN" ] || ok=false
    if $ok; then echo "OK OfficeCLI 已安装"; else echo "FAIL OfficeCLI 未安装"; fi

    echo -e "${CYAN}── OfficeCLI 状态 ──${NC}"

    echo -n "  二进制 ... "
    if [ -x "$OFFICECLI_BIN" ]; then
        local ver=$("$OFFICECLI_BIN" --version 2>/dev/null)
        good "✅ $ver"
    else
        bad "❌ 未安装"
    fi

    echo -n "  MCP 注册 ... "
    if "$OFFICECLI_BIN" mcp list 2>/dev/null | grep -q "Claude Code.*registered"; then
        good "✅"
    elif "$OFFICECLI_BIN" mcp list 2>/dev/null | grep -q "Claude Code"; then
        warn "○ 未注册"
    else
        info "○ 未检查"
    fi

    echo ""
    $ok || return 1
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
    echo "  │ • 零依赖，无需 Office/LibreOffice       │"
    echo "  │ • 可选: MCP 注册到 Claude Code          │"
    echo "  └─────────────────────────────────────────┘"
    echo ""

    local need_install=false
    [ -x "$OFFICECLI_BIN" ] || need_install=true

    if $need_install; then
        read -p "  安装 OfficeCLI? [Y/n]: " confirm
        confirm="${confirm:-y}"
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "  跳过"
            return 0
        fi
        echo ""
        install_officecli
    else
        good "  已安装"
        echo ""
        read -p "  更新到最新? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
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

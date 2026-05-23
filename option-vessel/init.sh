#!/bin/bash
# ccconfig/option-vessel/init.sh — Vessel AI Agent 浏览器初始化（可选组件）
#
# Vessel 是开源的 AI Agent 浏览器，Claude Code 可通过 MCP 协议操控它：
#   打开网页、点击、填表、提取内容、截图等
#   所有操作在 Supervisor 侧边栏实时可见，人类可审批
#
# 用法：
#   bash ccconfig/option-vessel/init.sh              # 交互式（推荐）
#   bash ccconfig/option-vessel/init.sh --install    # 仅安装 Vessel
#   bash ccconfig/option-vessel/init.sh --mcp        # 仅配置 MCP
#   bash ccconfig/option-vessel/init.sh --status     # 状态检查

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

VESSEL_BIN="$HOME/.local/bin/vessel"
VESSEL_DIR="$HOME/.local/lib/vessel"
GITHUB_REPO="unmodeled-tyler/vessel-browser"
MCP_PORT=3100

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║     Vessel — AI Agent 浏览器（可选组件）         ║"
    echo "║     MCP 协议操控，人类监督审批                   ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"
}

# ========== 环境检测 ==========
detect_env() {
    echo -e "${CYAN}── 环境检测 ──${NC}"
    echo -n "  WSLg (GUI) ... "
    if [ -n "$DISPLAY" ] && [ -d /mnt/wslg ]; then
        good "✓ WSLg (DISPLAY=$DISPLAY)"
    elif [ -n "$DISPLAY" ]; then
        good "✓ DISPLAY=$DISPLAY"
    else
        warn "○ 无 GUI 环境，Vessel 需要图形界面"
    fi
    echo -n "  curl ... "
    command -v curl &>/dev/null && good "✓" || { bad "❌"; return 1; }
    echo ""
}

# ========== 获取最新版本 ==========
get_latest_version() {
    curl -sL --max-time 15 "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=3" 2>/dev/null | \
        python3 -c "import json,sys; data=json.load(sys.stdin); print(data[0]['tag_name'])" 2>/dev/null || echo ""
}

# ========== 安装系统依赖 ==========
install_deps() {
    echo -e "${CYAN}── 系统依赖 ──${NC}"
    local missing=()
    for lib in libnspr4 libnss3 libasound2t64; do
        dpkg -l "$lib" 2>/dev/null | grep -q "^ii" || missing+=("$lib")
    done
    if [ ${#missing[@]} -eq 0 ]; then
        good "  ✓ 已安装"
        return 0
    fi
    echo -e "  ${YELLOW}缺: ${missing[*]}${NC}"
    echo -n "  sudo apt-get install ... "
    if sudo apt-get install -y "${missing[@]}" 2>&1 | tail -1; then
        good "  ✅ 依赖安装完成"
    else
        bad "  ❌ 安装失败，手动执行: sudo apt-get install -y ${missing[*]}"
        return 1
    fi
}

# ========== 下载安装 Vessel ==========
install_vessel() {
    echo -e "${CYAN}── 安装 Vessel ──${NC}"

    # 检查已安装版本
    if [ -x "$VESSEL_BIN" ] || [ -f "$VESSEL_DIR/squashfs-root/vessel" ]; then
        echo -n "  Vessel ... "
        good "✓ 已安装"
        return 0
    fi

    local version=$(get_latest_version)
    if [ -z "$version" ]; then
        bad "  ❌ 无法获取最新版本（GitHub API 不可达）"
        echo "  手动下载: https://github.com/${GITHUB_REPO}/releases"
        return 1
    fi
    info "  最新版本: $version"

    local url="https://github.com/${GITHUB_REPO}/releases/download/${version}/Vessel-${version#v}-x86_64.AppImage"
    local tmp_appimage="/tmp/Vessel-${version#v}-x86_64.AppImage"

    echo -n "  下载 ${version} ... "
    if curl -L --progress-bar -o "$tmp_appimage" "$url" 2>&1; then
        good "✅"
    else
        bad "❌ 下载失败"
        warn "  手动: $url"
        return 1
    fi

    local size=$(stat -c%s "$tmp_appimage" 2>/dev/null || echo 0)
    if [ "$size" -lt 10000000 ]; then
        bad "  ❌ 下载文件异常小 ($size bytes)"
        return 1
    fi

    echo -n "  安装 ... "
    mkdir -p "$VESSEL_DIR" "$HOME/.local/bin"

    # 尝试直接运行 AppImage（如果 libfuse2 已安装）
    if ldconfig -p 2>/dev/null | grep -q libfuse; then
        cp "$tmp_appimage" "$VESSEL_BIN"
        chmod +x "$VESSEL_BIN"
        good "✅ (AppImage)"
    else
        # 提取 AppImage
        cd "$VESSEL_DIR"
        "$tmp_appimage" --appimage-extract 2>&1 | tail -1
        chmod +x "$VESSEL_DIR/squashfs-root/vessel"
        # 创建 wrapper
        cat > "$VESSEL_BIN" << 'WRAPPER'
#!/bin/bash
exec "$HOME/.local/lib/vessel/squashfs-root/vessel" --no-sandbox "$@"
WRAPPER
        chmod +x "$VESSEL_BIN"
        good "✅ (extracted)"
    fi

    rm -f "$tmp_appimage"
    echo -e "  ${GRAY}二进制: $VESSEL_BIN${NC}"
}

# ========== 启动 Vessel ==========
start_vessel() {
    echo -e "${CYAN}── 启动 Vessel ──${NC}"
    if pgrep -f "squashfs-root/vessel|vessel.*AppImage" > /dev/null 2>&1; then
        good "  ✓ 已在运行"
        return 0
    fi
    echo -n "  启动中 ... "
    $VESSEL_BIN &
    sleep 3
    if pgrep -f "squashfs-root/vessel|vessel.*AppImage" > /dev/null 2>&1; then
        good "✅"
    else
        bad "❌ 启动失败"
        return 1
    fi
}

# ========== 配置 MCP ==========
configure_mcp() {
    echo -e "${CYAN}── 配置 MCP ──${NC}"

    # 检查 Vessel 是否运行
    if ! pgrep -f "squashfs-root/vessel|vessel.*AppImage" > /dev/null 2>&1; then
        warn "  Vessel 未运行，正在启动..."
        start_vessel || return 1
    fi

    # 从标准路径自动读取 token（~/.config/vessel/mcp-auth.json）
    local auth_file="$HOME/.config/vessel/mcp-auth.json"
    if [ -f "$auth_file" ]; then
        local token=$(python3 -c "import json; print(json.load(open('$auth_file'))['token'])" 2>/dev/null)
        if [ -n "$token" ]; then
            echo -n "  Token (自动读取 $auth_file) ... "
            good "✅ ${token:0:16}..."
            register_mcp "$token"
            return 0
        fi
    fi

    # 检查 MCP 端点
    echo -n "  MCP 端点 (localhost:${MCP_PORT}) ... "
    local resp=$(curl -s --max-time 3 "http://localhost:${MCP_PORT}/mcp" 2>/dev/null || echo "")
    if echo "$resp" | grep -q "Unauthorized\|bearer"; then
        good "✅ 已响应"
    else
        warn "○ 未响应"
        return 1
    fi

    echo ""
    echo -e "  ${RED}Token 文件不存在: $auth_file${NC}"
    echo -e "  ${GRAY}手动注册: bash ccconfig/option-vessel/init.sh --mcp-token <token>${NC}"
}

register_mcp() {
    local token="$1"
    if [ -z "$token" ]; then
        bad "❌ 需要提供 token: bash ccconfig/option-vessel/init.sh --mcp-token <token>"
        return 1
    fi

    echo -e "${CYAN}── 注册 Vessel MCP ──${NC}"

    # 先删除旧配置
    claude mcp remove vessel 2>/dev/null || true

    echo -n "  注册到 Claude Code ... "
    if claude mcp add --transport http --scope user vessel "http://127.0.0.1:${MCP_PORT}/mcp" \
        --header "Authorization: Bearer ${token}" 2>&1; then
        good "✅ MCP 已注册"
    else
        bad "❌ 注册失败"
        return 1
    fi
}

# ========== 状态检查 ==========
show_status() {
    echo -e "${CYAN}── Vessel 状态 ──${NC}"

    echo -n "  二进制 ... "
    if [ -x "$VESSEL_BIN" ] || [ -f "$VESSEL_DIR/squashfs-root/vessel" ]; then
        good "✅ 已安装"
    else
        bad "❌ 未安装"
    fi

    echo -n "  进程 ... "
    if pgrep -f "squashfs-root/vessel|vessel.*AppImage" > /dev/null 2>&1; then
        local pid=$(pgrep -f "squashfs-root/vessel|vessel" | head -1)
        good "✅ 运行中 (PID: $pid)"
    else
        warn "○ 未运行"
    fi

    echo -n "  MCP (端口 ${MCP_PORT}) ... "
    if curl -s --max-time 2 "http://localhost:${MCP_PORT}/mcp" 2>/dev/null | grep -q "Unauthorized\|bearer\|json"; then
        good "✅ 已监听"
    else
        warn "○ 未监听"
    fi

    # 检查 MCP 注册（.config.json 是 /mcp 对话框读取的文件）
    echo -n "  MCP 注册 ... "
    if grep -q '"vessel"' "$HOME/.claude/.config.json" 2>/dev/null; then
        good "✅ 已注册"
    else
        warn "○ 未注册"
    fi

    echo ""
}

# ========== 交互式 ==========
interactive_mode() {
    banner
    detect_env || exit 1
    echo ""

    echo -e "${BOLD}Vessel${NC} — AI Agent 浏览器，Claude Code 通过 MCP 操控"
    echo -e "  ${GRAY}打开网页、点击、填表、提取内容，所有操作人类可见可审批${NC}"
    echo ""
    echo "  ┌─ 安装内容 ─────────────────────────────┐"
    echo "  │ • 系统依赖: libnspr4 libnss3 libasound2t64 │"
    echo "  │ • Vessel AppImage（~121MB）               │"
    echo "  │ • MCP 注册到 Claude Code                 │"
    echo "  └─────────────────────────────────────────┘"
    echo ""

    read -p "  安装 Vessel? [Y/n]: " confirm
    confirm="${confirm:-y}"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "  跳过"
        return 0
    fi

    echo ""
    install_deps
    install_vessel
    echo ""

    # 询问是否启动
    read -p "  启动 Vessel 并配置 MCP? [Y/n]: " start_confirm
    start_confirm="${start_confirm:-y}"
    if [[ "$start_confirm" =~ ^[Yy]$ ]]; then
        start_vessel
        configure_mcp
    fi

    echo ""
    good "✅ Vessel 安装完成"
    echo ""
    echo "后续操作:"
    echo "  启动:        vessel &"
    echo "  MCP token:   在 Settings (Ctrl+,) 查看"
    echo "  注册 MCP:    bash ccconfig/option-vessel/init.sh --mcp-token <token>"
    echo "  状态检查:    bash ccconfig/option-vessel/init.sh --status"
}

# ========== 主程序 ==========
main() {
    case "${1:-}" in
        --install|-i)
            detect_env
            install_deps
            install_vessel
            echo ""
            good "✅ Vessel 安装完成"
            ;;
        --mcp|-m)
            configure_mcp
            ;;
        --mcp-token)
            register_mcp "$2"
            ;;
        --status|-s)
            show_status
            ;;
        --start)
            start_vessel
            ;;
        --help|-h)
            echo "用法: $0 [--install|--mcp|--mcp-token <token>|--status|--start]"
            echo ""
            echo "  (无参数)        交互式模式（推荐）"
            echo "  --install       仅安装 Vessel"
            echo "  --mcp           配置 MCP（引导获取 token）"
            echo "  --mcp-token <t> 使用指定 token 注册 MCP"
            echo "  --status        状态检查"
            echo "  --start         启动 Vessel"
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

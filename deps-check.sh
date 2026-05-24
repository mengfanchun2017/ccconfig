#!/bin/bash
# deps-check.sh — ccconfig 依赖完整性检查
#
# 检查所有脚本依赖的工具和包，输出清晰状态表。
# 被 status.sh 调用，也可独立运行。
#
# 用法:
#   bash ccconfig/deps-check.sh            # 全量检查
#   bash ccconfig/deps-check.sh --required  # 仅必需依赖
#   bash ccconfig/deps-check.sh --json      # JSON 输出（供程序消费）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/path-helper.sh" 2>/dev/null || true

export PATH="$HOME/.local/bin:$(find_node_bin 2>/dev/null || echo ""):$PATH"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; GRAY='\033[0;90m'; NC='\033[0m'

MISSING=0
WARNINGS=0
JSON_OUT=false
REQUIRED_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --json) JSON_OUT=true ;;
        --required) REQUIRED_ONLY=true ;;
    esac
done

# ========== 依赖定义 ==========

# 必需依赖：缺少则核心功能不可用
REQUIRED_DEPS=(
    "git|git --version|git|Git 版本控制"
    "bash|bash --version|bash|Bash shell"
    "curl|curl --version|curl|HTTP 客户端"
)

# 核心依赖：脚本直接调用
CORE_DEPS=(
    "node|node --version|node|Node.js 运行时"
    "python3|python3 --version|python3|Python 3 运行时"
    "pip3|pip3 --version|pip3|Python 包管理"
    "npm|npm --version|npm|Node 包管理"
)

# 功能依赖：特定脚本使用
FEATURE_DEPS=(
    "gh|gh --version|gh|GitHub CLI (update.sh, monitor.sh)"
    "claude|claude --version|claude|Claude Code CLI"
    "inotifywait|inotifywait --help|inotify-tools|文件监控 (monitor.sh)"
    "systemctl|systemctl --version|systemd|服务管理 (init-autostart.sh)"
    "tmux|tmux -V|tmux|终端复用 (remote/)"
    "ssh|ssh -V 2>&1|openssh-client|SSH 远程连接"
    "uv|uv --version|uv|Python 包管理器"
)

# 可选依赖：option-* 组件使用
OPTIONAL_DEPS=(
    "lark-cli|lark-cli --version|lark-cli|飞书 CLI (option-bridge)"
    "cc-connect|cc-connect --version 2>/dev/null|cc-connect|飞书 Bridge (option-bridge)"
    "officecli|officecli --version 2>/dev/null|officecli|OfficeCLI (option-officecli)"
)

# Python 包
PYTHON_PACKAGES=(
    "pptx|python-pptx|PPT 生成 (option-ppt-master)"
    "cairosvg|cairosvg|SVG 转换 (option-ppt-master)"
    "lxml|lxml|XML 解析"
    "PIL|pillow|图片处理"
)

# npm 全局包
NPM_PACKAGES=(
    "@larksuite/cli|lark-cli 飞书 CLI"
    "@anthropic-ai/claude-code|Claude Code"
)

# ========== 检查函数 ==========

check_cmd() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        return 0
    fi
    # 某些命令不是独立二进制（如 pip3、systemctl）
    type "$cmd" &>/dev/null 2>&1
}

get_version() {
    local extract="$1"
    eval "$extract" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "?"
}

check_dep() {
    local def="$1"
    local required="$2"

    IFS='|' read -r bin extract_cmd label desc <<< "$def"

    local status="OK"
    local version=""
    local color="$GREEN"
    local symbol="✅"

    if check_cmd "$bin"; then
        version=$(get_version "$extract_cmd")
        [ -z "$version" ] && version="已安装"
    else
        if [ "$required" = "true" ]; then
            status="MISSING"
            color="$RED"
            symbol="❌"
            MISSING=$((MISSING + 1))
        else
            status="未安装"
            color="$YELLOW"
            symbol="○"
            WARNINGS=$((WARNINGS + 1))
        fi
        version="-"
    fi

    if $JSON_OUT; then
        echo "{\"name\":\"$label\",\"bin\":\"$bin\",\"status\":\"$status\",\"version\":\"$version\",\"desc\":\"$desc\"},"
    else
        printf "  %b %-18s %-16s %b%s%b\n" "$symbol" "$label" "$version" "$GRAY" "$desc" "$NC"
    fi
}

check_python_pkg() {
    local def="$1"
    IFS='|' read -r import_name pkg_label desc <<< "$def"

    local status="OK"
    local version="-"
    local color="$GREEN"
    local symbol="✅"

    if python3 -c "import $import_name" 2>/dev/null; then
        version=$(python3 -c "import $import_name; print(getattr($import_name, '__version__', '已安装'))" 2>/dev/null || echo "已安装")
    else
        status="未安装"
        color="$YELLOW"
        symbol="○"
        WARNINGS=$((WARNINGS + 1))
    fi

    if $JSON_OUT; then
        echo "{\"name\":\"$pkg_label\",\"type\":\"python\",\"status\":\"$status\",\"version\":\"$version\",\"desc\":\"$desc\"},"
    else
        printf "  %b %-18s %-16s %s%b\n" "$symbol" "$pkg_label" "$version" "$GRAY" "$desc" "$NC"
    fi
}

check_network() {
    local target="$1"
    local label="$2"
    if curl -s --connect-timeout 3 --max-time 5 "$target" >/dev/null 2>&1; then
        if $JSON_OUT; then
            echo "{\"name\":\"$label\",\"status\":\"OK\"},"
        else
            printf "  %b %-18s %s%b\n" "✅" "$label" "${GRAY}可达${NC}"
        fi
    else
        MISSING=$((MISSING + 1))
        if $JSON_OUT; then
            echo "{\"name\":\"$label\",\"status\":\"不可达\"},"
        else
            printf "  %b %-18s %s%b\n" "❌" "$label" "${RED}不可达${NC}"
        fi
    fi
}

# ========== 主程序 ==========

if $JSON_OUT; then
    echo "["
fi

# 必需
if ! $REQUIRED_ONLY; then
    echo -e "${CYAN}── 必需依赖 ──${NC}"
fi
for dep in "${REQUIRED_DEPS[@]}"; do
    check_dep "$dep" "true"
done

# 核心
if ! $REQUIRED_ONLY; then
    echo ""
    echo -e "${CYAN}── 核心依赖 ──${NC}"
fi
for dep in "${CORE_DEPS[@]}"; do
    check_dep "$dep" "true"
done

if ! $REQUIRED_ONLY; then
    # 功能
    echo ""
    echo -e "${CYAN}── 功能依赖 ──${NC}"
    for dep in "${FEATURE_DEPS[@]}"; do
        check_dep "$dep" "false"
    done

    # 可选
    echo ""
    echo -e "${CYAN}── 可选依赖 ──${NC}"
    for dep in "${OPTIONAL_DEPS[@]}"; do
        check_dep "$dep" "false"
    done

    # Python 包
    echo ""
    echo -e "${CYAN}── Python 包 ──${NC}"
    for pkg in "${PYTHON_PACKAGES[@]}"; do
        check_python_pkg "$pkg"
    done

    # 网络连通性
    echo ""
    echo -e "${CYAN}── 网络连通性 ──${NC}"
    check_network "https://github.com" "GitHub"
    check_network "https://registry.npmjs.org" "npm registry"
    check_network "https://pypi.org" "PyPI"
fi

if $JSON_OUT; then
    echo "{}]"
else
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ $MISSING -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "  ${GREEN}✅ 所有依赖完整${NC}"
    else
        if [ $MISSING -gt 0 ]; then
            echo -e "  ${RED}❌ $MISSING 个依赖缺失${NC}"
        fi
        if [ $WARNINGS -gt 0 ]; then
            echo -e "  ${YELLOW}○ $WARNINGS 个可选依赖未安装${NC}"
        fi
        echo ""
        echo -e "  ${GRAY}修复: bash ccconfig/init-ubuntu.sh${NC}"
    fi
    echo ""
fi

[ $MISSING -eq 0 ] || exit 1

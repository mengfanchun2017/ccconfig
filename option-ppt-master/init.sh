#!/bin/bash
# ccconfig/option-ppt-master/init.sh — PPT 生成环境初始化（可选组件）
#
# 安装 hugohe3/ppt-master（⭐12.9k）PPT 生成引擎 + Python 依赖。
# ppt-master 将 SVG 模板转为原生可编辑 DrawingML PPTX（非 PNG 光栅），
# 支持 22 种模板、演讲者备注、转场动画。
#
# 用法：
#   bash ccconfig/option-ppt-master/init.sh              # 交互式（推荐）
#   bash ccconfig/option-ppt-master/init.sh --install    # 仅安装
#   bash ccconfig/option-ppt-master/init.sh --status     # 状态检查
#   bash ccconfig/option-ppt-master/init.sh --update     # 更新

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

PPT_DIR="$HOME/git/_ext/ppt-master"
GITHUB_REPO="hugohe3/ppt-master"

banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║     ppt-master — PPT 生成引擎（可选组件）        ║"
    echo "║     SVG → DrawingML 原生可编辑 PPTX              ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"
}

# ========== 安装 pip ==========
ensure_pip() {
    if python3 -m pip --version &>/dev/null; then
        return 0
    fi
    echo -n "  安装 pip ... "
    curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
    python3 /tmp/get-pip.py --break-system-packages 2>&1 | tail -1
    rm -f /tmp/get-pip.py
    if python3 -m pip --version &>/dev/null; then
        good "✅"
    else
        bad "❌"
        return 1
    fi
}

# ========== 安装 Python 依赖 ==========
install_python_deps() {
    echo -e "${CYAN}── Python 依赖 ──${NC}"

    local missing=""
    python3 -c "import pptx" 2>/dev/null || missing="$missing python-pptx"
    python3 -c "import cairosvg" 2>/dev/null || missing="$missing cairosvg"
    python3 -c "import lxml" 2>/dev/null || missing="$missing lxml"

    if [[ -z "$missing" ]]; then
        local pptx_ver=$(python3 -c "import pptx; print(pptx.__version__)" 2>/dev/null)
        echo -n "  python-pptx ... "
        good "✅ $pptx_ver"
        echo -n "  cairosvg ... "
        good "✅"
        echo -n "  lxml ... "
        good "✅"
        return 0
    fi

    echo "  安装:$missing"
    python3 -m pip install $missing --break-system-packages 2>&1 | tail -3
    echo -n "  验证 ... "
    local fail=""
    python3 -c "import pptx" 2>/dev/null || fail="$fail python-pptx"
    python3 -c "import cairosvg" 2>/dev/null || fail="$fail cairosvg"
    python3 -c "import lxml" 2>/dev/null || fail="$fail lxml"
    if [[ -z "$fail" ]]; then
        good "✅"
    else
        bad "❌ 安装失败:$fail"
        return 1
    fi
}

# ========== 克隆/更新 ppt-master ==========
install_ppt_master() {
    echo -e "${CYAN}── ppt-master 仓库 ──${NC}"

    if [[ -d "$PPT_DIR/.git" ]]; then
        echo -n "  仓库 ... "
        good "✅ 已克隆"
        return 0
    fi

    echo -n "  克隆 $GITHUB_REPO ... "
    mkdir -p "$HOME/git/_ext"
    local log="/tmp/ppt-master-clone.log"

    # 先尝试 SSH，失败时自动尝试 HTTPS
    if git clone "git@github.com:${GITHUB_REPO}.git" "$PPT_DIR" >"$log" 2>&1; then
        good "✅ (SSH)"
    elif git clone "https://github.com/${GITHUB_REPO}.git" "$PPT_DIR" >"$log" 2>&1; then
        good "✅ (HTTPS)"
    else
        bad "❌ 克隆失败"
        info "  日志: $log"
        cat "$log" | tail -5
        return 1
    fi
    rm -f "$log"
}

# ========== 更新 ==========
update_ppt_master() {
    echo -e "${CYAN}── 更新 ppt-master ──${NC}"

    if [[ ! -d "$PPT_DIR/.git" ]]; then
        warn "  ppt-master 未安装，请先运行 --install"
        return 1
    fi

    local local_c=$(git -C "$PPT_DIR" rev-parse --short HEAD)
    git -C "$PPT_DIR" fetch origin main 2>/dev/null || true
    local remote_c=$(git -C "$PPT_DIR" rev-parse --short origin/main)

    if [[ "$local_c" != "$remote_c" ]]; then
        echo -n "  更新 $local_c → $remote_c ... "
        git -C "$PPT_DIR" pull --ff-only origin main 2>&1 | tail -2
        good "✅"
    else
        info "  已是最新: $local_c"
    fi

    # 检查 Python 依赖是否有新增
    install_python_deps
}

# ========== 状态检查 ==========
show_status() {
    echo -e "${CYAN}── ppt-master 状态 ──${NC}"

    echo -n "  仓库 ... "
    if [[ -d "$PPT_DIR/.git" ]]; then
        cd "$PPT_DIR"
        local commit=$(git rev-parse --short HEAD 2>/dev/null)
        good "✅ $commit"
    else
        bad "❌ 未克隆 ($PPT_DIR)"
    fi

    echo -n "  python-pptx ... "
    if python3 -c "import pptx" 2>/dev/null; then
        local ver=$(python3 -c "import pptx; print(pptx.__version__)" 2>/dev/null)
        good "✅ $ver"
    else
        bad "❌ 未安装"
    fi

    echo -n "  cairosvg ... "
    python3 -c "import cairosvg" 2>/dev/null && good "✅" || bad "❌ 未安装"

    echo -n "  lxml ... "
    python3 -c "import lxml" 2>/dev/null && good "✅" || bad "❌ 未安装"

    # 检查模板
    echo -n "  模板 ... "
    local template_dir="$PPT_DIR/skills/ppt-master/templates/layouts"
    if [[ -d "$template_dir" ]]; then
        local count=$(ls "$template_dir" 2>/dev/null | wc -l)
        good "✅ $count 个模板"
    else
        warn "○ 模板目录不存在"
    fi

    echo ""
}

# ========== 交互式 ==========
interactive_mode() {
    banner
    echo ""

    show_status
    echo ""

    echo -e "${BOLD}ppt-master${NC} — SVG → DrawingML PPTX，22 种模板"
    echo -e "  ${GRAY}配合 unified-ppt skill 使用，从 md/wiki 生成飞书 PPT${NC}"
    echo ""
    echo "  ┌─ 安装内容 ─────────────────────────────┐"
    echo "  │ • python-pptx + cairosvg + lxml          │"
    echo "  │ • hugohe3/ppt-master 仓库                │"
    echo "  │ • 22 种 PPT 模板（mckinsey/anthropic/...）│"
    echo "  └─────────────────────────────────────────┘"
    echo ""

    local need_install=false
    [[ -d "$PPT_DIR/.git" ]] || need_install=true
    python3 -c "import pptx" 2>/dev/null || need_install=true
    python3 -c "import cairosvg" 2>/dev/null || need_install=true

    if $need_install; then
        read -p "  安装 ppt-master? [Y/n]: " confirm
        confirm="${confirm:-y}"
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "  跳过"
            return 0
        fi
        echo ""
        ensure_pip
        install_python_deps
        install_ppt_master
    else
        good "  所有组件已就绪"
        echo ""
        read -p "  更新 ppt-master? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            update_ppt_master
        fi
    fi

    echo ""
    good "✅ ppt-master 就绪"
    echo ""
    echo "后续操作:"
    echo "  生成 PPT:   使用 unified-ppt skill"
    echo "  状态检查:   bash ccconfig/option-ppt-master/init.sh --status"
    echo "  更新:       bash ccconfig/option-ppt-master/init.sh --update"
}

# ========== 主程序 ==========
main() {
    case "${1:-}" in
        --install|-i)
            ensure_pip
            install_python_deps
            install_ppt_master
            echo ""
            good "✅ ppt-master 安装完成"
            ;;
        --update|-u)
            update_ppt_master
            ;;
        --status|-s)
            show_status
            ;;
        --deps-only)
            ensure_pip
            install_python_deps
            ;;
        --help|-h)
            echo "用法: $0 [--install|--update|--status|--deps-only]"
            echo ""
            echo "  (无参数)        交互式模式（推荐）"
            echo "  --install       安装所有依赖 + 克隆仓库"
            echo "  --deps-only     仅安装 Python 依赖"
            echo "  --update        更新仓库到最新"
            echo "  --status        状态检查"
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

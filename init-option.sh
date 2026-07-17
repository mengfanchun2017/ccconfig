#!/bin/bash
# init-option.sh — 可选组件统一安装入口
#
# 用法：
#   bash init-option.sh                  # 交互式菜单
#   bash init-option.sh --status         # 列出所有 option 及安装状态
#   bash init-option.sh <name>           # 安装指定 option
#   bash init-option.sh all              # 安装所有 option
#
# 发现: 自动扫描 option-*/init.sh，内置 CLI tool 选项（bat/glow/nano）
# 设计: 每个 option 的 init.sh 必须支持 --status（输出 OK/FAIL + 描述）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/colors.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; GRAY='\033[0;90m'; NC='\033[0m'
}

info()    { echo -e "  ${GRAY}$1${NC}"; }
ok()      { echo -e "  ${GREEN}✅ $1${NC}"; }
warn()    { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
err()     { echo -e "  ${RED}❌ $1${NC}"; }
section() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ── 内置 CLI 选项（轻量，不建 option-* 目录） ──
declare -A CLI_OPTIONS
CLI_OPTIONS["bat"]="bat 安装 + alias cat=bat"
CLI_OPTIONS["glow"]="glow Markdown 阅读器"
CLI_OPTIONS["nano"]="nano 文本编辑器"

# ── 检测 option-* 目录 ──
list_option_dirs() {
    local dirs=()
    for d in "$SCRIPT_DIR"/option-*/; do
        [ -d "$d" ] || continue
        dirs+=("$(basename "$d")")
    done
    echo "${dirs[@]}"
}

has_init_script() {
    [ -f "$SCRIPT_DIR/option-$1/init.sh" ]
}

# ── 安装单个 option ──
install_option() {
    local name="$1"
    shift

    # option-* 目录
    if has_init_script "$name"; then
        section "安装 $name"
        bash "$SCRIPT_DIR/option-$name/init.sh" "$@"
        return $?
    fi

    # 内置 CLI 选项
    case "$name" in
        bat)
            install_bat
            ;;
        glow)
            install_glow
            ;;
        nano)
            install_nano
            ;;
        *)
            err "未知选项: $name"
            return 1
            ;;
    esac
}

# ── CLI 工具安装函数 ──
install_bat() {
    section "bat 安装 + alias cat=bat"

    if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
        ok "bat 已安装"
    else
        info "安装 bat..."
        if command -v sudo &>/dev/null; then
            sudo apt-get install -y bat 2>/dev/null || {
                warn "apt 安装失败，尝试下载二进制..."
                local bv
                bv=$(curl -fsSL "https://api.github.com/repos/sharkdp/bat/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4 | tr -d 'v')
                bv="${bv:-0.24.0}"
                curl -fsSL "https://github.com/sharkdp/bat/releases/download/v${bv}/bat_${bv}_amd64.deb" -o /tmp/bat.deb
                sudo dpkg -i /tmp/bat.deb 2>/dev/null || sudo apt-get install -f -y
                rm -f /tmp/bat.deb
            }
        else
            err "需要 sudo 才能安装 bat"
            return 1
        fi
    fi

    # alias cat=bat
    local alias_file="$HOME/.claude/shell_aliases.sh"
    if [ -f "$alias_file" ] && ! grep -q "alias cat=bat" "$alias_file" 2>/dev/null; then
        echo -e "\n# bat: cat 替代\nif command -v batcat &>/dev/null; then\n    alias cat=batcat\nelif command -v bat &>/dev/null; then\n    alias cat=bat\nfi" >> "$alias_file"
        ok "alias cat=bat 已写入 shell_aliases.sh"
    elif grep -q "alias cat=bat" "$alias_file" 2>/dev/null; then
        ok "alias cat=bat 已存在"
    fi

    ok "bat 就绪"
}

install_glow() {
    section "glow Markdown 阅读器"

    if command -v glow &>/dev/null; then
        ok "glow 已安装: $(glow --version 2>/dev/null | head -1)"
        return 0
    fi

    info "安装 glow..."
    if command -v sudo &>/dev/null; then
        # 优先 apt
        sudo apt-get install -y glow 2>/dev/null || {
            warn "apt 无 glow 包，下载二进制..."
            local gv
            gv=$(curl -fsSL "https://api.github.com/repos/charmbracelet/glow/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4 | tr -d 'v')
            gv="${gv:-2.1.0}"
            curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v${gv}/glow_${gv}_linux_amd64.deb" -o /tmp/glow.deb
            sudo dpkg -i /tmp/glow.deb 2>/dev/null || sudo apt-get install -f -y
            rm -f /tmp/glow.deb
        }
    else
        err "需要 sudo 才能安装 glow"
        return 1
    fi

    if command -v glow &>/dev/null; then
        ok "glow 已安装: $(glow --version 2>/dev/null | head -1)"
    else
        err "glow 安装失败"
    fi
}

install_nano() {
    section "nano 文本编辑器"

    if command -v nano &>/dev/null; then
        ok "nano 已安装: $(nano --version 2>/dev/null | head -1)"
        return 0
    fi

    info "安装 nano..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y nano
    else
        err "无法安装 nano（非 apt 系统）"
        return 1
    fi

    if command -v nano &>/dev/null; then
        ok "nano 已安装"
    fi
}

# ── 状态查询 ──
option_status() {
    local name="$1"

    # option-* 目录（取首个含文字的行，跳过纯ANSI行）
    if has_init_script "$name"; then
        bash "$SCRIPT_DIR/option-$name/init.sh" --status 2>&1 | grep -m1 -E '[a-zA-Z]{2}'
        return 0
    fi

    # 内置 CLI
    case "$name" in
        bat)
            if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
                echo -e "${GREEN}✅${NC} bat 已安装"
            else
                echo -e "${GRAY}－${NC} bat 未安装"
            fi
            ;;
        glow)
            if command -v glow &>/dev/null; then
                echo -e "${GREEN}✅${NC} glow 已安装"
            else
                echo -e "${GRAY}－${NC} glow 未安装"
            fi
            ;;
        nano)
            if command -v nano &>/dev/null; then
                echo -e "${GREEN}✅${NC} nano 已安装"
            else
                echo -e "${GRAY}－${NC} nano 未安装"
            fi
            ;;
        *)
            echo -e "${GRAY}－${NC} 未知"
            ;;
    esac
}

# ── 列出所有 option（内置 + option-*） ──
list_all() {
    echo ""
    echo -e "${CYAN}可选组件状态${NC}"
    echo ""

    # 选项索引
    local idx=1
    local -a all_names all_labels

    # 内置 CLI 工具
    for name in bat glow nano; do
        all_names+=("$name")
        all_labels+=("${CLI_OPTIONS[$name]}")
        printf "  %2d) %-12s %b\n" $idx "$name" "$(option_status "$name")"
        idx=$((idx + 1))
    done

    # option-* 目录（去掉 option- 前缀再存储，option_status 内部重新加）
    local dirs
    dirs=$(list_option_dirs)
    for d in $dirs; do
        local bare="${d#option-}"
        all_names+=("$bare")
        all_labels+=("$bare")
        printf "  %2d) %-12s %b\n" $idx "$bare" "$(option_status "$bare")"
        idx=$((idx + 1))
    done

    echo -e "\n  0) 返回"
    echo ""
}

# ── 交互菜单 ──
interactive_menu() {
    echo -e "${CYAN}Claude Code 可选组件安装${NC}"

    # 收集所有选项
    local -a all_names
    for n in bat glow nano; do all_names+=("$n"); done
    local dirs
    dirs=$(list_option_dirs)
    for d in $dirs; do all_names+=("${d#option-}"); done

    while true; do
        list_all
        read -p "选择安装 (1-${#all_names[@]}, 输入 a 安装全部, 0 退出): " choice

        case "$choice" in
            0|q|exit) echo ""; exit 0 ;;
            a|all)
                for n in "${all_names[@]}"; do
                    install_option "$n"
                done
                echo ""
                echo -e "${GREEN}✅ 全部安装完成${NC}"
                echo ""
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#all_names[@]} ]; then
                    install_option "${all_names[$((choice - 1))]}"
                else
                    warn "无效选择"
                    continue
                fi
                ;;
        esac

        echo ""
        read -p "操作完成，按回车继续..." dummy
    done
}

# ── 入口 ──
case "${1:-menu}" in
    --status|status|-s)
        list_all
        ;;
    -l|list)
        for n in bat glow nano; do echo "$n"; done
        for d in $(list_option_dirs); do echo "${d#option-}"; done
        ;;
    all|--all|-a)
        shift 2>/dev/null || true
        for n in bat glow nano; do install_option "$n"; done
        for d in $(list_option_dirs); do install_option "${d#option-}"; done
        echo -e "\n${GREEN}✅ 全部可选组件安装完成${NC}"
        ;;
    menu|--menu|"")
        interactive_menu
        ;;
    *)
        install_option "$@"
        ;;
esac

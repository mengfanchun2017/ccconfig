#!/bin/bash
# init-base.sh — ccconfig 初始化统一入口
#
# 使用：
#   bash init-base.sh                  # 交互式菜单（默认）
#   bash init-base.sh new              # 新机器：gh auth → ccprivate → 全量
#   bash init-base.sh all              # 一键全部（跳过认证，已有 ccprivate）
#   bash init-base.sh new --yes        # 全自动非交互
#   bash init-base.sh --dry-run        # 预览将要执行的操作（不实际执行）
#
# 全链：init-base.sh all → init-option（可选）→ maintain.sh（全量状态检查）
# 新机器：init-bootstrap.sh → init-base.sh all → init-option（可选）→ maintain.sh（全量状态检查）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/dry-run.sh"
source "$SCRIPT_DIR/lib/colors.sh"
source "$SCRIPT_DIR/lib/interact.sh"

show_banner() {
    echo -e "${CYAN}Claude Code 配置中枢 · ccconfig${NC}"
}

# 首次初始化检查：仅检查 ccprivate
check_prereqs() {
    if [[ -d "$HOME/git/ccprivate" ]]; then
        return 0
    fi

    # 自动化 / CI 旁路：不阻塞 read，直接 return 让上层 hard-exit 接管
    if [[ "${CCP_SKIP_PREREQ_PROMPT:-}" == "1" ]] || [[ "${INIT_ALL_FLOW:-}" == "1" ]]; then
        err "ccprivate 未找到，CI/自动模式终止"
        return 1
    fi

    echo ""
    echo -e "${YELLOW}━━━ 首次初始化引导 ━━━${NC}"
    echo ""
    echo -e "  ${RED}❌${NC} ccprivate 未找到 — 私有配置（API Key、CLAUDE.md、settings.json）"
    echo -e "     ${CYAN}→${NC} bash ccconfig/init-bootstrap.sh"
    echo ""
    echo -e "  ${GRAY}（完整流程：clone → init-bootstrap.sh → init-base.sh all → init-option（可选）→ maintain.sh status）${NC}"
    echo ""

    if confirm "现在创建 ccprivate？" y; then
        echo -e "  ${GRAY}请执行: bash ccconfig/init-bootstrap.sh${NC}"
        echo -e "  ${YELLOW}创建完成后重新运行 bash init-base.sh${NC}"
        exit 0
    fi

    return 0
}

# 一键全部初始化。假定 ccprivate 已存在。
init_all_steps() {
    show_banner
    export INIT_ALL_FLOW=1

    # 预检：确保 ccprivate 配置已就绪
    local ccpriv="${CCPRIVATE_HOME:-$HOME/git/ccprivate}"
    if [[ ! -d "$ccpriv" ]]; then
        err "ccprivate 未找到，请先: bash init-bootstrap.sh"
        exit 1
    fi

    # 配置预检：缺失的配置从 .example 复制（全自动，不交互）
    local configs=("llm.json" "mcp-servers.json")
    local missing_configs=()
    for name in "${configs[@]}"; do
        if [[ -f "$ccpriv/conf/$name" ]]; then
            continue
        fi
        local example="$CCCONFIG_ROOT/conf/$name.example"
        if [[ -f "$example" ]]; then
            mkdir -p "$ccpriv/conf"
            cp "$example" "$ccpriv/conf/$name"
            missing_configs+=("$name")
        fi
    done

    if [[ ${#missing_configs[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}━━━ 配置文件已从模板创建（到 ccprivate/conf/）━━━${NC}"
        echo ""
        for name in "${missing_configs[@]}"; do
            echo -e "  ${GRAY}→${NC} $name"
        done
        echo ""

        echo -e "  ${GRAY}📝 配置文件已创建，请手动编辑填入 API Key：${NC}"
        for name in "${missing_configs[@]}"; do
            echo "     vim $ccpriv/conf/$name"
        done
        echo ""
        echo -e "  ${GREEN}继续执行全部初始化步骤...${NC}"
    fi

    # 读取 llm.json 中预设的 current
    local llm_json="$ccpriv/conf/llm.json"
    local current_llm
    current_llm=$(python3 -c "import json; print(json.load(open('$llm_json')).get('current',''))" 2>/dev/null || echo "")
    export INIT_LLM_NAME="$current_llm"

    run_step "Ubuntu 环境" "$SCRIPT_DIR/lib/init-ubuntu.sh" true         \
        "装 Node / Claude Code / 建符号链接 / 启动 auto-sync"         \
        "3 min（含 apt 下载）"

    run_step "LLM 配置" "$SCRIPT_DIR/lib/init-llm.sh" true         \
        "把当前 LLM 的 API key 写入 ~/.claude/settings.json"         \
        "10 s"

    # 私有链接收尾：auto-sync 已由 init-ubuntu.sh 启动，maintain 留给用户手动跑
    run_step "收尾（私有链接）" "$ccpriv/setup.sh" true         \
        "ccprivate 私有链接（CLAUDE.md / MEMORY.md / settings.json 等 symlink）"         \
        "10 s"
    echo -e "${GREEN}🎉 基础初始化完成${NC}"
    echo ""

    export PATH="$HOME/.local/bin:$PATH"
    hash -r 2>/dev/null || true
    if command -v claude &>/dev/null; then
        echo -e "  ${GREEN}✅ claude 已可用${NC}"
    else
        echo -e "  ${YELLOW}⚠ 当前终端 claude 未生效（init 在子 shell 中运行）${NC}"
        echo -e "  ${GREEN}→ source ~/.bashrc${NC}  ${GRAY}或开新终端即可${NC}"
    fi
    echo -e "  ${CYAN}claudeby${NC} = claude --dangerously-skip-permissions（bypass 权限，跳分类器）"
    echo -e "  ${GRAY}日常用 claude（auto+allow 已覆盖 spawn agent），需跳权限用 claudeby${NC}"
    echo -e "  ${GRAY}claudeby 是 alias，当前终端需 source ~/.bashrc 或开新终端生效${NC}"
    echo ""

    echo -e "${BOLD}下一步:${NC}"
    echo -e "  ${CYAN}bash init-option.sh${NC}  # （可选）装附加组件：MCP / Skills / CLI"
    echo -e "  ${GREEN}bash maintain.sh${NC}     # 全量状态检查"
    echo -e "  ${GRAY}确认所有项通过后即可开始使用 Claude Code。${NC}"
    echo ""
    echo -e "${BOLD}日常使用:${NC}"
    echo "  切换 LLM:          bash $SCRIPT_DIR/lib/init-llm.sh"
    echo "  系统升级:          bash $SCRIPT_DIR/lib/update.sh all"
    echo "  状态检查:          bash maintain.sh status"
    echo "  补装组件:          bash init-option.sh"
    echo ""
}

run_step() {
    local label="$1" script="$2" auto="$3"
    local desc="${4:-}" eta="${5:-}"

    echo ""
    echo -e "${BOLD}${CYAN}▸ ${label}${NC}"
    if [[ -n "$desc" ]]; then
        echo -e "  ${GRAY}${desc}${NC}"
        [[ -n "$eta" ]] && echo -e "  ${GRAY}预计 ~${eta}${NC}"
    fi
    echo ""

    if [ "$auto" = "true" ]; then
        if bash "$script"; then
            ok "${label}"
        else
            warn "${label} 失败（继续）"
        fi
    else
        if confirm "运行？" y; then
            if bash "$script"; then
                ok "${label}"
            else
                err "${label} 失败"
            fi
        else
            echo -e "  ${YELLOW}跳过${NC}"
        fi
    fi
}

# ========== 子菜单 ==========

submenu_env() {
    echo ""; section "环境初始化"
    local c; c=$(menu_select "选择" \
        "Ubuntu 全环境初始化" "LLM 切换" "auto-sync" "★ 一键全部" "返回")
    [[ -z "$c" ]] && return
    case "$c" in
        "1") run_step "Ubuntu" "$SCRIPT_DIR/lib/init-ubuntu.sh" false; echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r < /dev/tty || true; exit 0 ;;
        "2") run_step "LLM" "$SCRIPT_DIR/lib/init-llm.sh" false; echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r < /dev/tty || true; exit 0 ;;
        "3") run_step "auto-sync" "$SCRIPT_DIR/lib/init-autostart.sh" false; echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r < /dev/tty || true; exit 0 ;;
        "4") init_all_steps; exit 0 ;;
        *) return ;;
    esac
}

submenu_remote() {
    echo ""; section "远程连接"
    local c; c=$(menu_select "选择" \
        "SSH Server + tmux" "部署到 Windows" "查看说明" "返回")
    [[ -z "$c" ]] && return
    case "$c" in
        "1") run_step "SSH Server" "$SCRIPT_DIR/option-remote/server/tmux-sshd.sh" false ;;
        "2") bash "$SCRIPT_DIR/option-remote/deploy.sh" server ;;
        "3") cat "$SCRIPT_DIR/option-remote/README.md" 2>/dev/null || warn "README.md 不存在" ;;
        *) return ;;
    esac
}

# ========== 主菜单 ==========
main_menu() {
    show_banner
    check_prereqs
    local choice
    while true; do
        choice=$(menu_select "ccconfig 初始化" \
            "Ubuntu 环境/LLM/自启动" \
            "远程连接/SSH/tmux" \
            "★ 新机第一步：gh auth + ccprivate" \
            "★ 已有 ccprivate：基础初始化 3 步" \
            "可选组件(MCP/Skills/CLI)" \
            "退出")
        case "$choice" in
            1) submenu_env ;;
            2) submenu_remote ;;
            3) bash "$0" new ;;
            4) init_all_steps; exit 0 ;;
            5) bash "$SCRIPT_DIR/init-option.sh" ;;
            0) echo ""; exit 0 ;;
        esac
        echo ""; read -p "按回车返回主菜单..." dummy < /dev/tty || true
    done
}

# ========== 入口 ==========
# BASH_SOURCE 守卫：被 source 时不执行入口（支持测试 source 调函数）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
case "${1:-menu}" in
    all)
        if [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]]; then
            export NONINTERACTIVE=true
        fi
        init_all_steps
        exit 0
        ;;
    new|bootstrap)
        # gh auth + ccprivate 一体化
        if [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]]; then
            export CCP_NONINTERACTIVE=1
        fi
        bash "$SCRIPT_DIR/init-bootstrap.sh" || exit 1
        # 成功后继续全量初始化
        exec bash "$0" all "${2:-}"
        ;;
    option|options)
        exec bash "$SCRIPT_DIR/init-option.sh" "${@:2}"
        ;;
    --dry-run|--preview|--what)
        show_banner
        echo ""
        echo -e "${CYAN}━━━ 预览：将要执行的操作 ━━━${NC}"
        echo "  init-ubuntu.sh  → 系统包 + node/claude + symlink"
        echo "  init-llm.sh       → 写入 ANTHROPIC_AUTH_TOKEN"
        echo "  maintain.sh setup → 链接 + auto-sync + 状态"
        echo ""
        echo "  运行 bash init-base.sh all [--yes]"
        ;;
    menu|"")
        main_menu
        ;;
    *)
        echo "用法: bash init-base.sh [new|all [--yes]|option|--dry-run|menu]"
        ;;
esac
fi

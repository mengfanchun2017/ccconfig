#!/bin/bash
# init-base.sh — ccconfig 初始化统一入口
#
# 使用：
#   bash init-base.sh                  # 交互式菜单（默认）
#   bash init-base.sh all              # 一键全部（跳过交互全自动）
#   bash init-base.sh --dry-run        # 预览将要执行的操作（不实际执行）
#
# 子命令输出指引让用户手动执行，不直接调其他根脚本。

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
        return 1
    fi

    echo ""
    echo -e "${YELLOW}━━━ 首次初始化引导 ━━━${NC}"
    echo ""
    echo -e "  ${RED}❌${NC} ccprivate 未找到 — 私有配置（API Key、CLAUDE.md、settings.json）"
    echo -e "     ${CYAN}→${NC} bash ccconfig/init-ccprivate-repo.sh"
    echo ""
    echo -e "  ${GRAY}（完整流程：clone → bootstrap-gh-auth.sh → init-ccprivate-repo.sh → init-base.sh all → 可选 init-option.sh/option-skill/init.sh → maintain.sh status）${NC}"
    echo ""

    if confirm "现在创建 ccprivate？" y; then
        echo -e "  ${GRAY}请执行: bash ccconfig/init-ccprivate-repo.sh${NC}"
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
        err "ccprivate 未找到，请先: bash init-ccprivate-repo.sh"
        exit 1
    fi

    # 配置预检：缺失的配置从 .example 复制（全自动，不交互）
    local configs=("ubuntu.json" "llm.json" "claude.json")
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

        # Git 信息：从 git config 自动读
        local git_user git_email
        git_user="$(git config --global user.name 2>/dev/null || echo '')"
        git_email="$(git config --global user.email 2>/dev/null || echo '')"
        if [[ -n "$git_user" ]] || [[ -n "$git_email" ]]; then
            python3 - "$ccpriv/conf/ubuntu.json" "$git_user" "$git_email" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    d = json.load(f)
if sys.argv[2]:
    d.setdefault('git', {})['username'] = sys.argv[2]
if sys.argv[3]:
    d.setdefault('git', {})['email'] = sys.argv[3]
with open(sys.argv[1], 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
PYEOF
            echo -e "  ${GREEN}✅${NC} Git 信息已从 git config 写入 ccprivate/conf/ubuntu.json"
        fi

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

    run_step "1/4 Ubuntu 环境" "$SCRIPT_DIR/lib/init-ubuntu.sh" true \
        "装 Node / Claude Code / uv / 建符号链接 / 启动 auto-sync / 注册 SessionStart hook" \
        "Claude Code 需要 Node 运行时；uv 装 Python 工具；auto-sync 让配置变更自动 push" \
        "3 min（含 apt 下载）"

    run_step "2/4 LLM 配置" "$SCRIPT_DIR/lib/init-llm.sh" true \
        "把当前 LLM 的 API key 写入 ~/.claude/settings.json" \
        "Claude Code 通过 ANTHROPIC_AUTH_TOKEN 调用 LLM；没配就跑不了" \
        "10 s"

    # 步骤 3/4: 收尾指引
    echo ""
    echo -e "${CYAN}━━━ 3/4 收尾 ━━━${NC}"
    echo -e "  ${GRAY}链接修复 + 启动 auto-sync 服务 + 状态验证${NC}"
    echo ""
    echo -e "  ${GREEN}✅ Ubuntu 环境 + LLM 配置完成${NC}"
    echo -e "  ${GRAY}请执行以下命令完成收尾:${NC}"
    echo -e "    ${CYAN}bash maintain.sh setup${NC}"
    echo ""

    echo -e "${GREEN}🎉 全部初始化完成${NC}"
    echo ""

    export PATH="$HOME/.local/bin:$PATH"
    hash -r 2>/dev/null || true
    if command -v claude &>/dev/null; then
        echo -e "  ${GREEN}✅ claude 已可用${NC}"
    else
        echo -e "  ${YELLOW}⚠ 当前终端 claude 未生效（init 在子 shell 中运行）${NC}"
        echo -e "  ${GREEN}→ source ~/.bashrc${NC}  ${GRAY}或开新终端即可${NC}"
    fi
    echo ""

    echo -e "${BOLD}日常使用:${NC}"
    echo "  切换 LLM:          bash $SCRIPT_DIR/lib/init-llm.sh"
    echo "  系统升级:          bash $SCRIPT_DIR/lib/update.sh all"
    echo "  状态检查:          bash maintain.sh status"
    echo "  装 Skills:         bash option-skill/init.sh --install"
    echo "  装 MCP/可选组件:    bash init-option.sh"
    echo ""
}

run_step() {
    local label="$1" script="$2" auto="$3"
    local what="${4:-}" why="${5:-}" eta="${6:-}"
    shift 6 2>/dev/null || true

    echo ""
    echo -e "${CYAN}━━━ ${label} ━━━${NC}"
    if [[ -n "$what" ]]; then
        echo -e "  ${GRAY}${what}${NC}"
        [[ -n "$eta" ]] && echo -e "  ${GRAY}预计 ~${eta}${NC}"
    fi
    echo ""

    if [ "$auto" = "true" ]; then
        if bash "$script" "$@"; then
            echo -e "${GREEN}✅ ${label} 完成${NC}"
        else
            echo -e "${RED}❌ ${label} 失败（继续）${NC}"
        fi
    else
        if confirm "运行？" y; then
            if bash "$script" "$@"; then
                echo -e "${GREEN}✅ ${label} 完成${NC}"
            else
                echo -e "${RED}❌ ${label} 失败${NC}"
            fi
        else
            echo -e "${YELLOW}跳过${NC}"
        fi
    fi
}

# ========== 子菜单 ==========

submenu_env() {
    echo ""; section "环境初始化"
    local c; c=$(menu_select "选择" \
        "1) Ubuntu 全环境初始化" "2) LLM 切换" "3) auto-sync" "4) ★ 一键全部" "0) 返回")
    [[ -z "$c" ]] && return
    case "${c:0:1}" in
        1) run_step "Ubuntu" "$SCRIPT_DIR/lib/init-ubuntu.sh" false; echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r < /dev/tty || true; exit 0 ;;
        2) run_step "LLM" "$SCRIPT_DIR/lib/init-llm.sh" false; echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r < /dev/tty || true; exit 0 ;;
        3) run_step "auto-sync" "$SCRIPT_DIR/lib/init-autostart.sh" false; echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r < /dev/tty || true; exit 0 ;;
        4) init_all_steps; exit 0 ;;
    esac
}

submenu_remote() {
    echo ""; section "远程连接"
    local c; c=$(menu_select "选择" \
        "1) SSH Server + tmux" "2) 部署到 Windows" "3) 查看说明" "0) 返回")
    [[ -z "$c" ]] && return
    case "${c:0:1}" in
        1) run_step "SSH Server" "$SCRIPT_DIR/option-remote/server/tmux-sshd.sh" false ;;
        2) bash "$SCRIPT_DIR/option-remote/deploy.sh" server ;;
        3) cat "$SCRIPT_DIR/option-remote/readme.md" 2>/dev/null || warn "readme.md 不存在" ;;
    esac
}

# ========== 主菜单 ==========
main_menu() {
    show_banner
    check_prereqs
    local choice; choice=$(menu_select "ccconfig 初始化" \
        "1) Ubuntu 环境/LLM/自启动" \
        "2) 远程连接/SSH/tmux" \
        "3) ★ 一键全部初始化" \
        "4) 可选组件(MCP/Skills/CLI)" \
        "0) 退出")
    [[ -z "$choice" ]] && { main_menu; return; }
    case "${choice:0:1}" in
        1) submenu_env ;;
        2) submenu_remote ;;
        3) init_all_steps; exit 0 ;;
        4) echo -e "  ${GRAY}请执行: bash init-option.sh${NC}" ;;
        0) echo ""; exit 0 ;;
    esac
    echo ""; read -p "按回车返回主菜单..." dummy < /dev/tty || true
    main_menu
}

# ========== 入口 ==========
case "${1:-menu}" in
    all)
        init_all_steps
        exit 0
        ;;
    option|options)
        echo -e "  ${GRAY}请执行: bash init-option.sh${NC}"
        ;;
    --dry-run|--preview|--what)
        show_banner
        echo ""
        echo -e "${CYAN}━━━ 预览：将要执行的操作 ━━━${NC}"
        echo "  1) init-ubuntu.sh    → 系统包 + node/gh/claude/uv + symlink"
        echo "  2) init-llm.sh       → 写入 ANTHROPIC_AUTH_TOKEN"
        echo "  3) maintain.sh       → 链接修复 + 状态 + 服务"
        echo ""
        echo "  运行 'bash init-base.sh all' 执行以上所有步骤"
        echo "  运行 'bash init-base.sh' 进入交互式菜单"
        echo "  MCP/Skills 可选: bash init-option.sh"
        ;;
    menu|"")
        main_menu
        ;;
    *)
        echo "用法: bash init-base.sh [all|option|--dry-run|menu]"
        ;;
esac

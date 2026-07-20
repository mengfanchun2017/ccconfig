#!/bin/bash
# init-base.sh — ccconfig 初始化统一入口
#
# 使用：
#   bash init-base.sh                  # 交互式菜单（默认）
#   bash init-base.sh all              # 一键全部（跳过交互，全自动）
#   bash init-base.sh status           # 状态检查
#   bash init-base.sh --dry-run        # 预览将要执行的操作（不实际执行）
#   bash init-base.sh option           # 可选组件安装（跳转到 init-option.sh）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/colors.sh"

show_banner() {
    echo -e "${CYAN}Claude Code 配置中枢 · ccconfig${NC}"
}

# 首次初始化检查：仅检查 ccprivate（skill 由 init-skill.sh 自动 clone）
# init_all_steps 假定 ccprivate 已存在（4 步流程的 Step 3 已创建）
check_first_time() {
    if [[ -d "$HOME/git/ccprivate" ]]; then
        return 0
    fi

    echo ""
    echo -e "${YELLOW}━━━ 首次初始化引导 ━━━${NC}"
    echo ""
    echo -e "  ${RED}❌${NC} ccprivate 未找到 — 私有配置（API Key、CLAUDE.md、settings.json）"
    echo -e "     ${CYAN}→${NC} bash ccconfig/init-ccprivate-repo.sh"
    echo ""
    echo -e "  ${GRAY}（6 步流程：clone → bootstrap-gh-auth.sh → init-ccprivate-repo.sh → init-base.sh all → init-option.sh → maintain.sh status）${NC}"
    echo ""

    read -p "是否现在创建 ccprivate？[Y/n]: " create_ccp
    create_ccp="${create_ccp:-y}"
    if [[ "$create_ccp" =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/init-ccprivate-repo.sh"
        echo ""
        echo -e "${GREEN}✅ ccprivate 已创建${NC}"
        echo -e "${YELLOW}请重新运行 init.sh 继续初始化${NC}"
        echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0
    fi

    return 0
}

# 一键全部初始化的标准 5 步。
# 假定 ccprivate 已存在（4 步流程的 Step 3 已创建）
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
        "装 Node / Claude Code / Claude 原生二进制 / uv / 建符号链接 / 启动 auto-sync / 注册 SessionStart hook" \
        "Claude Code 需要 Node 运行时；uv 装 Python 工具；auto-sync 让配置变更自动 push 到 GitHub" \
        "3 min（含 apt 下载）"

    run_step "2/4 LLM 配置" "$SCRIPT_DIR/lib/init-llm.sh" true \
        "把当前 LLM（DeepSeek/MiniMax/Claude 等）的 API key 写入 ~/.claude/settings.json" \
        "Claude Code 通过 ANTHROPIC_AUTH_TOKEN / ANTHROPIC_BASE_URL 调用 LLM；没配就跑不了" \
        "10 s"

    run_step "3/4 MCP 服务器" "$SCRIPT_DIR/lib/init-mcp.sh" true \
        "注册 Tavily（英文搜索）/ MiniMax（中文+多模态）/ Supabase（数据库）/ Cloudflare（开发者平台）到 ~/.claude/settings.json" \
        "MCP 是 Claude Code 的'工具箱'：搜索/数据库/部署/可观测，skills 按需调用" \
        "20 s"

    # Step 4/4: maintain.sh finalize（链接修复 + 状态检查 + 服务启动）
    run_step "4/4 收尾（链接修复 + 状态检查 + 服务启动）" "$SCRIPT_DIR/maintain.sh" finalize \
        "修复符号链接 / 启动 auto-sync 服务 / 状态验证" \
        "确认所有组件就位，可以开始工作" \
        "10 s"

    echo ""
    echo -e "${GREEN}🎉 全部初始化完成${NC}"
    echo ""
    echo -e "${YELLOW}━━━ 重要：刷新 shell 环境 ━━━${NC}"
    echo "  PATH 已写入 ~/.bashrc，当前终端需手动刷新："
    echo ""
    echo -e "    ${GREEN}source ~/.bashrc && hash -r${NC}"
    echo ""
    echo -e "  或直接 ${GREEN}新开一个终端${NC}（新终端自动加载 bashrc）"
    echo ""
    echo -e "${BOLD}日常使用:${NC}"
    echo "  切换 LLM:          bash $SCRIPT_DIR/lib/init-llm.sh"
    echo "  更新系统:          bash $SCRIPT_DIR/lib/update.sh all"
    echo "  状态检查:          bash maintain.sh status"
    echo "  装 Skills:         bash option-skill/init.sh --install"
    echo "  装可选组件:        bash init-option.sh"
    echo ""
    echo ""
    echo -e "${YELLOW}━━━ Worklog 日合并 ━━━${NC}"
    echo "  Worklog 使用 f-logme skill 手动记录 + 每日自动合并。"
    echo "  首次在 Claude 中说一句即可配置: "
    echo ""
    echo -e "    ${GREEN}\"设 worklog 日合并每天中午12:01执行\"${NC}"
    echo ""
    echo "  改时间: \"改 worklog 日合并时间到 HH:MM\""
    echo ""
}

run_step() {
    local label="$1" script="$2" auto="$3"
    local what="${4:-}" why="${5:-}" eta="${6:-}"
    shift 6 2>/dev/null || true  # remaining args passed to script

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
    elif [ "$auto" = "finalize" ]; then
        bash "$script" finalize && echo -e "${GREEN}✅ ${label} 完成${NC}" || echo -e "${RED}❌ ${label} 失败${NC}"
    else
        read -p "运行？[Y/n]: " confirm || true
        confirm="${confirm:-y}"
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
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
    echo ""
    echo -e "${CYAN}── 环境初始化 ──${NC}"
    echo "  1) Ubuntu 全环境初始化 (init-ubuntu.sh)"
    echo "  2) LLM 后端切换       (init-llm.sh)"
    echo "  3) auto-sync 自启动    (init-autostart.sh)"
    echo "  4) ★ 一键全部（ubuntu + LLM + MCP + skills + 收尾）"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-4,0]: " c
    case "$c" in
        1) run_step "Ubuntu 初始化"    "$SCRIPT_DIR/lib/init-ubuntu.sh"    false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        2) run_step "LLM 切换"         "$SCRIPT_DIR/lib/init-llm.sh"       false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        3) run_step "auto-sync 自启动" "$SCRIPT_DIR/lib/init-autostart.sh" false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        4) init_all_steps
           exit 0 ;;
        0) return ;;
    esac
}

submenu_options() {
    bash "$SCRIPT_DIR/init-option.sh"
}

submenu_remote() {
    echo ""
    echo -e "${CYAN}── 远程连接 ──${NC}"
    echo "  1) SSH Server + tmux 安装"
    echo "  2) 部署配置到 Windows"
    echo "  3) 查看完整说明"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-3,0]: " c
    case "$c" in
        1) run_step "SSH Server" "$SCRIPT_DIR/option-remote/server/tmux-sshd.sh" false ;;
        2) bash "$SCRIPT_DIR/option-remote/deploy.sh" server ;;
        3) echo ""; cat "$SCRIPT_DIR/option-remote/readme.md" 2>/dev/null || echo -e "  ${YELLOW}readme.md 不存在${NC}" ;;
    esac
}

submenu_mcp() {
    echo ""
    echo -e "${CYAN}── MCP 管理 ──${NC}"
    echo "  1) 安装并同步 MCP  (init-mcp.sh sync)"
    echo "  2) 仅安装缺失 MCP  (init-mcp.sh install)"
    echo "  3) 配置 API Key     (init-mcp.sh keys)"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-3,0]: " c
    case "$c" in
        1) run_step "MCP 同步"   "$SCRIPT_DIR/lib/init-mcp.sh" true
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        2) echo ""; bash "$SCRIPT_DIR/lib/init-mcp.sh" install
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        3) echo ""; bash "$SCRIPT_DIR/lib/init-mcp.sh" keys
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        0) return ;;
    esac
}

submenu_skills() {
    echo ""
    echo -e "${CYAN}── Skills 管理（可选组件）──${NC}"
    echo "  1) 安装/同步 skills"
    echo "  2) 查看 skills 状态"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-2,0]: " c
    case "$c" in
        1) bash "$SCRIPT_DIR/option-skill/init.sh" --install
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        2) bash "$SCRIPT_DIR/option-skill/init.sh" --status
           bash "$SCRIPT_DIR/lib/init-skill.sh" status
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        0) return ;;
    esac
}

# ========== 主菜单 ==========
main_menu() {
    show_banner
    check_first_time
    echo ""
    echo "  ── 初始化 ──"
    echo "  1) Ubuntu 环境  │ LLM切换 │ 自启动"
    echo "  2) 远程连接    │ SSH │ tmux"
    echo "  3) MCP 管理    │ 安装 │ 同步"
    echo "  4) Skills      │ 同步 │ 状态"
    echo "  5) ★ 一键全部初始化（4 步：Ubuntu → LLM → MCP → 收尾）"
    echo "  ── 可选组件 ──"
    echo "  6) 可选组件（bat / glow / nano / option-*）"
    echo "  0) 退出"
    echo ""
    read -p "选择 [0-6]: " choice

    case "$choice" in
        1) submenu_env ;;
        2) submenu_remote ;;
        3) submenu_mcp ;;
        4) submenu_skills ;;
        5) init_all_steps
           exit 0 ;;
        6) submenu_options
           echo -e "${YELLOW}操作完成${NC}";;
        0) echo ""; exit 0 ;;
        *) echo "无效选择"; main_menu ;;
    esac

    echo ""
    read -p "按回车返回主菜单..." dummy
    main_menu
}

# ========== 入口 ==========
case "${1:-menu}" in
    all)
        init_all_steps
        exit 0
        ;;
    option|options)
        bash "$SCRIPT_DIR/init-option.sh"
        ;;
    --dry-run|--preview|--what)
        show_banner
        echo ""
        echo -e "${CYAN}━━━ 预览：将要执行的操作 ━━━${NC}"
        echo "  1) init-ubuntu.sh    → 系统包 + node/gh/claude/uv + symlink"
        echo "  2) init-llm.sh       → 写入 ANTHROPIC_AUTH_TOKEN"
        echo "  3) init-mcp.sh sync  → 注册 MCP 服务器"
        echo "  4) maintain.sh       → 链接修复 + 状态 + 服务"
        echo ""
        echo "  运行 'bash init-base.sh all' 执行以上所有步骤"
        echo "  运行 'bash init-base.sh' 进入交互式菜单"
        echo "  Skills 可选: bash option-skill/init.sh --install"
        ;;
    status)
        bash "$SCRIPT_DIR/maintain.sh" status
        ;;
    menu|"")
        main_menu
        ;;
    *)
        echo "用法: bash init-base.sh [all|option|--dry-run|status|menu]"
        ;;
esac

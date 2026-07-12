#!/bin/bash
# ccconfig 统一入口 — 两级交互式菜单
#
# 使用：
#   bash ccconfig/init.sh              # 交互式菜单（默认）
#   bash ccconfig/init.sh all          # 一键初始化全部
#   bash ccconfig/init.sh status       # 状态检查
#   bash ccconfig/init.sh --dry-run    # 预览将要执行的操作（不实际执行）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/colors.sh"

show_banner() {
    echo -e "${CYAN}Claude Code 配置中枢 · ccconfig${NC}"
}

# 首次初始化检查：仅检查 ccprivate（claude-skills 由 init-skill.sh 自动 clone）
# 只在交互菜单入口（main_menu）调用，引导用户去 bash bin/init-ccprivate.sh
# init_all_steps 假定 ccprivate 已存在（用户在 4 步流程的 Step 3 创建过）
check_first_time() {
    if [[ -d "$HOME/git/ccprivate" ]]; then
        return 0
    fi

    echo ""
    echo -e "${YELLOW}━━━ 首次初始化引导 ━━━${NC}"
    echo ""
    echo -e "  ${RED}❌${NC} ccprivate 未找到 — 私有配置（API Key、CLAUDE.md、settings.json）"
    echo -e "     ${CYAN}→${NC} bash ccconfig/bin/init-ccprivate.sh"
    echo ""
    echo -e "  ${GRAY}（4 步流程：clone → bash bootstrap.sh → bash bin/init-ccprivate.sh → bash init.sh all）${NC}"
    echo ""

    read -p "是否现在创建 ccprivate？[Y/n]: " create_ccp
    create_ccp="${create_ccp:-y}"
    if [[ "$create_ccp" =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/bin/init-ccprivate.sh"
        echo ""
        echo -e "${GREEN}✅ ccprivate 已创建${NC}"
        echo -e "${YELLOW}请重新运行 init.sh 继续初始化${NC}"
        echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0
    fi

    return 0
}

# 一键全部初始化的标准 5 步。
# 三个入口都走这里，确保行为一致：
#   - submenu_env 4: ★ 一键全部
#   - main_menu 6:   ★ 一键全部初始化
#   - case "all":    bash init.sh all
# 假定 ccprivate 已存在（4 步流程的 Step 3 已创建）
init_all_steps() {
    show_banner

    run_step "1/5 Ubuntu 环境" "$SCRIPT_DIR/init-ubuntu.sh" true
    echo -e "  ${GRAY}下一步: 2/5 LLM 配置（自动进行）${NC}"

    run_step "2/5 LLM 配置" "$SCRIPT_DIR/init-llm.sh" true
    echo -e "  ${GRAY}下一步: 3/5 MCP 服务器${NC}"

    run_step "3/5 MCP 服务器" "$SCRIPT_DIR/init-mcp.sh" true
    echo -e "  ${GRAY}下一步: 4/5 Skills${NC}"

    run_step "4/5 Skills" "$SCRIPT_DIR/init-skill.sh" sync
    echo -e "  ${GRAY}下一步: 5/5 验证${NC}"

    run_step "5/5 验证" "$SCRIPT_DIR/status.sh" false

    echo ""
    echo -e "${GREEN}🎉 全部初始化完成${NC}"
    echo ""
    echo -e "${BOLD}日常使用:${NC}"
    echo "  切换 LLM:          bash ccconfig/init-llm.sh"
    echo "  更新系统:          bash ccconfig/update.sh all"
    echo "  状态检查:          bash ccconfig/status.sh"
    echo ""
    echo -e "${BOLD}可选组件:${NC}"
    echo "  飞书 Bridge:       bash ccconfig/option-bridge/init.sh"
    echo "  Cloudflare 插件:   bash ccconfig/option-cloudflare/init.sh"
    echo "  OfficeCLI:         bash ccconfig/option-officecli/init.sh"
    echo "  Python 包更新:     bash ccconfig/update.sh python"
    echo ""
    echo -e "${GRAY}auto-sync 已在步骤1配置，配置变更自动推送到 GitHub${NC}"
}

run_step() {
    local label="$1"
    local script="$2"
    local auto="$3"
    shift 3

    echo ""
    echo -e "${CYAN}━━━ ${label} ━━━${NC}"

    if [ "$auto" = "true" ]; then
        if bash "$script" "$@"; then
            echo -e "${GREEN}✅ ${label} 完成${NC}"
        else
            echo -e "${RED}❌ ${label} 失败（继续）${NC}"
        fi
    else
        read -p "运行？[Y/n]: " confirm || true
        confirm="${confirm:-y}"
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            if bash "$script"; then
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
    echo "  4) ★ 一键全部（ubuntu + MCP + skills）"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-4,0]: " c
    case "$c" in
        1) run_step "Ubuntu 初始化"    "$SCRIPT_DIR/init-ubuntu.sh"    false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        2) run_step "LLM 切换"         "$SCRIPT_DIR/init-llm.sh"       false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        3) run_step "auto-sync 自启动" "$SCRIPT_DIR/init-autostart.sh" false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        4) init_all_steps
           exit 0 ;;
        0) return ;;
    esac
}

# ========== 可选组件（自动发现 option-*/ ） ==========
discover_options() {
    local opts=()
    for d in "$SCRIPT_DIR"/option-*/; do
        [ -d "$d" ] || continue
        local name=$(basename "$d")
        opts+=("$name|$d")
    done
    printf '%s\n' "${opts[@]}"
}

option_has_init() {
    [ -x "$1/init.sh" ] || [ -f "$1/init.sh" ]
}

submenu_options() {
    echo ""
    echo -e "${CYAN}── 可选组件 ──${NC}"
    echo ""

    local idx=1
    local -a opt_names opt_dirs

    while IFS='|' read -r name dir; do
        [ -z "$name" ] && continue
        opt_names+=("$name")
        opt_dirs+=("$dir")
        local status=""
        if option_has_init "$dir"; then
            status="  ← init.sh"
        fi
        echo -e "  ${BOLD}$idx)${NC} $name ${GRAY}$status${NC}"
        idx=$((idx + 1))
    done <<< "$(discover_options)"

    echo "  0) 返回"
    echo ""
    read -p "选择: " c

    case "$c" in
        0|"") return ;;
        *)
            if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le ${#opt_dirs[@]} ]; then
                local i=$((c - 1))
                local name="${opt_names[$i]}" dir="${opt_dirs[$i]}"
                echo ""
                echo -e "${CYAN}── $name ──${NC}"
                echo ""
                echo "  1) 安装/初始化"
                echo "  2) 状态检查"
                echo "  0) 返回"
                echo ""
                read -p "选择: " sub

                case "$sub" in
                    1) run_step "$name 安装" "$dir/init.sh" false
                       echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
                    2)
                       if [ -x "$dir/init.sh" ]; then
                           bash "$dir/init.sh" --status 2>/dev/null || echo -e "  ${YELLOW}○ 状态检查不支持${NC}"
                       else
                           echo -e "  ${YELLOW}○ 无 init.sh${NC}"
                       fi
                       echo ""; read -p "按回车返回..." dummy
                       ;;
                esac
            fi
            ;;
    esac
}

submenu_remote() {
    echo ""
    echo -e "${CYAN}── 远程连接 ──${NC}"
    echo "  1) SSH Server + tmux 安装  (remote/server/tmux-sshd.sh)"
    echo "  2) 部署配置到 Windows       (remote/deploy.sh server)"
    echo "  3) 查看完整说明             (remote/readme.md)"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-3,0]: " c
    case "$c" in
        1) run_step "SSH Server" "$SCRIPT_DIR/remote/server/tmux-sshd.sh" false ;;
        2) bash "$SCRIPT_DIR/remote/deploy.sh" server ;;
        3) echo ""; info_tmux ;;
    esac
}

info_tmux() {
    echo -e "${CYAN}远程连接方案：${NC}"
    echo ""
    echo "  配置步骤："
    echo "  1. 台式机 WSL: bash ccconfig/remote/server/tmux-sshd.sh"
    echo "  2. 台式机 Win 管理员 PowerShell: 执行 windows/ 下的 ps1 脚本"
    echo "  3. 两端安装 Tailscale 组网"
    echo "  4. 笔记本: ssh -p 2222 <your-username>@<台式机IP>"
    echo ""
    echo "  详见: ccconfig/remote/readme.md"
}

submenu_mcp() {
    echo ""
    echo -e "${CYAN}── MCP 管理 ──${NC}"
    echo "  1) 安装并同步 MCP  (init-mcp.sh sync)"
    echo "  2) 仅安装缺失 MCP  (init-mcp.sh install)"
    echo "  3) 状态检查         (status.sh)"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-3,0]: " c
    case "$c" in
        1) run_step "MCP 同步"   "$SCRIPT_DIR/init-mcp.sh" true
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        2) echo ""; bash "$SCRIPT_DIR/init-mcp.sh" install
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        3) bash "$SCRIPT_DIR/status.sh"
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        0) return ;;
    esac
}

submenu_skills() {
    echo ""
    echo -e "${CYAN}── Skills 管理 ──${NC}"
    echo "  1) 同步 skills 到 Claude Code"
    echo "  2) 查看 skills 状态"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-2,0]: " c
    case "$c" in
        1) run_step "Skills 同步" "$SCRIPT_DIR/init-skill.sh" sync
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        2) bash "$SCRIPT_DIR/init-skill.sh" status
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        0) return ;;
    esac
}

submenu_tools() {
    echo ""
    echo -e "${CYAN}── 系统工具 ──${NC}"
    echo "  1) 状态检查       (status.sh)"
    echo "  2) 强制拉取远程   (sync.sh --pull)"
    echo "  3) 升级组件       (update.sh)"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-3,0]: " c
    case "$c" in
        1) bash "$SCRIPT_DIR/status.sh"
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        2) run_step "强制拉取" "$SCRIPT_DIR/sync.sh --pull" false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        3) bash "$SCRIPT_DIR/update.sh" ;;
        0) return ;;
    esac
}

# ========== 主菜单 ==========
main_menu() {
    show_banner
    check_first_time
    echo ""
    echo "  ── 环境初始化 ──"
    echo "  1) Ubuntu 环境  │ LLM切换 │ 自启动"
    echo "  2) 远程连接    │ SSH │ tmux │ EasyTier"
    echo "  3) MCP 管理    │ 安装 │ 同步 │ 状态"
    echo "  4) Skills      │ 同步 │ 状态"
    echo "  5) 系统工具    │ 检查 │ 拉取 │ 升级"
    echo "  6) ★ 一键全部初始化"
    echo "  ── 可选组件 ──"
    echo "  7) 可选组件（option-*）"
    echo "  0) 退出"
    echo ""
    read -p "选择 [0-7]: " choice

    case "$choice" in
        1) submenu_env ;;
        2) submenu_remote ;;
        3) submenu_mcp ;;
        4) submenu_skills ;;
        5) submenu_tools ;;
        6)
            init_all_steps
            exit 0
            ;;
        7) submenu_options ;;
        0) echo ""; exit 0 ;;
        *) echo "无效选择"; main_menu ;;
    esac

    # 操作后回到主菜单
    echo ""
    read -p "按回车返回主菜单..." dummy
    main_menu
}

# ========== 入口 ==========
case "${1:-menu}" in
    all)
        init_all_steps
        echo ""
        echo "CLI 工具: bat (batcat) / glow / nano — 已由 init-ubuntu.sh 自动安装"
        echo "可选: bash ccconfig/option-bridge/init.sh   # 安装飞书 Bridge"
        exit 0
        ;;
    --dry-run|--preview|--what)
        show_banner
        echo ""
        section "预览：将要执行的操作"
        echo "  init-ubuntu.sh    → 安装系统包 + git/gh/node/uv/claude + symlink + LLM"
        echo "  init-mcp.sh sync  → 注册 MCP 服务器（Tavily/MiniMax/Supabase）"
        echo "  init-skill.sh sync → 安装 CLI 依赖 + symlink 自建 skill + 注册 marketplace"
        echo ""
        echo "  运行 'bash init.sh all' 执行以上操作"
        echo "  运行 'bash init.sh' 进入交互式菜单选择单个步骤"
        ;;
    status)
        bash "$SCRIPT_DIR/status.sh"
        ;;
    menu|"")
        main_menu
        ;;
    *)
        echo "用法: bash ccconfig/init.sh [all|--dry-run|status|menu]"
        ;;
esac

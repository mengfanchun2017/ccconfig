#!/bin/bash
# ccconfig 统一入口 — 两级交互式菜单
#
# 使用：
#   bash ccconfig/init.sh              # 交互式菜单（默认）
#   bash ccconfig/init.sh all          # 一键初始化全部
#   bash ccconfig/init.sh status       # 状态检查

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║          Claude Code 配置中枢 · ccconfig        ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"
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
    echo "  4) ★ 一键全部（ubuntu + LLM + autostart）"
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
        4) run_step "Ubuntu" "$SCRIPT_DIR/init-ubuntu.sh" true
           run_step "LLM"    "$SCRIPT_DIR/init-llm.sh" true deepseek
           run_step "自启动"  "$SCRIPT_DIR/init-autostart.sh" true
           exit 0 ;;
        0) return ;;
    esac
}

submenu_feishu() {
    echo ""
    echo -e "${CYAN}── 飞书 Bridge（可选） ──${NC}"
    echo "  需要安装 lark-cli 和 cc-connect 吗？"
    echo ""
    echo "  手动安装:  bash ccconfig/option-bridge/init.sh"
    echo ""
    echo "  包含:"
    echo "    - lark-cli     (终端创建飞书文档/日历/任务)"
    echo "    - cc-connect   (接收飞书消息 Bridge)"
    echo "    - mcp-bridge   (可选 MCP，bot 消息)"
    echo ""
    echo "  查看状态:  bash ccconfig/option-bridge/bot-status.sh"
    echo "  切换账号:  bash ccconfig/option-bridge/lark-switch.sh <name>"
    echo ""
    read -p "按回车返回..." dummy
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
    echo "  4. 笔记本: ssh -p 2222 francis@<台式机IP>"
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
    echo "  2) 强制拉取远程   (gitforce.sh)"
    echo "  3) 升级组件       (update.sh)"
    echo "  4) WSL 网络/interop 修复 (windows/)"
    echo "  0) 返回"
    echo ""
    read -p "选择 [1-4,0]: " c
    case "$c" in
        1) bash "$SCRIPT_DIR/status.sh"
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        2) run_step "强制拉取" "$SCRIPT_DIR/gitforce.sh" false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        3) bash "$SCRIPT_DIR/update.sh" ;;
        4) run_step "WSL修复" "$SCRIPT_DIR/windows/wsl-interop.sh" false
           echo -e "${YELLOW}操作完成，按回车退出...${NC}"; read -r; exit 0 ;;
        0) return ;;
    esac
}

# ========== 主菜单 ==========
main_menu() {
    show_banner
    echo ""
    echo "  ┌─ 环境初始化 ──────────────────────────┐"
    echo "  │ 1) Ubuntu 环境  │ LLM切换 │ 自启动   │"
    echo "  │ 2) [可选] 飞书 Bridge               │"
    echo "  │ 3) 远程连接    │ SSH │ tmux │ EasyTier │"
    echo "  │ 4) MCP 管理    │ 安装 │ 同步 │ 状态   │"
    echo "  │ 5) Skills      │ 同步 │ 状态          │"
    echo "  │ 6) 系统工具    │ 检查 │ 拉取 │ 升级   │"
    echo "  ├────────────────────────────────────────┤"
    echo "  │ 7) ★ 一键全部初始化                   │"
    echo "  │ 0) 退出                               │"
    echo "  └────────────────────────────────────────┘"
    echo ""
    read -p "选择 [0-7]: " choice

    case "$choice" in
        1) submenu_env ;;
        2) submenu_feishu ;;
        3) submenu_remote ;;
        4) submenu_mcp ;;
        5) submenu_skills ;;
        6) submenu_tools ;;
        7)
            show_banner
            run_step "1/4 Ubuntu 环境"    "$SCRIPT_DIR/init-ubuntu.sh"    true
            run_step "2/4 LLM 配置"       "$SCRIPT_DIR/init-llm.sh"       true deepseek
            run_step "3/4 MCP 服务器"      "$SCRIPT_DIR/init-mcp.sh"      true
            run_step "4/4 Skills"          "$SCRIPT_DIR/init-skill.sh"    sync
            echo ""
            echo "🎉 全部初始化完成（飞书 Bridge 为可选组件）"
            echo "提示: auto-sync 和 SessionStart hook 已在步骤1中配置"
            echo "可选: bash ccconfig/option-bridge/init.sh  # 安装飞书 Bridge"
            exit 0
            ;;
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
        show_banner
        run_step "1/4 Ubuntu 环境"    "$SCRIPT_DIR/init-ubuntu.sh"    true
        run_step "2/4 LLM 配置"       "$SCRIPT_DIR/init-llm.sh"       true deepseek
        run_step "3/4 MCP 服务器"      "$SCRIPT_DIR/init-mcp.sh"      true
        run_step "4/4 Skills"          "$SCRIPT_DIR/init-skill.sh"    sync
        echo ""
        echo "🎉 全部初始化完成（飞书 Bridge 为可选组件）"
        echo "提示: auto-sync 和 SessionStart hook 已在步骤1中配置"
        echo "可选: bash ccconfig/option-bridge/init.sh  # 安装飞书 Bridge"
        exit 0
        ;;
    status)
        bash "$SCRIPT_DIR/status.sh"
        ;;
    menu|"")
        main_menu
        ;;
    *)
        echo "用法: bash ccconfig/init.sh [all|status|menu]"
        ;;
esac

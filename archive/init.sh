#!/bin/bash
# Claude Config 统一初始化入口
# 功能：按顺序运行所有 init 脚本
#
# 使用：
#   bash ccconfig/init.sh              # 交互式，询问每步
#   bash ccconfig/init.sh all          # 一键初始化全部
#   bash ccconfig/init.sh status       # 仅状态检查
#
# 初始化流程（5步）：
#   1. ubuntuinit.sh   → 基础环境（Git/Claude/Node/字体/LLM/auto-sync）
#   2. feishuinit.sh   → 飞书 lark-cli（文档/日历/任务）
#   3. claudeinit.sh   → MCP 服务器
#   4. skillinit.sh    → Claude Code Skills 安装
#   5. cconnectinit.sh → cc-connect Bridge（多用户飞书 WebSocket）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║        Claude Config 统一初始化                ║"
    echo "║    Ubuntu 环境一键配置 + 多用户飞书桥接        ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"
}

run_step() {
    local step_name="$1"
    local script="$2"
    local auto_yes="$3"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  [$step_name]${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ "$auto_yes" = "true" ]; then
        if bash "$script"; then
            echo -e "${GREEN}✅ $step_name 完成${NC}"
        else
            echo -e "${RED}❌ $step_name 失败（继续下一步）${NC}"
        fi
    else
        echo ""
        read -p "是否运行 $step_name？[Y/n]: " confirm || true
        confirm="${confirm:-y}"
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            if bash "$script"; then
                echo -e "${GREEN}✅ $step_name 完成${NC}"
            else
                echo -e "${RED}❌ $step_name 失败${NC}"
            fi
        else
            echo -e "${YELLOW}跳过 $step_name${NC}"
        fi
    fi
}

show_menu() {
    show_banner
    echo ""
    echo "请选择初始化模式："
    echo ""
    echo "  1) 一键全部初始化（推荐，含 Bridge）"
    echo "  2) 仅基础环境（ubuntuinit.sh）"
    echo "  3) 仅飞书文档（feishuinit.sh）"
    echo "  4) 仅 MCP 服务器（claudeinit.sh）"
    echo "  5) 仅 Skills 安装（skillinit.sh）"
    echo "  6) 仅 Bridge 桥接（cconnectinit.sh）"
    echo "  7) 状态检查"
    echo "  8) 完整交互式（每步确认，含 Bridge）"
    echo "  9) 全部初始化（不含 Bridge，多机推荐）"
    echo "  0) 退出"
    echo ""
    read -p "选择 [1-9,0]: " choice

    case "$choice" in
        1)
            run_step "1/5 基础环境"     "$SCRIPT_DIR/ubuntuinit.sh"   true
            run_step "2/5 飞书文档"     "$SCRIPT_DIR/feishuinit.sh"   true
            run_step "3/5 MCP 服务器"   "$SCRIPT_DIR/claudeinit.sh"   true
            run_step "4/5 Skills"       "$SCRIPT_DIR/skillinit.sh"    true
            run_step "5/5 Bridge 桥接"  "$SCRIPT_DIR/cconnectinit.sh" true
            ;;
        2)
            run_step "基础环境"         "$SCRIPT_DIR/ubuntuinit.sh"   false
            ;;
        3)
            run_step "飞书文档"         "$SCRIPT_DIR/feishuinit.sh"   false
            ;;
        4)
            run_step "MCP 服务器"       "$SCRIPT_DIR/claudeinit.sh"   false
            ;;
        5)
            run_step "Skills 安装"      "$SCRIPT_DIR/skillinit.sh"    false
            ;;
        6)
            run_step "Bridge 桥接"      "$SCRIPT_DIR/cconnectinit.sh" false
            ;;
        7)
            bash "$SCRIPT_DIR/hook-status.sh"
            ;;
        8)
            run_step "1/5 基础环境"     "$SCRIPT_DIR/ubuntuinit.sh"   false
            run_step "2/5 飞书文档"     "$SCRIPT_DIR/feishuinit.sh"   false
            run_step "3/5 MCP 服务器"   "$SCRIPT_DIR/claudeinit.sh"   false
            run_step "4/5 Skills"       "$SCRIPT_DIR/skillinit.sh"    false
            run_step "5/5 Bridge 桥接"  "$SCRIPT_DIR/cconnectinit.sh" false
            ;;
        9)
            run_step "1/4 基础环境"     "$SCRIPT_DIR/ubuntuinit.sh"   true
            run_step "2/4 飞书文档"     "$SCRIPT_DIR/feishuinit.sh"   true
            run_step "3/4 MCP 服务器"   "$SCRIPT_DIR/claudeinit.sh"   true
            run_step "4/4 Skills"       "$SCRIPT_DIR/skillinit.sh"    true
            ;;
        0)
            echo "退出"
            exit 0
            ;;
        *)
            echo "无效选择"
            exit 1
            ;;
    esac
}

# ========== 主程序 ==========
case "${1:-menu}" in
    all)
        show_banner
        run_step "1/5 基础环境"     "$SCRIPT_DIR/ubuntuinit.sh"   true
        run_step "2/5 飞书文档"     "$SCRIPT_DIR/feishuinit.sh"   true
        run_step "3/5 MCP 服务器"   "$SCRIPT_DIR/claudeinit.sh"   true
        run_step "4/5 Skills"       "$SCRIPT_DIR/skillinit.sh"    true
        run_step "5/5 Bridge 桥接"  "$SCRIPT_DIR/cconnectinit.sh" true
        ;;
    nobridge)
        show_banner
        run_step "1/4 基础环境"     "$SCRIPT_DIR/ubuntuinit.sh"   true
        run_step "2/4 飞书文档"     "$SCRIPT_DIR/feishuinit.sh"   true
        run_step "3/4 MCP 服务器"   "$SCRIPT_DIR/claudeinit.sh"   true
        run_step "4/4 Skills"       "$SCRIPT_DIR/skillinit.sh"    true
        ;;
    status)
        bash "$SCRIPT_DIR/hook-status.sh"
        ;;
    menu|"")
        show_menu
        ;;
    *)
        echo "用法: bash ccconfig/init.sh [all|nobridge|status|menu]"
        echo "  all      - 一键初始化全部（5步，含 Bridge）"
        echo "  nobridge - 全部初始化不含 Bridge（4步，多机推荐）"
        echo "  status   - 状态检查"
        echo "  menu     - 交互式菜单（默认）"
        ;;
esac

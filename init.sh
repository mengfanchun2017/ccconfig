#!/bin/bash
# Claude Config - 主初始化脚本
#
# 功能：按顺序执行所有初始化脚本
# 用法：bash init.sh [选项]
#
# 选项：
#   all     - 执行所有初始化（默认）
#   git     - 仅执行 Git 初始化
#   claude  - 仅执行 Claude 安装
#   env     - 仅执行环境配置
#   mcp     - 仅执行 MCP 配置
#   auto    - 配置 auto-sync 自启动
#   status  - 查看当前配置状态

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

info() { echo -e "${CYAN}[INFO]${NC} $1"; }
step() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 获取远程最新提交数
get_remote_updates() {
    local repo="$1"
    if [ -d "$repo/.git" ]; then
        (cd "$repo" && git fetch origin main 2>/dev/null)
        local count=$(git rev HEAD..origin/main 2>/dev/null | wc -l)
        echo "$count"
    else
        echo "0"
    fi
}

# ========== 显示状态 ==========
show_status() {
    echo ""
    echo -e "${CYAN}=== Claude Config 状态检查 ===${NC}"
    echo ""

    # Git 远程更新
    step "Git 远程更新"
    local updates=$(get_remote_updates "$REPO_DIR")
    if [ "$updates" -gt 0 ]; then
        echo -e "  ${YELLOW}有 $updates 个更新可用${NC}"
        echo -e "  运行 ${CYAN}git pull${NC} 拉取最新版本"
    else
        echo -e "  ${GREEN}已是最新版本${NC}"
    fi
    echo ""

    # 符号链接检查
    step "符号链接"
    local link_errors=0

    if [ -L "$HOME/.claude/settings.json" ]; then
        if [ -e "$HOME/.claude/settings.json" ]; then
            echo -e "  ${GREEN}✅ settings.json${NC}"
        else
            echo -e "  ${RED}❌ settings.json (链接断开)${NC}"
            link_errors=$((link_errors + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠️  settings.json (未链接)${NC}"
    fi

    if [ -L "$HOME/CLAUDE.md" ]; then
        if [ -e "$HOME/CLAUDE.md" ]; then
            echo -e "  ${GREEN}✅ CLAUDE.md${NC}"
        else
            echo -e "  ${RED}❌ CLAUDE.md (链接断开)${NC}"
            link_errors=$((link_errors + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠️  CLAUDE.md (未链接)${NC}"
    fi

    local mem_link="$HOME/.claude/projects/-home-francis-git/memory/MEMORY.md"
    if [ -L "$mem_link" ]; then
        if [ -e "$mem_link" ]; then
            echo -e "  ${GREEN}✅ MEMORY.md${NC}"
        else
            echo -e "  ${RED}❌ MEMORY.md (链接断开)${NC}"
            link_errors=$((link_errors + 1))
        fi
    else
        echo -e "  ${YELLOW}⚠️  MEMORY.md (未链接)${NC}"
    fi
    echo ""

    # auto-sync 检查
    step "auto-sync"
    local auto_sync_pid=$(pgrep -f "auto-sync.sh start" 2>/dev/null | head -1)
    if [ -n "$auto_sync_pid" ]; then
        echo -e "  ${GREEN}✅ 运行中 (PID: $auto_sync_pid)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  未运行${NC}"
        echo -e "  运行 ${CYAN}bash scripts/auto-sync.sh start${NC} 启动"
    fi
    echo ""

    # MCP 检查
    step "MCP 服务器"
    if command -v claude &>/dev/null; then
        # 跳过前两行（Checking... 和空行），计算剩余行数
        local mcp_count=$(claude mcp list 2>/dev/null | tail -n +3 | grep -c ":" || echo "0")
        if [ "$mcp_count" -gt 0 ]; then
            echo -e "  ${GREEN}✅ 已配置 $mcp_count 个 MCP${NC}"
            claude mcp list 2>/dev/null | tail -n +3 | grep ":" | sed 's/^/  /'
        else
            echo -e "  ${YELLOW}⚠️  无 MCP 配置${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  Claude Code 未安装${NC}"
    fi
    echo ""

    echo -e "${CYAN}================================${NC}"
    if [ "$updates" -eq 0 ] && [ "$link_errors" -eq 0 ]; then
        echo -e "${GREEN}✅ 所有配置正常，可以开始工作！${NC}"
    else
        echo -e "${YELLOW}⚠️  有配置问题，请先修复${NC}"
    fi
    echo ""
}

# ========== Git 拉取 ==========
git_pull() {
    step "Git 拉取更新"
    cd "$REPO_DIR"
    if git fetch origin main 2>/dev/null; then
        local updates=$(git rev HEAD..origin/main 2>/dev/null | wc -l)
        if [ "$updates" -gt 0 ]; then
            info "发现 $updates 个更新，正在拉取..."
            if git pull --rebase origin main; then
                echo -e "  ${GREEN}✅ 拉取成功${NC}"
            else
                echo -e "  ${RED}❌ 拉取失败，请手动检查${NC}"
            fi
        else
            echo -e "  ${GREEN}已是最新版本${NC}"
        fi
    else
        warn "无法连接远程仓库"
    fi
}

# ========== 执行单个脚本 ==========
run_script() {
    local script="$1"
    local name=$(basename "$script" .sh)
    step "$name"
    if bash "$script"; then
        echo -e "  ${GREEN}✅ 完成${NC}"
    else
        echo -e "  ${RED}❌ 失败${NC}"
        return 1
    fi
}

# ========== 主程序 ==========
main() {
    case "${1:-all}" in
        all)
            echo -e "${CYAN}=== Claude Config 完整初始化 ===${NC}"
            echo ""

            git_pull
            echo ""

            run_script "$SCRIPT_DIR/scripts/init01git.sh"
            run_script "$SCRIPT_DIR/scripts/init02claude.sh"
            run_script "$SCRIPT_DIR/scripts/init03env.sh"
            run_script "$SCRIPT_DIR/scripts/claudemcp.sh"

            echo ""
            echo -e "${GREEN}=== 初始化完成 ===${NC}"
            show_status
            ;;
        git)
            git_pull
            ;;
        claude)
            run_script "$SCRIPT_DIR/scripts/init02claude.sh"
            ;;
        env)
            run_script "$SCRIPT_DIR/scripts/init03env.sh"
            ;;
        mcp)
            run_script "$SCRIPT_DIR/scripts/claudemcp.sh"
            ;;
        auto)
            bash "$SCRIPT_DIR/scripts/enable-autostart.sh" enable
            ;;
        status)
            git_pull
            show_status
            ;;
        help|--help|-h)
            echo "用法: init.sh [选项]"
            echo ""
            echo "选项："
            echo "  all     - 执行所有初始化（默认）"
            echo "  git     - 仅执行 Git 拉取"
            echo "  claude  - 仅执行 Claude 安装"
            echo "  env     - 仅执行环境配置"
            echo "  mcp     - 仅执行 MCP 配置"
            echo "  auto    - 配置 auto-sync 自启动"
            echo "  status  - 查看当前配置状态"
            echo "  help    - 显示帮助"
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            echo "运行 init.sh help 查看帮助"
            exit 1
            ;;
    esac
}

main "$@"

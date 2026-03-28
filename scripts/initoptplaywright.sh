#!/bin/bash
# Claude Code Playwright 浏览器配置脚本
# 功能：选择并配置不同的浏览器后端（Steel / Chrome / Edge）
#
# 使用方法（从仓库上级目录运行）：
#   bash claude-config/scripts/initoptplaywright.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_JSON="$HOME/.claude.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

title() { echo -e "\n========================================\n$1\n========================================\n${CYAN}"; }
section() { echo -e "\n【$1】${YELLOW}"; }
item() { echo -e "$1${NC}"; }
good() { echo -e "$1${GREEN}"; }
bad() { echo -e "$1${RED}"; }
info() { echo -e "$1${GRAY}"; }
warn() { echo -e "$1${YELLOW}"; }

# ========== 检查函数 ==========
check_docker() {
    command -v docker &> /dev/null && docker info &> /dev/null
}

check_npm() {
    command -v npm &> /dev/null
}

check_chromium() {
    command -v chromium &> /dev/null || \
    command -v chromium-browser &> /dev/null || \
    command -v google-chrome &> /dev/null || \
    command -v google-chrome-stable &> /dev/null
}

check_edge() {
    # Windows Edge 通过 WSL 检测
    powershell.exe -Command "Get-Command msedge" &> /dev/null 2>&1
}

# ========== 获取当前配置 ==========
get_current_browser() {
    python3 - "$CLAUDE_JSON" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)

    mcp_servers = data.get('mcpServers', {})
    playwright = mcp_servers.get('playwright', {})

    args = playwright.get('args', [])
    env = playwright.get('env', {})

    # 检测是否是 Steel (有 cdp-endpoint)
    if any('cdp-endpoint' in str(a) for a in args):
        print('steel')
    # 检测是否是 Edge (有 --edge 或 user-data-dir 包含 Edge)
    elif any('--edge' in str(a) or 'msedge' in str(a) for a in args):
        print('edge')
    # 默认是 chromium
    elif playwright:
        print('chromium')
    else:
        print('none')
except:
    print('none')
PYEOF
}

# ========== 读取 Playwright 配置 ==========
read_playwright_config() {
    python3 - "$CLAUDE_JSON" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)

    mcp_servers = data.get('mcpServers', {})
    playwright = mcp_servers.get('playwright', {})

    print(json.dumps(playwright))
except:
    print('{}')
PYEOF
}

# ========== 更新 Playwright MCP 配置 ==========
update_playwright_mcp() {
    local name="$1"
    local install_cmd="$2"
    local cdp_endpoint="$3"
    local extra_args="$4"

    python3 - "$CLAUDE_JSON" "$name" "$install_cmd" "$cdp_endpoint" "$extra_args" << 'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)

    name = sys.argv[2]
    install_cmd = sys.argv[3]
    cdp_endpoint = sys.argv[4]
    extra_args = sys.argv[5] if len(sys.argv) > 5 else ''

    mcp_servers = data.get('mcpServers', {})

    # 构建新的配置
    if cdp_endpoint:
        args = ['@playwright/mcp', '--cdp-endpoint', cdp_endpoint]
        if extra_args:
            args.extend(extra_args.split())
        config = {
            'command': 'npx',
            'args': args,
            'env': {}
        }
    else:
        # 默认本地浏览器
        args = ['@playwright/mcp']
        if extra_args:
            args.extend(extra_args.split())
        config = {
            'command': 'npx',
            'args': args,
            'env': {}
        }

    mcp_servers['playwright'] = config

    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2)

    print('ok')
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
PYEOF
}

# ========== 启动 Steel ==========
start_steel() {
    section "🚀 启动 Steel 浏览器"

    # 检查 Docker
    if ! check_docker; then
        bad "❌ Docker 未安装或未运行"
        info "请先安装 Docker: https://docs.docker.com/get-docker/"
        return 1
    fi

    # 检查 Steel 容器是否已运行
    if docker ps | grep -q steel-browser; then
        info "Steel 已在运行中"
        docker ps --filter name=steel-browser --format "{{.Ports}}"
        return 0
    fi

    # 启动 Steel
    info "启动 Steel 容器..."
    docker run -d \
        --name steel-browser \
        -p 3000:3000 \
        -p 9223:9223 \
        ghcr.io/steel-dev/steel-browser

    if [ $? -eq 0 ]; then
        good "✅ Steel 启动成功"
        info "API: http://localhost:3000"
        info "UI:  http://localhost:3000/ui"
        info "CDP: localhost:9223"

        # 等待 Steel 就绪
        echo -n "等待 Steel 就绪"
        for i in {1..10}; do
            if curl -s http://localhost:3000 > /dev/null 2>&1; then
                echo -e "\n${GREEN}✅ Steel 已就绪${NC}"
                return 0
            fi
            echo -n "."
            sleep 1
        done
        echo -e "\n${YELLOW}⚠️ Steel 启动中，请稍后手动检查${NC}"
        return 0
    else
        bad "❌ Steel 启动失败"
        return 1
    fi
}

# ========== 停止 Steel ==========
stop_steel() {
    if docker ps | grep -q steel-browser; then
        echo -n "停止 Steel ... "
        docker stop steel-browser &> /dev/null
        docker rm steel-browser &> /dev/null
        good "✅ 已停止"
    else
        info "Steel 未运行"
    fi
}

# ========== 主程序 ==========
title "Claude Code Playwright 配置"

# 检测环境
section "🔍 环境检测"
info "Docker: $(check_docker && echo '✅ 可用' || echo '❌ 不可用')"
info "npm: $(check_npm && echo '✅ 可用' || echo '❌ 不可用')"
info "Chromium: $(check_chromium && echo '✅ 已安装' || echo '❌ 未安装')"
info "Edge (Windows): $(check_edge && echo '✅ 已安装' || echo '❌ 未安装')"

# 获取当前配置
current=$(get_current_browser)
section "📋 当前配置"
case "$current" in
    steel)   info "浏览器: Steel (CDP)" ;;
    edge)    info "浏览器: Microsoft Edge" ;;
    chromium) info "浏览器: Chromium (本地)" ;;
    none)    info "浏览器: 未配置" ;;
esac

# 显示选项
section "🔧 请选择要配置的浏览器"

echo -e "  ${CYAN}1)${NC} ${GREEN}Steel${NC} - AI 专用浏览器，支持 stealth/代理/验证码"
echo -e "     Docker 方式运行，完全免费开源"
echo ""
echo -e "  ${CYAN}2)${NC} ${GREEN}Chromium${NC} - Playwright 默认浏览器"
echo -e "     需要先运行: npx playwright install"
echo ""
echo -e "  ${CYAN}3)${NC} ${YELLOW}Microsoft Edge${NC} - 使用 Windows Edge 浏览器"
echo -e "     需要 Windows 环境，CDP 连接"
echo ""
echo -e "  ${CYAN}4)${NC} 查看当前详细配置"
echo ""
echo -e "  ${CYAN}0)${NC} 退出"
echo ""

read -p "请输入选项 [0-4]: " choice
echo ""

case "$choice" in
    1)
        # Steel
        title "配置 Steel"

        # 先检查/启动 Steel
        if ! docker ps | grep -q steel-browser; then
            echo -e "${YELLOW}Steel 未运行，是否启动?${NC}"
            read -p "启动 Steel 容器? [Y/n]: " start_choice
            start_choice=${start_choice:-Y}

            if [[ "$start_choice" =~ ^[Yy]$ ]]; then
                start_steel
            else
                bad "❌ Steel 未启动，无法配置"
                exit 1
            fi
        else
            info "Steel 已在运行: localhost:9223"
        fi

        # CDP 端点
        CDP_ENDPOINT="ws://localhost:9223"

        echo ""
        info "将配置 Playwright MCP 连接到: $CDP_ENDPOINT"
        read -p "确认配置? [Y/n]: " confirm
        confirm=${confirm:-Y}

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            result=$(update_playwright_mcp "playwright" "npx @playwright/mcp" "$CDP_ENDPOINT" "")
            if [[ "$result" == "ok" ]]; then
                good "✅ 配置成功！"
                info "重启 Claude Code 后生效"
            else
                bad "❌ 配置失败: $result"
            fi
        else
            info "已取消"
        fi
        ;;

    2)
        # Chromium
        title "配置 Chromium (本地)"

        if ! check_chromium; then
            warn "⚠️ Chromium 未检测到"
            echo -e "${YELLOW}需要先安装 Chromium:${NC}"
            echo -e "  npx playwright install chromium"
            echo ""
            read -p "是否现在安装? [y/N]: " install_choice

            if [[ "$install_choice" =~ ^[Yy]$ ]]; then
                info "安装中 (可能需要几分钟)..."
                npx playwright install chromium
                if [ $? -eq 0 ]; then
                    good "✅ Chromium 安装成功"
                else
                    bad "❌ Chromium 安装失败"
                    exit 1
                fi
            else
                bad "❌ Chromium 未安装，无法配置"
                exit 1
            fi
        else
            good "✅ Chromium 已安装"
        fi

        echo ""
        info "将使用本地 Chromium (Playwright 默认行为)"
        read -p "确认配置? [Y/n]: " confirm
        confirm=${confirm:-Y}

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # 使用空 CDP_ENDPOINT 表示本地浏览器
            result=$(update_playwright_mcp "playwright" "npx @playwright/mcp" "" "")
            if [[ "$result" == "ok" ]]; then
                good "✅ 配置成功！"
                info "Playwright 将使用本地 Chromium"
                info "重启 Claude Code 后生效"
            else
                bad "❌ 配置失败: $result"
            fi
        else
            info "已取消"
        fi
        ;;

    3)
        # Edge
        title "配置 Microsoft Edge"

        if ! check_edge; then
            bad "❌ Windows Edge 未检测到"
            info "请确保在 Windows 上安装了 Edge 浏览器"
            exit 1
        fi

        # Edge DevTools 端口 (默认 9222)
        EDGE_CDP="ws://localhost:9222"

        echo ""
        warn "⚠️ Edge 连接需要额外配置:"
        info "1. 在 Windows 上启用 Edge DevTools:"
        echo -e "   ${CYAN}Set-ExecutionPolicy RemoteSigned -Scope CurrentUser${NC}"
        echo -e "   ${CYAN}iex ((New-Object System.Net.WebClient).DownloadString('https://edge-developer-tools.azureedge.net/grantpermissions'))${NC}"
        echo ""
        info "2. 启动 Edge 并启用远程调试:"
        echo -e "   ${CYAN}msedge --remote-debugging-port=9222${NC}"
        echo ""

        echo -e "假设 Edge CDP 端点: ${YELLOW}$EDGE_CDP${NC}"
        echo -e "(如果不是，请手动修改脚本)"
        echo ""

        read -p "确认配置 Edge? [Y/n]: " confirm
        confirm=${confirm:-Y}

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            result=$(update_playwright_mcp "playwright" "npx @playwright/mcp" "$EDGE_CDP" "")
            if [[ "$result" == "ok" ]]; then
                good "✅ 配置成功！"
                info "重启 Claude Code 后生效"
            else
                bad "❌ 配置失败: $result"
            fi
        else
            info "已取消"
        fi
        ;;

    4)
        # 查看详细配置
        title "当前 Playwright MCP 详细配置"
        config=$(read_playwright_config)
        echo "$config" | python3 -m json.tool 2>/dev/null || echo "$config"
        ;;

    0|*)
        info "退出"
        exit 0
        ;;
esac

echo ""
good "✅ 配置完成！"
info "请重启 Claude Code 使配置生效"

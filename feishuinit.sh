#!/bin/bash
# 飞书初始化脚本
# 功能：安装配置 lark-cli 和 feishu-claude-code bridge
# 目的：新 Ubuntu/WSL 环境快速打通飞书
#
# 使用：
#   bash ccconfig/feishuinit.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

title() { echo -e "\n========================================\n$1\n========================================\n${CYAN}"; }
section() { echo -e "\n【$1】${YELLOW}"; }
good() { echo -e "$1${GREEN}"; }
bad() { echo -e "$1${RED}"; }
info() { echo -e "$1${GRAY}"; }
warn() { echo -e "$1${YELLOW}"; }

# ========== 检查前置环境 ==========
check_prerequisites() {
    title "检查前置环境"

    local missing=0

    if ! command -v node &> /dev/null; then
        bad "❌ Node.js 未安装"
        missing=1
    else
        good "✓ Node.js $(node --version)"
    fi

    if ! command -v npm &> /dev/null; then
        bad "❌ npm 未安装"
        missing=1
    else
        good "✓ npm $(npm --version)"
    fi

    if ! command -v claude &> /dev/null; then
        warn "⚠ Claude Code 未安装（lark-cli 可独立使用）"
    else
        good "✓ Claude Code 已安装"
    fi

    if [ $missing -eq 1 ]; then
        echo ""
        warn "请先运行 ubuntuinit.sh 完成基础环境配置"
        exit 1
    fi
}

# ========== 安装 lark-cli ==========
install_lark_cli() {
    title "安装 lark-cli"

    if command -v lark-cli &> /dev/null; then
        good "✓ lark-cli 已安装: $(lark-cli --version 2>/dev/null || lark-cli version 2>/dev/null || 'unknown')"
        return 0
    fi

    section "npm 全局安装"
    echo -n "安装 @larksuite/cli ... "
    if npm install -g @larksuite/cli 2>&1; then
        good "✅ 安装成功"
    else
        bad "❌ 安装失败"
        return 1
    fi

    # PATH 修复
    section "PATH 修复"
    local node_path
    node_path=$(find "$HOME/.local" -name "lark-cli" -type f 2>/dev/null | head -1)
    if [ -z "$node_path" ]; then
        node_path=$(find "$HOME" -name "lark-cli" -type f 2>/dev/null | grep "\.npm" | head -1)
    fi

    if [ -n "$node_path" ]; then
        local bin_dir
        bin_dir=$(dirname "$node_path")
        echo -n "创建 bin 链接到 ~/.local/bin ... "
        if [ ! -d "$HOME/.local/bin" ]; then
            mkdir -p "$HOME/.local/bin"
        fi
        if ln -sf "$node_path" "$HOME/.local/bin/lark-cli" 2>/dev/null; then
            good "✅"
        else
            warn "⚠ 链接失败，请手动执行: ln -s $node_path ~/.local/bin/lark-cli"
        fi
    else
        warn "⚠ 未找到 lark-cli 可执行文件"
    fi

    export PATH="$HOME/.local/bin:$PATH"

    echo ""
    echo -n "验证安装 ... "
    if command -v lark-cli &> /dev/null; then
        good "✅ lark-cli 已可用"
    else
        bad "❌ lark-cli 不可用，请检查 PATH"
        return 1
    fi
}

# ========== 配置 lark-cli ==========
configure_lark_cli() {
    title "配置 lark-cli"

    export PATH="$HOME/.local/bin:$PATH"

    # 检查是否已配置
    section "检查当前配置"
    if lark-cli config list 2>/dev/null | grep -q "app_id"; then
        good "✓ lark-cli 已配置"
        lark-cli config list 2>/dev/null || true
        return 0
    fi

    section "初始化配置"
    echo ""
    warn "需要填写飞书应用凭证"
    echo ""
    echo "请到 https://open.feishu.cn/app/<your-feishu-app-id> 获取 App ID 和 App Secret"
    echo "或者创建新应用后填入"
    echo ""

    # 交互式初始化
    echo -n "App ID (cli_xxxxx): "
    read -r app_id || true
    app_id="${app_id:-<your-feishu-app-id>}"

    echo -n "App Secret: "
    read -r app_secret || true

    if [ -z "$app_secret" ]; then
        warn "跳过配置（未提供 App Secret）"
        return 0
    fi

    echo ""
    echo -n "配置 lark-cli ... "
    if echo "$app_secret" | lark-cli config init --app-id "$app_id" --app-secret-stdin --brand feishu 2>&1; then
        good "✅ 配置成功"
    else
        bad "❌ 配置失败"
        return 1
    fi
}

# ========== lark-cli 用户授权 ==========
auth_lark_cli() {
    title "lark-cli 用户授权"

    export PATH="$HOME/.local/bin:$PATH"

    section "OAuth 授权"
    echo ""
    echo "需要 Francis 账号授权才能创建用户身份文档"
    echo ""
    echo "执行以下命令完成授权："
    echo -e "${CYAN}lark-cli auth login --recommend${NC}"
    echo ""
    echo "或浏览器打开授权链接："
    echo "https://open.feishu.cn/open-apis/authen/v1/index?redirect_uri=https%3A%2F%2Flarksuite.com%2Ftool%2Fcli%2Fcallback&app_id=<your-feishu-app-id>&state=cli"
    echo ""

    read -p "是否现在执行授权? [y/N]: " confirm || true
    confirm="${confirm:-n}"
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        lark-cli auth login --recommend || warn "授权可能需要浏览器完成"
    fi
}

# ========== feishu-claude-code Bridge 配置 ==========
configure_feishu_bridge() {
    title "feishu-claude-code Bridge 配置"

    section "飞书开放平台配置"
    echo ""
    echo "需要在飞书开放平台配置长连接（WebSocket）接收消息"
    echo ""
    echo "步骤："
    echo "1. 打开 https://open.feishu.cn/app/<your-feishu-app-id>"
    echo "2. 进入 事件与回调"
    echo "3. 订阅方式 选择 长连接（不是 Webhook）"
    echo "4. 添加事件: im.message.receive_v1（接收消息）"
    echo ""
    echo "配置好后，bridge 会自动连接，你就能在飞书和我对话了"
    echo ""

    # 检查 MCP 是否配置
    section "检查 MCP 状态"
    if command -v claude &> /dev/null; then
        echo -n "feishu MCP ... "
        if claude mcp list 2>/dev/null | grep -q "feishu"; then
            good "✓ 已注册"
        else
            warn "○ 未注册（需要运行 claudeinit.sh）"
        fi
    fi

    section "安装 feishu MCP"
    if command -v claude &> /dev/null && [ -f "$SCRIPT_DIR/conf-claude.json" ]; then
        echo "运行以下命令安装 feishu MCP："
        echo -e "${CYAN}bash ccconfig/claudeinit.sh${NC}"
        echo ""
        read -p "是否现在运行? [y/N]: " confirm || true
        confirm="${confirm:-n}"
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            bash "$SCRIPT_DIR/claudeinit.sh"
        fi
    fi
}

# ========== 飞书功能测试 ==========
test_feishu() {
    title "飞书功能测试"

    export PATH="$HOME/.local/bin:$PATH"

    section "lark-cli 测试"
    echo -n "lark-cli 版本 ... "
    if lark-cli --version 2>/dev/null || lark-cli version 2>/dev/null; then
        good "✅"
    else
        warn "⚠ 无法获取版本"
    fi

    echo -n "lark-cli 配置 ... "
    if lark-cli config list 2>/dev/null | grep -q "app_id"; then
        good "✓ 已配置"
    else
        warn "○ 未配置"
    fi

    section "MCP 测试"
    if command -v claude &> /dev/null; then
        echo -n "feishu MCP ... "
        if claude mcp list 2>/dev/null | grep -q "feishu"; then
            good "✓ 已注册"
        else
            warn "○ 未注册"
        fi
    fi
}

# ========== 主程序 ==========
main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         飞书初始化 - Feishu Init                 ║"
    echo "║  安装配置 lark-cli 和 feishu-claude-code bridge  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"

    check_prerequisites
    install_lark_cli
    configure_lark_cli
    auth_lark_cli
    configure_feishu_bridge
    test_feishu

    echo ""
    title "✅ 飞书初始化完成"
    echo ""
    echo "后续步骤："
    echo "1. 完成飞书开放平台的长连接配置"
    echo "2. 运行 lark-cli auth login 完成用户授权"
    echo "3. 重启 Claude Code 加载 feishu MCP"
    echo ""
}

#!/bin/bash
# 飞书初始化脚本
# 功能：安装配置 lark-cli（文档/日历/任务写操作）
# 配置：从 conf-feishu.json 读取
# 目的：新 Ubuntu/WSL 环境配置飞书基础能力（所有环境都跑）
#
# 注意：ccbot (Bridge) 相关已拆分到 bridgeinit.sh
#
# 使用：
#   bash ccconfig/feishuinit.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEISHU_CONF="$SCRIPT_DIR/conf-feishu.json"

# 确保 node/npm 可以找到：
# ubuntuinit.sh 装 Node.js 到 ~/.local/node-v20.11.0-linux-x64/
# 符号链接放在 ~/.local/bin/
# 直接用绝对路径，不依赖 PATH 查找，彻底解决 WSL 环境 PATH 被 Windows 污染的问题
export PATH="${HOME}/.local/node-v20.11.0-linux-x64/bin:${HOME}/.local/bin:$PATH"
# 避免 lark-cli 警告 "requests will transit through proxy"
export LARK_CLI_NO_PROXY=1

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

# ========== JSON 读取 ==========
get_feishu_app_id() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get('feishu', {}).get('appId', ''))
except:
    print('')
PYEOF
}

get_feishu_app_secret() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get('feishu', {}).get('appSecret', ''))
except:
    print('')
PYEOF
}

get_lark_brand() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get('lark', {}).get('brand', 'feishu'))
except:
    print('feishu')
PYEOF
}

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

    if [ ! -f "$FEISHU_CONF" ]; then
        bad "❌ 配置文件不存在: $FEISHU_CONF"
        exit 1
    fi

    local app_id
    app_id=$(get_feishu_app_id)
    if [ -z "$app_id" ]; then
        bad "❌ conf-feishu.json 中未找到 feishu.appId"
        exit 1
    fi
    good "✓ 配置文件: $FEISHU_CONF"

    if [ $missing -eq 1 ]; then
        echo ""
        warn "请先运行 ubuntuinit.sh 完成基础环境配置"
        exit 1
    fi
}

# ========== 安装 lark-cli ==========
install_lark_cli() {
    title "安装 lark-cli"

    # 先设置 PATH，避免找不到命令
    export PATH="$HOME/.local/bin:$PATH"

    if command -v lark-cli &> /dev/null; then
        good "✓ lark-cli 已安装: $(lark-cli --version 2>/dev/null || lark-cli version 2>/dev/null || echo 'unknown')"
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

    # PATH 修复：npm 全局包在 ~/.local/bin/
    mkdir -p "$HOME/.local/bin"

    # npm 10.x 移除了 bin -g，直接使用 node_modules
    local npm_global_root
    npm_global_root=$(npm root -g 2>/dev/null || echo "$HOME/.local/node-v20.11.0-linux-x64/lib/node_modules")
    local lark_src="$npm_global_root/@larksuite/cli/bin/lark-cli.js"

    # 如果 bin/lark-cli.js 不存在，尝试其他路径
    if [ ! -f "$lark_src" ]; then
        lark_src="$npm_global_root/@larksuite/cli/bin/cli.js"
    fi

    # 尝试 scripts/run.js（lark-cli 实际入口）
    if [ ! -f "$lark_src" ]; then
        lark_src="$npm_global_root/@larksuite/cli/scripts/run.js"
    fi

    # 创建/更新符号链接
    if [ -f "$lark_src" ]; then
        rm -f "$HOME/.local/bin/lark-cli"  # 强制删除旧链接
        ln -sf "$lark_src" "$HOME/.local/bin/lark-cli"
    fi

    echo -n "验证安装 ... "
    if command -v lark-cli &> /dev/null; then
        good "✅ lark-cli 已可用"
    else
        bad "❌ lark-cli 不可用"
        return 1
    fi
}

# ========== 配置 lark-cli ==========
configure_lark_cli() {
    title "配置 lark-cli"

    export PATH="$HOME/.local/bin:$PATH"

    # 检查是否已配置
    if lark-cli config show 2>/dev/null | grep -q "appId"; then
        good "✓ lark-cli 已配置"
        lark-cli config show 2>/dev/null || true
        return 0
    fi

    local app_id app_secret brand
    app_id=$(get_feishu_app_id)
    app_secret=$(get_feishu_app_secret)
    brand=$(get_lark_brand)

    section "初始化配置"
    echo -n "配置 lark-cli ... "
    if echo "$app_secret" | lark-cli config init --app-id "$app_id" --app-secret-stdin --brand "$brand" 2>&1; then
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

    read -p "是否现在执行授权? [y/N]: " confirm || true
    confirm="${confirm:-n}"
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        lark-cli auth login --recommend || warn "授权可能需要浏览器完成"
    else
        echo ""
        info "后续手动授权: lark-cli auth login --recommend"
    fi
}

# ========== 状态检查 ==========
show_status() {
    title "状态检查"

    export PATH="$HOME/.local/bin:$PATH"

    section "lark-cli"
    echo -n "安装 ... "
    if command -v lark-cli &> /dev/null; then
        good "✓"
    else
        bad "❌"
    fi

    echo -n "配置 ... "
    if lark-cli config show 2>/dev/null | grep -q "appId"; then
        good "✓"
    else
        warn "○ 未配置"
    fi

    echo -n "授权 ... "
    if lark-cli config show 2>/dev/null | grep -q "users"; then
        good "✓"
    else
        warn "○ 未授权"
    fi
}

# ========== 主程序 ==========
main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         飞书初始化 - Feishu Init               ║"
    echo "║    安装配置 lark-cli（文档/日历/任务）         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"

    check_prerequisites
    install_lark_cli
    configure_lark_cli
    auth_lark_cli
    show_status

    echo ""
    title "✅ 飞书初始化完成"
    echo ""
    echo "提示："
    echo "- ccbot (Bridge WebSocket) 已拆分到 bridgeinit.sh，仅 Bridge 环境需要"
    echo "- 如需配置 ccbot，请运行: bash ccconfig/bridgeinit.sh"
    echo ""
}

main "$@"

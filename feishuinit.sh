#!/bin/bash
# 飞书初始化脚本
# 功能：安装配置 ccbot (bridge) 和 lark-cli
# 配置：从 conf-feishu.json 读取
# 目的：新 Ubuntu/WSL 环境快速打通飞书
#
# 使用：
#   bash ccconfig/feishuinit.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEISHU_CONF="$SCRIPT_DIR/conf-feishu.json"

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
read_json() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(json.dumps(data, ensure_ascii=False))
except Exception as e:
    print('{}')
PYEOF
}

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

get_ccbot_workdir() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get('ccbot', {}).get('workDir', '/home/francis'))
except:
    print('/home/francis')
PYEOF
}

get_ccbot_timeout() {
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)
    print(data.get('ccbot', {}).get('timeoutMs', '3600000'))
except:
    print('3600000')
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

# ========== 安装 ccbot ==========
install_ccbot() {
    title "安装 ccbot (Bridge)"

    if command -v ccbot &> /dev/null; then
        good "✓ ccbot 已安装: $(ccbot -V 2>/dev/null || echo 'unknown')"
        return 0
    fi

    section "npm 全局安装"
    echo -n "安装 @ccbot/cli ... "
    if npm install -g @ccbot/cli 2>&1; then
        good "✅ 安装成功"
    else
        bad "❌ 安装失败"
        return 1
    fi

    # PATH 修复：npm 全局包在 ~/.local/bin/
    mkdir -p "$HOME/.local/bin"

    # 方式1：直接从 npm 全局 bin 目录检查
    local npm_global_bin
    npm_global_bin=$(npm bin -g 2>/dev/null || echo "$HOME/.local/bin")
    local ccbot_src="$npm_global_bin/ccbot"

    # 方式2：如果方式1找不到，尝试 node_modules
    if [ ! -f "$ccbot_src" ]; then
        local npm_global_root
        npm_global_root=$(npm root -g 2>/dev/null || echo "$HOME/.local/node-v20.11.0-linux-x64/lib/node_modules")
        ccbot_src="$npm_global_root/@ccbot/cli/dist/server.js"
    fi

    # 创建符号链接
    if [ -f "$ccbot_src" ] && [ ! -e "$HOME/.local/bin/ccbot" ]; then
        ln -sf "$ccbot_src" "$HOME/.local/bin/ccbot" 2>/dev/null || true
    fi

    export PATH="$HOME/.local/bin:$PATH"

    echo -n "验证安装 ... "
    if command -v ccbot &> /dev/null; then
        good "✅ ccbot 已可用"
    else
        bad "❌ ccbot 不可用"
        return 1
    fi
}

# ========== 配置 ccbot ==========
configure_ccbot() {
    title "配置 ccbot"

    export PATH="$HOME/.local/bin:$PATH"

    local app_id app_secret workdir timeout
    app_id=$(get_feishu_app_id)
    app_secret=$(get_feishu_app_secret)
    workdir=$(get_ccbot_workdir)
    timeout=$(get_ccbot_timeout)

    # 如果已配置，跳过
    if [ -f "$workdir/ccbot.json" ]; then
        good "✓ ccbot 已配置: $workdir/ccbot.json"
    else
        section "创建配置文件"
        mkdir -p "$workdir"
        cat > "$workdir/ccbot.json" << EOF
{
  "feishu": {
    "appId": "$app_id",
    "appSecret": "$app_secret"
  },
  "claude": {
    "bin": "claude",
    "workDir": "$workdir",
    "timeoutMs": $timeout
  }
}
EOF
        good "✅ 已创建 $workdir/ccbot.json"
    fi

    section "启动 ccbot"
    echo -n "启动 ccbot ... "
    # ccbot 会在 workDir 目录查找 ccbot.json
    if (cd "$workdir" && ccbot start 2>&1); then
        good "✅ 启动成功"
        echo ""
        info "ccbot 由 pm2 管理，可使用以下命令："
        echo "  ccbot status  - 查看状态"
        echo "  ccbot logs     - 查看日志"
        echo "  ccbot restart  - 重启"
        echo "  ccbot stop     - 停止"
    else
        warn "⚠ 启动可能需要手动确认"
    fi
}

# ========== 配置 ccbot 自动启动 ==========
setup_ccbot_autostart() {
    title "配置 ccbot 自动启动"

    local workdir
    workdir=$(get_ccbot_workdir)
    local ccbot_bin="$HOME/.local/bin/ccbot"

    # 检查 crontab 是否已有 @reboot ccbot
    if crontab -l 2>/dev/null | grep -q "@reboot.*ccbot"; then
        good "✓ ccbot 自动启动已配置"
        return 0
    fi

    section "添加 crontab @reboot"
    # 添加到 crontab
    (crontab -l 2>/dev/null; echo "@reboot cd $workdir && $ccbot_bin start >> $workdir/ccbot.log 2>&1") | crontab -
    if [ $? -eq 0 ]; then
        good "✅ 已添加自动启动"
        echo ""
        info "ccbot 会在开机后自动启动"
    else
        bad "❌ 添加失败"
    fi
}

# ========== 安装 lark-cli ==========
install_lark_cli() {
    title "安装 lark-cli"

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

    # 方式1：直接从 npm 全局 bin 目录检查
    local npm_global_bin
    npm_global_bin=$(npm bin -g 2>/dev/null || echo "$HOME/.local/bin")
    local lark_src="$npm_global_bin/lark-cli"

    # 方式2：如果方式1找不到，尝试 node_modules
    if [ ! -f "$lark_src" ]; then
        local npm_global_root
        npm_global_root=$(npm root -g 2>/dev/null || echo "$HOME/.local/node-v20.11.0-linux-x64/lib/node_modules")
        lark_src="$npm_global_root/@larksuite/cli/bin/lark-cli.js"
    fi

    # 创建符号链接
    if [ -f "$lark_src" ] && [ ! -e "$HOME/.local/bin/lark-cli" ]; then
        ln -sf "$lark_src" "$HOME/.local/bin/lark-cli" 2>/dev/null || true
    fi

    export PATH="$HOME/.local/bin:$PATH"

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
    if lark-cli config list 2>/dev/null | grep -q "app_id"; then
        good "✓ lark-cli 已配置"
        lark-cli config list 2>/dev/null || true
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

# ========== 飞书开放平台配置 ==========
show_bridge_config() {
    title "飞书开放平台配置（长连接）"

    section "配置步骤"
    echo ""
    echo "需要在飞书开放平台配置长连接（WebSocket）接收消息："
    echo ""
    echo "1. 打开 https://open.feishu.cn/app/<your-feishu-app-id>"
    echo "2. 进入 事件与回调"
    echo "3. 订阅方式 选择 长连接（不是 Webhook）"
    echo "4. 添加事件: im.message.receive_v1（接收消息）"
    echo ""
    echo "配置好后，ccbot 会自动连接，你就能在飞书里和我对话了"
    echo ""
}

# ========== 状态检查 ==========
show_status() {
    title "状态检查"

    export PATH="$HOME/.local/bin:$PATH"

    section "ccbot"
    local workdir
    workdir=$(get_ccbot_workdir)
    echo -n "安装 ... "
    if command -v ccbot &> /dev/null; then
        good "✓"
    else
        bad "❌"
    fi

    echo -n "配置 ... "
    if [ -f "$workdir/ccbot.json" ]; then
        good "✓"
    else
        bad "❌"
    fi

    echo -n "自动启动 ... "
    if crontab -l 2>/dev/null | grep -q "@reboot.*ccbot"; then
        good "✓"
    else
        warn "○ 未配置"
    fi

    section "lark-cli"
    echo -n "安装 ... "
    if command -v lark-cli &> /dev/null; then
        good "✓"
    else
        bad "❌"
    fi

    echo -n "配置 ... "
    if lark-cli config list 2>/dev/null | grep -q "app_id"; then
        good "✓"
    else
        warn "○ 未配置"
    fi
}

# ========== 主程序 ==========
main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         飞书初始化 - Feishu Init                 ║"
    echo "║    安装配置 ccbot (bridge) 和 lark-cli           ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo "$NC"

    check_prerequisites
    install_ccbot
    configure_ccbot
    setup_ccbot_autostart
    install_lark_cli
    configure_lark_cli
    auth_lark_cli
    show_bridge_config
    show_status

    echo ""
    title "✅ 飞书初始化完成"
    echo ""
    echo "后续步骤："
    echo "1. 完成飞书开放平台的长连接配置（上面有步骤说明）"
    echo "2. 运行 lark-cli auth login --recommend 完成用户授权"
    echo ""
}

main "$@"

#!/bin/bash

# ==============================================
# Claude Code 配置脚本
# 功能：初始化或更新 Claude Code 的自定义 LLM API 配置
# 支持：交互式输入 或 读取 apillm.json
# ==============================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# 配置目录和文件
CLAUDE_DIR="$HOME/.claude"
CONFIG_FILE="$(dirname "$0")/apillm.json"

# -------------------------- 参数解析 --------------------------
show_usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -i, --init        初始化模式"
    echo "  -u, --update      更新模式"
    echo "  --url <URL>       API 基础地址"
    echo "  -k, --key <KEY>   API 密钥"
    echo "  -m, --model <MODEL>  模型名称"
    echo "  -h, --help        显示帮助"
    echo ""
}

MODE=""
BASE_URL=""
API_KEY=""
MODEL_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--init)
            MODE="init"
            shift
            ;;
        -u|--update)
            MODE="update"
            shift
            ;;
        --url)
            BASE_URL="$2"
            shift 2
            ;;
        -k|--key)
            API_KEY="$2"
            shift 2
            ;;
        -m|--model)
            MODEL_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "未知参数: $1"
            show_usage
            exit 1
            ;;
    esac
done

# -------------------------- 模式选择 --------------------------
if [[ -z "$MODE" ]]; then
    echo "请选择操作模式："
    echo "  1) 初始化 (init)  - 首次配置"
    echo "  2) 更新 (update)  - 修改现有配置"
    echo ""
    read -p "请输入选项 [1]: " choice
    choice="${choice:-1}"

    if [[ "$choice" == "1" ]]; then
        MODE="init"
    else
        MODE="update"
    fi
fi

echo ""
if [[ "$MODE" == "init" ]]; then
    echo "🚀 开始初始化 Claude Code 配置..."
else
    echo "🚀 开始更新 Claude Code 配置..."
fi
echo "=========================================="
echo ""

# -------------------------- 厂商选择 --------------------------
echo "请选择 LLM 订阅厂商："
echo "  1) MINIMAX"
echo ""
read -p "请输入选项 [1]: " vendor_choice
vendor_choice="${vendor_choice:-1}"

if [[ "$vendor_choice" == "1" ]]; then
    VENDOR="MINIMAX"
    print_info "已选择: $VENDOR"
else
    print_error "无效选项"
    exit 1
fi
echo ""

# -------------------------- 配置获取 --------------------------
IMPORTED=false

# 读取 apillm.json 配置模板
if [[ -f "$CONFIG_FILE" ]]; then
    CURRENT_URL=$(grep -o '"base_url": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    CURRENT_MODEL=$(grep -o '"model_name": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)

    echo "📋 $VENDOR 配置模板："
    echo "  API 地址: ${CURRENT_URL:-未设置}"
    echo "  模型:     ${CURRENT_MODEL:-未设置}"
    echo ""

    # 逐条询问用户
    echo "请逐项确认或修改配置："
    echo ""

    # Base URL
    echo -n "API 地址 [${CURRENT_URL}]: "
    read input
    BASE_URL="${input:-$CURRENT_URL}"

    # API Key
    echo ""
    echo "API Key 示例: sk-cp-xxx..."
    echo -n "API Key: "
    read -s input
    echo
    API_KEY="${input}"

    # Model Name
    echo ""
    echo -n "模型名称 [${CURRENT_MODEL}]: "
    read input
    MODEL_NAME="${input:-$CURRENT_MODEL}"

    IMPORTED=true
    print_info "已根据 $VENDOR 配置模板设置参数"
    echo ""
fi

# 如果没有 apillm.json，使用默认值
if [[ "$IMPORTED" == "false" ]]; then
    echo -n "API 基础地址 [https://api.minimaxi.com/anthropic]: "
    read input
    BASE_URL="${input:-https://api.minimaxi.com/anthropic}"

    echo ""
    echo "API Key 示例: sk-cp-xxx..."
    echo -n "API Key: "
    read -s input
    echo
    API_KEY="${input}"

    echo ""
    echo -n "模型名称 [MiniMax-M2.7]: "
    read input
    MODEL_NAME="${input:-MiniMax-M2.7}"
fi

# 验证
if [[ -z "$BASE_URL" || -z "$API_KEY" || -z "$MODEL_NAME" ]]; then
    print_error "配置不能为空"
    exit 1
fi

echo ""
print_info "📋 当前配置："
echo "  API 地址: $BASE_URL"
echo "  API Key:  ${API_KEY:0:15}..."
echo "  模型:     $MODEL_NAME"
echo ""

read -p "确认? [y/N]: " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "已取消"
    exit 0
fi

# -------------------------- 写入配置 --------------------------
mkdir -p "$CLAUDE_DIR"

# 1. 跳过登录引导
cat > "$HOME/.claude.json" << 'EOF'
{
    "hasCompletedOnboarding": true
}
EOF
print_success "已设置跳过登录引导"

# 2. 写入用户配置 (~/.claude.json) - 不参与同步
# 注意：API 配置写入 ~/.claude.json 而非 settings.json，避免被 sync-settings.js 同步
CLAUDE_JSON="$HOME/.claude.json"
if [[ -f "$CLAUDE_JSON" ]]; then
    # 合并配置，保留已有内容
    # 使用 jq 或 python 处理 JSON 合并
    if command -v python3 &> /dev/null; then
        python3 << PYEOF
import json
import os
config_file = os.path.expanduser("~/.claude.json")
try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except:
    config = {}
config.update({
    "hasCompletedOnboarding": True,
    "ANTHROPIC_BASE_URL": "$BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$API_KEY",
    "ANTHROPIC_MODEL": "$MODEL_NAME",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
})
with open(config_file, 'w') as f:
    json.dump(config, f, indent=4)
PYEOF
    else
        # 如果没有 python3，直接覆盖
        cat > "$CLAUDE_JSON" << EOF
{
    "hasCompletedOnboarding": true,
    "ANTHROPIC_BASE_URL": "$BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$API_KEY",
    "ANTHROPIC_MODEL": "$MODEL_NAME",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
}
EOF
    fi
else
    cat > "$CLAUDE_JSON" << EOF
{
    "hasCompletedOnboarding": true,
    "ANTHROPIC_BASE_URL": "$BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$API_KEY",
    "ANTHROPIC_MODEL": "$MODEL_NAME",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
}
EOF
fi
print_success "已配置 Claude Code 设置（写入 ~/.claude.json）"

# 3. 更新 ~/.bashrc
BASHRC="$HOME/.bashrc"
if grep -q "ANTHROPIC_BASE_URL" "$BASHRC" 2>/dev/null; then
    sed -i "s|export ANTHROPIC_BASE_URL=.*|export ANTHROPIC_BASE_URL=\"$BASE_URL\"|" "$BASHRC"
    sed -i "s|export ANTHROPIC_AUTH_TOKEN=.*|export ANTHROPIC_AUTH_TOKEN=\"$API_KEY\"|" "$BASHRC"
    sed -i "s|export ANTHROPIC_MODEL=.*|export ANTHROPIC_MODEL=\"$MODEL_NAME\"|" "$BASHRC"
    print_success "已更新 ~/.bashrc 环境变量"
else
    cat >> "$BASHRC" << EOF

# Claude Code 自定义 API 配置
export ANTHROPIC_BASE_URL="$BASE_URL"
export ANTHROPIC_AUTH_TOKEN="$API_KEY"
export ANTHROPIC_MODEL="$MODEL_NAME"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
EOF
    print_success "已添加环境变量到 ~/.bashrc"
fi

# -------------------------- 完成 --------------------------
echo ""
if [[ "$MODE" == "init" ]]; then
    echo "🎉 Claude Code 初始化完成！"
else
    echo "🎉 Claude Code 配置更新完成！"
fi
echo ""
echo "下一步操作："
echo "  1. 运行 'source ~/.bashrc' 加载环境变量"
echo "  2. 输入 'claude' 开始使用！"
echo ""
print_warning "API 密钥仅写入 Claude 配置，未保存到 apillm.json"
echo ""

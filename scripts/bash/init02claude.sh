#!/bin/bash

# ==============================================
# Claude Code 安装 + 配置脚本
# 功能：安装 Claude Code 并配置自定义 LLM API
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$REPO_DIR/config/apillm.json"

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

# -------------------------- Claude Code 安装检查 --------------------------
echo "=========================================="
echo "  📦 Claude Code 安装检查"
echo "=========================================="
echo ""

if command -v claude &> /dev/null; then
    # 提取版本号，例如从 "2.1.81 (Claude Code)" 中提取 "2.1.81"
    CURRENT_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "未知版本")
    print_success "Claude Code 已安装: $CURRENT_VERSION"

    # 获取最新版本
    print_info "检查最新版本..."
    LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/anthropics/claude-code/releases/latest 2>/dev/null | grep -o '"tag_name": *[^,]*' | cut -d'"' -f4 | sed 's/^v//')

    if [[ -z "$LATEST_VERSION" ]]; then
        LATEST_VERSION="$CURRENT_VERSION"  # 获取失败时假设已最新
    fi

    echo ""
    echo "最新版本: $LATEST_VERSION"

    # 比较版本
    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        echo ""
        print_info "✅ 已是最新版本，无需升级"
        upgrade_choice="2"
    else
        echo ""
        echo "发现新版本: $LATEST_VERSION (当前: $CURRENT_VERSION)"
        echo "是否升级？"
        echo "  1) 升级到最新版本"
        echo "  2) 保持当前版本"
        echo ""
        read -p "请输入选项 [2]: " upgrade_choice
        upgrade_choice="${upgrade_choice:-2}"

        if [[ "$upgrade_choice" == "1" ]]; then
            print_info "正在升级 Claude Code（使用官方安装脚本）..."
            if curl -fsSL https://claude.ai/install.sh | bash; then
                NEW_VERSION=$(claude --version 2>/dev/null | head -1 | sed 's/.* //')
                print_success "Claude Code 已升级: $CURRENT_VERSION → $NEW_VERSION"
            else
                print_error "升级失败，请检查网络"
                exit 1
            fi
        fi
    fi
else
    print_warning "Claude Code 未安装，正在安装..."
    echo ""

    print_info "使用官方安装脚本: curl -fsSL https://claude.ai/install.sh | bash"
    echo ""

    if curl -fsSL https://claude.ai/install.sh | bash; then
        NEW_VERSION=$(claude --version 2>/dev/null | head -1 | sed 's/.* //')
        print_success "Claude Code 安装成功: $NEW_VERSION"
    else
        print_error "安装失败，请检查网络"
        exit 1
    fi
fi

echo ""

# -------------------------- 显示当前配置 --------------------------
echo "=========================================="
echo "  📋 当前配置状态"
echo "=========================================="

# 读取当前配置
CURRENT_CONFIGURED="未配置"
if [[ -f "$HOME/.claude.json" ]]; then
    _key=$(grep -o '"ANTHROPIC_AUTH_TOKEN": *"[^"]*"' "$HOME/.claude.json" 2>/dev/null | cut -d'"' -f4)
    _url=$(grep -o '"ANTHROPIC_BASE_URL": *"[^"]*"' "$HOME/.claude.json" 2>/dev/null | cut -d'"' -f4)
    _model=$(grep -o '"ANTHROPIC_MODEL": *"[^"]*"' "$HOME/.claude.json" 2>/dev/null | cut -d'"' -f4)

    if [[ -n "$_key" && -n "$_url" && -n "$_model" ]]; then
        CURRENT_CONFIGURED="已配置"
        echo ""
        echo "  API 地址: ${_url}"
        echo "  API Key:  ${_key:0:15}..."
        echo "  模型:     $_model"
    fi
fi

if [[ "$CURRENT_CONFIGURED" == "未配置" ]]; then
    echo ""
    print_warning "尚未配置 API"
fi

echo ""
echo "=========================================="
echo "  ⚙️  请选择操作"
echo "=========================================="
echo ""
echo "  1) 保持现有配置"
echo "  2) 修改配置"
echo ""
read -p "请输入选项 [1]: " choice
choice="${choice:-1}"

if [[ "$choice" != "2" ]]; then
    echo ""
    print_info "已取消，保持现有配置"
    echo ""
    echo "========================================"
    echo "  📋 下一步操作"
    echo "========================================"
    echo ""
    echo "  1. 运行以下命令加载 PATH："
    echo "     source ~/.bashrc"
    echo ""
    echo "  2. 配置环境 + 建立符号链接："
    echo "     bash claude-config/scripts/bash/init03env.sh"
    echo ""
    exit 0
fi

echo ""
echo "🚀 开始配置 Claude Code API..."
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

# 检查是否已有 API Key
EXISTING_KEY=""
EXISTING_URL=""
EXISTING_MODEL=""
if [[ -f "$HOME/.claude.json" ]]; then
    # 先提取可能存在的 key（确保不为空才赋值）
    _key_raw=$(grep -o '"ANTHROPIC_AUTH_TOKEN": *"[^"]*"' "$HOME/.claude.json" 2>/dev/null | cut -d'"' -f4)
    _url_raw=$(grep -o '"ANTHROPIC_BASE_URL": *"[^"]*"' "$HOME/.claude.json" 2>/dev/null | cut -d'"' -f4)
    _model_raw=$(grep -o '"ANTHROPIC_MODEL": *"[^"]*"' "$HOME/.claude.json" 2>/dev/null | cut -d'"' -f4)
    # 只有非空才赋值
    [[ -n "$_key_raw" ]] && EXISTING_KEY="$_key_raw"
    [[ -n "$_url_raw" ]] && EXISTING_URL="$_url_raw"
    [[ -n "$_model_raw" ]] && EXISTING_MODEL="$_model_raw"
fi

# 读取 apillm.json 配置模板
if [[ -f "$CONFIG_FILE" ]]; then
    CURRENT_URL=$(grep -o '"base_url": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    CURRENT_MODEL=$(grep -o '"model_name": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)

    echo "📋 $VENDOR 配置模板："
    echo "  API 地址: ${CURRENT_URL:-未设置}"
    echo "  模型:     ${CURRENT_MODEL:-未设置}"
    echo ""

    KEY_CHOICE_SET=false
    if [[ -n "$EXISTING_KEY" ]]; then
        echo "📋 当前已有 API Key 配置："
        echo "  API 地址: ${EXISTING_URL:-未设置}"
        echo "  模型:     ${EXISTING_MODEL:-未设置}"
        echo "  Key:      ${EXISTING_KEY:0:15}..."
        echo ""
        echo "是否更新 API Key？"
        echo "  1) 更新 (输入新的 key)"
        echo "  2) 保留现有 key"
        echo ""
        read -p "请输入选项 [2]: " key_choice
        key_choice="${key_choice:-2}"
        KEY_CHOICE_SET=true
    fi

    # 逐条询问用户
    echo "请逐项确认或修改配置："
    echo ""

    # Base URL
    echo -n "API 地址 [${CURRENT_URL}]: "
    read input
    BASE_URL="${input:-$CURRENT_URL}"

    # API Key - 根据选择处理
    if [[ "$KEY_CHOICE_SET" == "true" && "$key_choice" == "1" ]] || [[ "$KEY_CHOICE_SET" == "false" ]]; then
        echo ""
        echo "API Key 示例: sk-cp-xxx..."
        echo -n "API Key: "
        read -s input
        echo
        API_KEY="${input}"
    else
        API_KEY="$EXISTING_KEY"
        echo ""
        echo "✅ 保留现有 API Key: ${EXISTING_KEY:0:15}..."
    fi

    if [[ -z "$API_KEY" ]]; then
        print_error "API Key 不能为空"
        exit 1
    fi

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
    KEY_CHOICE_SET=false
    if [[ -n "$EXISTING_KEY" ]]; then
        echo "📋 当前已有 API Key 配置："
        echo "  API 地址: ${EXISTING_URL:-未设置}"
        echo "  模型:     ${EXISTING_MODEL:-未设置}"
        echo "  Key:      ${EXISTING_KEY:0:15}..."
        echo ""
        echo "是否更新 API Key？"
        echo "  1) 更新 (输入新的 key)"
        echo "  2) 保留现有 key"
        echo ""
        read -p "请输入选项 [2]: " key_choice
        key_choice="${key_choice:-2}"
        KEY_CHOICE_SET=true
    fi

    echo -n "API 基础地址 [https://api.minimaxi.com/anthropic]: "
    read input
    BASE_URL="${input:-https://api.minimaxi.com/anthropic}"

    # 只有当用户选择更新 或 没有现有key需要输入时，才询问API Key
    if [[ "$KEY_CHOICE_SET" == "true" && "$key_choice" == "1" ]] || [[ "$KEY_CHOICE_SET" == "false" ]]; then
        echo ""
        echo "API Key 示例: sk-cp-xxx..."
        echo -n "API Key: "
        read -s input
        echo
        API_KEY="${input}"
    else
        API_KEY="$EXISTING_KEY"
        echo ""
        echo "✅ 保留现有 API Key: ${API_KEY:0:15}..."
    fi

    if [[ -z "$API_KEY" ]]; then
        print_error "API Key 不能为空"
        exit 1
    fi

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

# 确保 ~/.local/bin 在 PATH 中
LOCAL_BIN="$HOME/.local/bin"
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    if ! grep -q "\.local/bin" "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$LOCAL_BIN:$PATH"
fi

echo ""
echo "🎉 Claude Code 配置完成！"
echo ""
echo "========================================"
echo "  📋 下一步操作"
echo "========================================"
echo ""
echo "  1. 运行以下命令加载 PATH："
echo "     source ~/.bashrc"
echo ""
echo "  2. 配置环境 + 建立符号链接："
echo "     bash claude-config/scripts/bash/init03env.sh"
echo ""
if [[ "$key_choice" == "1" || ( -n "$API_KEY" && "$API_KEY" != "$EXISTING_KEY" ) ]]; then
    print_warning "API 密钥已更新并写入 ~/.claude.json"
else
    print_info "保留现有 API 密钥，未做更改"
fi
echo ""

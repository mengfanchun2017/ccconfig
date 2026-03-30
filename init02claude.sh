#!/bin/bash

# ==============================================
# Claude Code 安装 + 配置脚本
# 功能：安装 Claude Code 并配置自定义 LLM API
# 配置：从 initconf.json 读取
# ==============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/initconf.json"
CLAUDE_JSON="$HOME/.claude.json"
CLAUDE_DIR="$HOME/.claude"

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

# -------------------------- 读取配置 --------------------------
read_api_config() {
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        config = json.load(f)
    api = config.get('api', {})
    print(f"{api.get('base_url', '')}|{api.get('model', '')}|{api.get('key', '')}")
except:
    print("|||")
PYEOF
}

# -------------------------- Claude Code 安装检查 --------------------------
echo "=========================================="
echo "  📦 Claude Code 安装检查"
echo "=========================================="

export PATH="$HOME/.local/bin:$PATH"

if command -v claude &> /dev/null; then
    CURRENT_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "未知版本")
    print_success "Claude Code 已安装: $CURRENT_VERSION"
    print_info "检查最新版本..."
    LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/anthropics/claude-code/releases/latest 2>/dev/null | grep -o '"tag_name": *[^,]*' | cut -d'"' -f4 | sed 's/^v//')
    if [[ -z "$LATEST_VERSION" ]]; then
        LATEST_VERSION="$CURRENT_VERSION"
    fi
    echo ""
    echo "最新版本: $LATEST_VERSION"
    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        echo ""
        print_info "✅ 已是最新版本，无需升级"
    else
        print_info "发现新版本: $LATEST_VERSION (当前: $CURRENT_VERSION)"
        print_info "如需升级请运行: curl -fsSL https://claude.ai/install.sh | bash"
    fi
else
    print_warning "Claude Code 未安装"
    print_info "请运行官方安装脚本: curl -fsSL https://claude.ai/install.sh | bash"
fi

# -------------------------- 读取 API 配置 --------------------------
echo ""
echo "=========================================="
echo "  📋 API 配置"
echo "=========================================="

API_CONFIG=$(read_api_config)
IFS='|' read -r BASE_URL MODEL_NAME API_KEY <<< "$API_CONFIG"

echo ""
echo "  API 地址: ${BASE_URL}"
echo "  模型:     ${MODEL_NAME}"
echo "  API Key:  ${API_KEY:0:15}..."

# -------------------------- 写入配置 --------------------------
mkdir -p "$CLAUDE_DIR"

print_info "写入 Claude Code 配置..."

# 使用 python3 合并 JSON
python3 << PYEOF
import json
import os

config_file = os.path.expanduser("$CLAUDE_JSON")
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
print("ok")
PYEOF

print_success "Claude Code 配置完成！"
echo ""
print_info "运行 init03env.sh 完成环境配置"

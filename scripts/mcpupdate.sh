#!/bin/bash
# Claude Code MCP 自动更新脚本
# 作用：对比 mcplist.json，安装本地缺失的 MCP

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MCP_LIST_FILE="$REPO_DIR/mcplist.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info() { echo -e "${CYAN}$1${NC}"; }
echo_success() { echo -e "${GREEN}$1${NC}"; }
echo_warn() { echo -e "${YELLOW}$1${NC}"; }
echo_error() { echo -e "${RED}$1${NC}"; }

echo_info "========================================"
echo_info "  Claude Code MCP 自动更新"
echo_info "========================================"
echo ""

# 检查 mcplist.json 是否存在
if [ ! -f "$MCP_LIST_FILE" ]; then
    echo_error "❌ 未找到 mcplist.json"
    exit 1
fi

# 读取 MCP 列表（使用 node 解析 JSON）
echo_info "检查已安装的 MCP..."

# 获取已安装的 MCP 列表
INSTALLED_MCP=$(claude mcp list 2>&1 || true)

if echo "$INSTALLED_MCP" | grep -q "No MCP servers"; then
    echo "   当前没有安装任何 MCP"
    INSTALLED_LIST=""
else
    # 提取已安装的 MCP 名称
    INSTALLED_LIST=$(echo "$INSTALLED_MCP" | grep -oE "^\s+[a-zA-Z0-9_-]+" | sed 's/^[[:space:]]*//' | tr '\n' ' ')
fi

echo "   已安装: ${INSTALLED_LIST:-无}"
echo ""

# 解析 MCP 列表并安装
# 使用 node 解析 JSON
MCP_NAMES=$(node -e "
const list = require('$MCP_LIST_FILE');
list.mcp.forEach(m => console.log(m.name + '|' + (m.install || '') + '|' + (m.type || 'stdio')));
")

# 遍历 MCP 列表
while IFS='|' read -r name install_cmd type; do
    echo -n "检查: $name ... "

    if echo "$INSTALLED_LIST" | grep -qw "$name"; then
        echo_success "✅ 已安装"
        continue
    fi

    if [ "$type" = "http" ]; then
        echo_warn "⏳ 需要配置 (HTTP)"
    else
        if [ -n "$install_cmd" ]; then
            echo_error "❌ 未安装"

            echo "   安装命令: $install_cmd"

            # 解析命令
            cmd_args=($install_cmd)
            cmd="${cmd_args[0]}"
            args=("${cmd_args[@]:1}")

            echo "   执行: claude mcp add $name -- ${args[*]}"

            # 执行安装
            if claude mcp add "$name" -- "${args[@]}"; then
                echo_success "   ✅ 安装成功"
            else
                echo_error "   ❌ 安装失败"
            fi
        fi
    fi
done <<< "$MCP_NAMES"

echo ""
echo_info "========================================"
echo_info "  MCP 更新完成!"
echo_info "========================================"
echo ""
echo "提示: HTTP 类型的 MCP 包含敏感信息，请在本地 .claude.json 中配置"
echo ""

#!/bin/bash
# 飞书 MCP Bridge 安装脚本（可选组件）
# 用途: 给 Claude Code 安装 feishu MCP，用于 bot 消息收发
# 位置: ccconfig/feishu/mcp-bridge/
#
# 使用:
#   bash ccconfig/feishu/mcp-bridge/install.sh          # 安装
#   bash ccconfig/feishu/mcp-bridge/install.sh --remove # 移除
#
# 注意: 如果只需要文档/日历/任务操作，用 lark-cli 即可，不需要安装此组件

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MCP_NAME="feishu"
MCP_COMMAND="npx"
MCP_ARGS="-y @china-mcp/feishu-mcp"
FEISHU_APP_ID="<your-feishu-app-id>"
FEISHU_APP_SECRET="<your-feishu-app-secret>"
SETTINGS_FILE="$HOME/.claude/settings.json"

do_install() {
    echo -e "${CYAN}=== 安装飞书 MCP Bridge ===${NC}"
    echo ""

    if ! command -v claude &> /dev/null; then
        echo -e "${RED}❌ Claude Code 未安装${NC}"
        exit 1
    fi

    echo -n "注册 feishu MCP ... "
    if claude mcp add -s user "$MCP_NAME" -- $MCP_COMMAND $MCP_ARGS 2>&1 | grep -q "error\|Error\|failed\|Failed"; then
        echo -e "${RED}❌ 注册失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅${NC}"

    echo -n "配置环境变量 ... "
    python3 - "$SETTINGS_FILE" "$FEISHU_APP_ID" "$FEISHU_APP_SECRET" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
data['mcpServers']['feishu']['env'] = {
    'FEISHU_APP_ID': sys.argv[2],
    'FEISHU_APP_SECRET': sys.argv[3]
}
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
print('ok')
PYEOF
    echo -e "${GREEN}✅${NC}"

    echo ""
    echo -e "${GREEN}✅ 飞书 MCP Bridge 安装完成${NC}"
    echo ""
    echo "验证: claude mcp list | grep feishu"
    echo "移除: bash ccconfig/feishu/mcp-bridge/install.sh --remove"
}

do_remove() {
    echo -e "${YELLOW}=== 移除飞书 MCP Bridge ===${NC}"
    echo -n "移除 feishu MCP ... "
    if claude mcp remove -s user "$MCP_NAME" 2>&1 | grep -q "error\|Error\|failed\|Failed"; then
        echo -e "${RED}❌ 移除失败（可能未安装）${NC}"
    else
        echo -e "${GREEN}✅${NC}"
    fi
    echo -e "${GREEN}✅ 已移除${NC}"
}

case "${1:-}" in
    --remove|-r)
        do_remove
        ;;
    *)
        do_install
        ;;
esac

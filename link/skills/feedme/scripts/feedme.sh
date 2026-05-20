#!/bin/bash
# feedme.sh — Entry point: check MCP + show context overview.
# Claude handles the conversation; this just primes the pump.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check MCP
echo "🔍 检查 MCP 配置..."
if ! bash "$SKILL_DIR/scripts/setup.sh" --check 2>/dev/null; then
    echo ""
    echo "❌ 麦当劳 MCP 未配置"
    echo "   运行: bash scripts/setup.sh"
    echo "   获取Token: https://open.mcd.cn/mcp"
    exit 1
fi
echo "✅ MCP 已配置"
echo ""

# Show context
python3 "$SKILL_DIR/scripts/display.py" overview

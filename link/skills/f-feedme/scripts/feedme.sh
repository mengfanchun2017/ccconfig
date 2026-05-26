#!/bin/bash
# feedme.sh — Launch feedme overview. Claude runs this when user says "feedme".
set -euo pipefail
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! bash "$SKILL_DIR/scripts/setup.sh" --check 2>/dev/null; then
    echo "❌ 麦当劳 MCP 未配置。"
    echo ""
    echo "   快速安装："
    echo "   1. 获取 Token: https://open.mcd.cn/mcp"
    echo "   2. 运行安装: bash ~/.claude/skills/feedme/scripts/setup.sh"
    echo "   3. 回到此处输入 feedme"
    exit 1
fi

exec python3 "$SKILL_DIR/scripts/feedme.py" overview

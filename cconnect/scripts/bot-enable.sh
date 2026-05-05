#!/bin/bash
# ccconfig/cconnect/scripts/bot-enable.sh
# 功能：启用指定机器人
# 用法：bash ccconfig/cconnect/scripts/bot-enable.sh <bot_name>
#       bash ccconfig/cconnect/scripts/bot-enable.sh --list  列出所有机器人

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BOTS_JSON="$PROJECT_DIR/conf/bots.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

good() { echo -e "${GREEN}$1${NC}"; }
bad() { echo -e "${RED}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }

BOT_NAME="${1:-}"

if [ -z "$BOT_NAME" ] || [ "$BOT_NAME" = "--list" ]; then
    echo -e "${CYAN}可用机器人:${NC}"
    python3 - "$BOTS_JSON" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
for bot in data.get('bots', []):
    marker = '✅' if bot.get('enabled') else '❌'
    print(f"  {marker} {bot['name']}: {bot.get('description', '')}")
PYEOF
    echo ""
    echo "用法: bash ccconfig/cconnect/scripts/bot-enable.sh <bot_name>"
    exit 0
fi

# 检查 bot 是否存在
BOT_EXISTS=$(python3 - "$BOTS_JSON" "$BOT_NAME" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
for bot in data.get('bots', []):
    if bot['name'] == sys.argv[2]:
        print('yes')
        sys.exit(0)
print('no')
PYEOF
)

if [ "$BOT_EXISTS" = "no" ]; then
    bad "❌ 机器人 '$BOT_NAME' 不存在"
    echo "运行 bash scripts/bot-enable.sh --list 查看可用机器人"
    exit 1
fi

# 检查 feishuAppId 是否已配置
APP_ID=$(python3 - "$BOTS_JSON" "$BOT_NAME" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
for bot in data.get('bots', []):
    if bot['name'] == sys.argv[2]:
        print(bot.get('feishuAppId', ''))
        sys.exit(0)
PYEOF
)

if [ -z "$APP_ID" ]; then
    bad "❌ 机器人 '$BOT_NAME' 的 feishuAppId 未配置"
    warn "请先编辑 ccconfig/cconnect/conf/bots.json，填入 App ID 和 App Secret 后再启用"
    exit 1
fi

# 设置为 enabled = true
python3 - "$BOTS_JSON" "$BOT_NAME" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

updated = False
for bot in data.get('bots', []):
    if bot['name'] == sys.argv[2]:
        if bot.get('enabled'):
            print(f'⚠ {bot["name"]} 已经是启用状态')
            sys.exit(2)
        bot['enabled'] = True
        updated = True
        break

if updated:
    with open(sys.argv[1], 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f'✅ {sys.argv[2]} 已启用')
PYEOF

case $? in
    2) exit 0 ;;  # 已经是启用状态
    0) ;;
    *) exit 1 ;;
esac

# 重新生成配置并重启
echo ""
echo -e "${CYAN}重新生成配置并重启 cc-connect ...${NC}"
bash "$PROJECT_DIR/scripts/init.sh"

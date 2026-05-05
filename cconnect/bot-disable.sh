#!/bin/bash
# ccconfig/cconnect/bot-disable.sh
# 功能：禁用指定机器人
# 用法：bash ccconfig/cconnect/bot-disable.sh <bot_name>
#       bash ccconfig/cconnect/bot-disable.sh --list  列出已启用的机器人

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
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
    echo -e "${CYAN}已启用的机器人:${NC}"
    python3 - "$BOTS_JSON" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
enabled = [b for b in data.get('bots', []) if b.get('enabled')]
if not enabled:
    print("  (无)")
else:
    for bot in enabled:
        print(f"  ✅ {bot['name']}: {bot.get('description', '')}")
PYEOF
    echo ""
    echo "用法: bash ccconfig/cconnect/bot-disable.sh <bot_name>"
    exit 0
fi

# 检查是否能禁用（至少保留一个启用的 bot）
ENABLED_COUNT=$(python3 - "$BOTS_JSON" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
print(sum(1 for b in data.get('bots', []) if b.get('enabled')))
PYEOF
)

# 设置为 enabled = false
python3 - "$BOTS_JSON" "$BOT_NAME" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

updated = False
for bot in data.get('bots', []):
    if bot['name'] == sys.argv[2]:
        if not bot.get('enabled'):
            print(f'⚠ {bot["name"]} 已经是禁用状态')
            sys.exit(2)
        bot['enabled'] = False
        updated = True
        break

if not updated:
    print(f'❌ 机器人 "{sys.argv[2]}" 不存在')
    sys.exit(1)

with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(f'✅ {sys.argv[2]} 已禁用')
PYEOF

case $? in
    2) exit 0 ;;  # 已经是禁用状态
    1) exit 1 ;;  # 不存在
    0) ;;
esac

# 重新生成配置并重启
echo ""
echo -e "${CYAN}重新生成配置并重启 cc-connect ...${NC}"
bash "$PROJECT_DIR/init-cconnect.sh"

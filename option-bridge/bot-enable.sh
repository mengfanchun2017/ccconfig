#!/bin/bash
# ccconfig/option-bridge/bot-enable.sh — 启用 cc-connect 机器人
# 配置源: ../conf/feishu.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FEISHU_CONF="$CCCONFIG_DIR/conf/feishu.json"

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
    python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
for app in data.get('apps', []):
    cc = app.get('ccConnect', {})
    marker = '✅' if cc.get('enabled') else '❌'
    print(f"  {marker} {app['name']}: {app.get('description', '')}")
PYEOF
    echo ""
    echo "用法: bash ccconfig/option-bridge/bot-enable.sh <name>"
    exit 0
fi

python3 - "$FEISHU_CONF" "$BOT_NAME" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

name = sys.argv[2]
for app in data.get('apps', []):
    if app['name'] == name:
        cc = app.get('ccConnect', {})
        if not app.get('appId'):
            print(f'❌ {name} 的 appId 未配置')
            sys.exit(1)
        if cc.get('enabled'):
            print(f'⚠ {name} 已经是启用状态')
            sys.exit(2)
        cc['enabled'] = True
        with open(sys.argv[1], 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f'✅ {name} 已启用')
        sys.exit(0)

print(f'❌ 机器人 "{name}" 不存在')
sys.exit(1)
PYEOF

case $? in
    2) exit 0 ;;
    0) ;;
    *) exit 1 ;;
esac

echo ""
echo -e "${CYAN}重新生成配置并重启 cc-connect ...${NC}"
bash "$SCRIPT_DIR/init.sh" --cc-connect

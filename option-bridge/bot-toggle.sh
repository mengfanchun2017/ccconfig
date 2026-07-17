#!/bin/bash
# ccconfig/option-bridge/bot-toggle.sh — 启用/禁用 cc-connect 机器人
# 配置源: ../conf/feishu.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_DIR/lib/path-helper.sh"
source "$CCCONFIG_DIR/lib/colors.sh"
FEISHU_CONF="$(resolve_conf feishu.json)" || exit 1

ACTION=""
BOT_NAME=""

for arg in "$@"; do
    case "$arg" in
        --enable)  ACTION="enable" ;;
        --disable) ACTION="disable" ;;
        --list)    ACTION="list" ;;
        *)         BOT_NAME="$arg" ;;
    esac
done

if [ -z "$ACTION" ] && [ -n "$BOT_NAME" ]; then
    echo -e "${YELLOW}请指定 --enable 或 --disable${NC}"
    echo "用法: bash ccconfig/option-bridge/bot-toggle.sh <name> --enable|--disable"
    exit 1
fi

if [ "$ACTION" = "list" ] || [ -z "$BOT_NAME" ]; then
    echo -e "${CYAN}机器人状态:${NC}"
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
    echo "用法: bash ccconfig/option-bridge/bot-toggle.sh <name> --enable|--disable"
    exit 0
fi

python3 - "$FEISHU_CONF" "$BOT_NAME" "$ACTION" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

name = sys.argv[2]
action = sys.argv[3]
target_enabled = (action == "enable")

for app in data.get('apps', []):
    if app['name'] == name:
        cc = app.get('ccConnect', {})
        if not app.get('appId'):
            print(f'❌ {name} 的 appId 未配置')
            sys.exit(1)
        if cc.get('enabled') == target_enabled:
            state = "启用" if target_enabled else "禁用"
            print(f'⚠ {name} 已经是{state}状态')
            sys.exit(2)
        cc['enabled'] = target_enabled
        with open(sys.argv[1], 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        state = "启用" if target_enabled else "禁用"
        print(f'✅ {name} 已{state}')
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

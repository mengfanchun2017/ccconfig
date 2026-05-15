#!/bin/bash
# ccconfig/option-bridge/bot-status.sh — 查看 cc-connect 机器人状态
# 配置源: ../conf/feishu.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FEISHU_CONF="$CCCONFIG_DIR/conf/feishu.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}cc-connect 服务${NC}"
echo -n "  "
if systemctl --user is-active cc-connect.service &>/dev/null 2>&1; then
    echo -e "${GREEN}● 运行中${NC} (systemd)"
elif pgrep -f "cc-connect" > /dev/null 2>&1; then
    echo -e "${YELLOW}● 后台进程${NC} (PID: $(pgrep -f 'cc-connect' | head -1))"
else
    echo -e "${RED}○ 未运行${NC}"
fi

echo ""
echo -e "${BOLD}机器人列表${NC}"
echo ""

python3 - "$FEISHU_CONF" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
GRAY = '\033[0;90m'
NC = '\033[0m'

apps = data.get('apps', [])

print(f"  {'状态':<6} {'名称':<14} {'App ID':<28} {'工作目录':<32} {'模式':<12}")
print(f"  {'─'*6} {'─'*14} {'─'*28} {'─'*32} {'─'*12}")

for app in apps:
    name = app.get('name', '?')
    cc = app.get('ccConnect', {})
    enabled = cc.get('enabled', False)
    app_id = app.get('appId', '')
    work_dir = app.get('workDir', '')
    desc = app.get('description', '')
    perms = cc.get('permissions', {})
    admin_ids = perms.get('adminOpenIds', [])
    disabled_cmds = perms.get('disabledCommands', [])

    if enabled:
        status = f'{GREEN}✅ 启用{NC}'
    else:
        status = f'{RED}❌ 禁用{NC}'

    app_display = app_id[:22] + '...' if app_id else f'{GRAY}(未配置){NC}'

    if not admin_ids:
        perm_mode = f'{GRAY}开放{NC}'
    elif disabled_cmds:
        perm_mode = f'{YELLOW}受限{NC}'
    else:
        perm_mode = f'{GREEN}管理员{NC}'

    print(f"  {status:<16} {name:<14} {app_display:<28} {work_dir:<32} {perm_mode:<12}")

    if desc:
        print(f"  {'':6} {'':14} {GRAY}{desc}{NC}")
    if admin_ids:
        ids_str = ', '.join(admin_ids[:2])
        if len(admin_ids) > 2: ids_str += f' +{len(admin_ids)-2}'
        print(f"  {'':6} {'':14} 管理员: {ids_str}")
    if disabled_cmds:
        print(f"  {'':6} {'':14} 禁止命令: {', '.join(disabled_cmds)}")
    rl = perms.get('rateLimit', {})
    if rl:
        print(f"  {'':6} {'':14} 限频: {rl.get('maxMessages','?')}条/{rl.get('windowSecs','?')}秒")
    print()

total_cc = sum(1 for a in apps if a.get('ccConnect', {}).get('enabled'))
print(f"  共 {len(apps)} 个应用，{total_cc} 个 cc-connect 启用")
PYEOF

echo ""
echo -e "${GRAY}提示: bash ccconfig/option-bridge/bot-enable.sh <名称>   启用机器人${NC}"
echo -e "${GRAY}      bash ccconfig/option-bridge/bot-disable.sh <名称>  禁用机器人${NC}"
echo ""

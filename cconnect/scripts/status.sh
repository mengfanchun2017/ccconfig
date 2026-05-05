#!/bin/bash
# ccconfig/cconnect/scripts/status.sh
# 用法：bash ccconfig/cconnect/scripts/status.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BOTS_JSON="$PROJECT_DIR/conf/bots.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# ========== cc-connect 服务状态 ==========
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

echo -n "  配置路径: "
eval "$(python3 - "$BOTS_JSON" << 'PYEOF'
import json, sys
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
cc = data.get('cconnect', {})
print(f"config_path={cc.get('configPath', '?')}")
PYEOF
)"
echo "$config_path"

# ========== 机器人列表 ==========
echo ""
echo -e "${BOLD}机器人列表${NC}"
echo ""

python3 - "$BOTS_JSON" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r') as f:
    data = json.load(f)

bots = data.get('bots', [])

# 表头
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
GRAY = '\033[0;90m'
CYAN = '\033[0;36m'
BOLD = '\033[1m'
NC = '\033[0m'

print(f"  {'状态':<6} {'名称':<16} {'App ID':<28} {'工作目录':<32} {'权限模式':<14}")
print(f"  {'─'*6} {'─'*16} {'─'*28} {'─'*32} {'─'*14}")

for bot in bots:
    name = bot.get('name', '?')
    enabled = bot.get('enabled', False)
    app_id = bot.get('feishuAppId', '')
    work_dir = bot.get('workDir', '')
    desc = bot.get('description', '')
    perms = bot.get('permissions', {})
    admin_ids = perms.get('adminOpenIds', [])
    disabled_cmds = perms.get('disabledCommands', [])

    # 状态标记
    if enabled:
        status = f'{GREEN}✅ 启用{NC}'
    else:
        status = f'{RED}❌ 禁用{NC}'

    # App ID 显示（已配置/未配置）
    if app_id:
        # 显示前 20 个字符
        app_display = app_id[:22] + '...'
    else:
        app_display = f'{GRAY}(未配置){NC}'

    # 权限模式
    if not admin_ids:
        perm_mode = f'{GRAY}开放{NC}'
    else:
        if disabled_cmds:
            perm_mode = f'{YELLOW}受限{NC}'
        else:
            perm_mode = f'{GREEN}管理员{NC}'

    print(f"  {status:<16} {name:<16} {app_display:<28} {work_dir:<32} {perm_mode:<14}")

    if desc:
        print(f"  {'':6} {'':16} {GRAY}{desc}{NC}")

    # 显示权限详情
    if admin_ids:
        ids_str = ', '.join(admin_ids[:2])
        if len(admin_ids) > 2:
            ids_str += f' +{len(admin_ids)-2}'
        print(f"  {'':6} {'':16} 管理员: {ids_str}")
    if disabled_cmds:
        print(f"  {'':6} {'':16} 禁止命令: {', '.join(disabled_cmds)}")

    rl = perms.get('rateLimit', {})
    if rl:
        print(f"  {'':6} {'':16} 频率限制: {rl.get('maxMessages', '?')}条/{rl.get('windowSecs', '?')}秒")

    print()

print(f"  共 {len(bots)} 个机器人，{sum(1 for b in bots if b.get('enabled'))} 个启用")
PYEOF

echo ""
echo -e "${GRAY}提示: bash ccconfig/cconnect/scripts/bot-enable.sh <名称>   启用机器人${NC}"
echo -e "${GRAY}      bash ccconfig/cconnect/scripts/bot-disable.sh <名称>  禁用机器人${NC}"
echo -e "${GRAY}      bash ccconfig/cconnect/scripts/init.sh --dry-run      预览配置${NC}"
echo ""

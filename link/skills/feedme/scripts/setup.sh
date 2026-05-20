#!/bin/bash
# setup.sh — Install/check McDonald's MCP configuration for feedme
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
CONF_FILE="$HOME/.claude/projects/-home-francis-git/conf/feedme/feedme.json"
MCP_KEY="mcd-mcp"

check_mcp() {
    if [ ! -f "$SETTINGS_FILE" ]; then
        return 1
    fi
    python3 -c "
import json, sys
d = json.load(open('$SETTINGS_FILE'))
ok = 'mcpServers' in d and '$MCP_KEY' in d['mcpServers']
sys.exit(0 if ok else 1)
" 2>/dev/null
}

get_existing_token() {
    if [ -f "$CONF_FILE" ]; then
        python3 -c "
import json
d = json.load(open('$CONF_FILE'))
print(d.get('mcd', {}).get('token', ''))
" 2>/dev/null
    fi
}

install_mcp() {
    local token="$1"
    local py_script
    py_script=$(cat << 'PYEOF'
import json, os, sys

token = sys.argv[1]
conf_file = sys.argv[2]
settings_file = sys.argv[3]
mcp_key = sys.argv[4]

# Write token to conf
os.makedirs(os.path.dirname(conf_file), exist_ok=True)
if os.path.exists(conf_file):
    with open(conf_file) as f:
        data = json.load(f)
else:
    data = {}
data.setdefault('mcd', {})['token'] = token
data['mcd']['mcp_configured'] = True
with open(conf_file, 'w') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print('OK: token saved to feedme.json')

# Write to settings.json
with open(settings_file) as f:
    sdata = json.load(f)
sdata.setdefault('mcpServers', {})[mcp_key] = {
    "type": "streamablehttp",
    "url": "https://mcp.mcd.cn",
    "headers": {"Authorization": f"Bearer {token}"}
}
with open(settings_file, 'w') as f:
    json.dump(sdata, f, ensure_ascii=False, indent=2)
print('OK: MCP server added to settings.json')
print()
print('⚠️  请重启 Claude Code 使 MCP 配置生效')
PYEOF
)
    python3 -c "$py_script" "$token" "$CONF_FILE" "$SETTINGS_FILE" "$MCP_KEY"
}

remove_mcp() {
    python3 -c "
import json
f='$SETTINGS_FILE'
d=json.load(open(f))
d.get('mcpServers',{}).pop('$MCP_KEY',None)
json.dump(d, open(f,'w'), ensure_ascii=False, indent=2)
print('OK: MCP removed from settings.json')
"
}

case "${1:-}" in
    --check|-c)
        if check_mcp; then
            echo "MCP_CHECK:OK"
            exit 0
        else
            echo "MCP_CHECK:MISSING"
            exit 1
        fi
        ;;
    --update|-u)
        echo "=== feedme MCP 更新 ==="
        echo ""
        echo -n "请输入麦当劳 MCP Token: "
        read -r token
        [ -z "$token" ] && { echo "Token 不能为空"; exit 1; }
        install_mcp "$token"
        ;;
    --remove)
        remove_mcp
        ;;
    *)
        echo "╔══════════════════════════════════════════════╗"
        echo "║       🍔  feedme - 麦当劳 MCP 安装向导       ║"
        echo "╚══════════════════════════════════════════════╝"
        echo ""
        if check_mcp; then
            echo "✅ 麦当劳 MCP 已配置"
            existing=$(get_existing_token)
            if [ -n "$existing" ]; then
                echo "   Token: ${existing:0:8}...${existing: -4}"
            fi
            echo ""
            echo "重新配置: bash setup.sh --update"
            echo "删除配置: bash setup.sh --remove"
            exit 0
        fi
        echo "未检测到麦当劳 MCP 配置。"
        echo ""
        echo "获取 Token 步骤："
        echo "  1. 打开 https://open.mcd.cn/mcp"
        echo "  2. 手机号验证登录"
        echo "  3. 进入控制台 → 点击「激活」"
        echo "  4. 同意服务协议 → 复制生成的 Token"
        echo ""
        echo -n "请粘贴 MCP Token: "
        read -r token
        [ -z "$token" ] && { echo "Token 不能为空，安装取消。"; exit 1; }
        install_mcp "$token"
        echo ""
        echo "✅ 安装完成！请重启 Claude Code 后使用 feedme。"
        ;;
esac

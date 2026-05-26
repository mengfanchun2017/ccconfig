#!/bin/bash
# setup.sh — Install/check McDonald's MCP configuration for feedme
set -euo pipefail

CONF_FILE="$HOME/.claude/projects/-home-francis-git/conf/feedme/feedme.json"

check_mcp() {
    if [ ! -f "$CONF_FILE" ]; then
        return 1
    fi
    python3 -c "
import json, sys
d = json.load(open('$CONF_FILE'))
ok = d.get('mcd', {}).get('token', '')
sys.exit(0 if ok else 1)
" 2>/dev/null
}

install_token() {
    local token="$1"
    python3 -c "
import json, os, sys
conf_file = sys.argv[1]
token = sys.argv[2]
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
" "$CONF_FILE" "$token"
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
        install_token "$token"
        ;;
    *)
        echo "╔══════════════════════════════════════════════╗"
        echo "║       🍔  feedme - 麦当劳 MCP 安装向导       ║"
        echo "╚══════════════════════════════════════════════╝"
        echo ""
        if check_mcp; then
            echo "✅ 麦当劳 MCP 已配置"
            echo ""
            echo "重新配置: bash setup.sh --update"
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
        install_token "$token"
        echo ""
        echo "✅ 安装完成！现在可以使用 feedme 了。"
        ;;
esac

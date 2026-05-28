#!/bin/bash
# lark-current.sh — 可被 source 的飞书账号查询
# 供 status.sh / monitor.sh 等其他脚本复用
#
# 用法:
#   source ccconfig/option-bridge/lark-current.sh
#   echo "$LARK_ACCOUNT_NAME"    # francis / ailab / "" (none)
#   echo "$LARK_CONFIG_DIR"      # ~/.lark-cli-francis / ...
#
# 也可直接执行:
#   bash ccconfig/option-bridge/lark-current.sh      # 输出账号名
#   bash ccconfig/option-bridge/lark-current.sh -v   # 详细输出

# 颜色（仅在直接执行时使用）
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    GRAY='\033[0;90m'
    NC='\033[0m'
fi

# 探测当前账号
_detect_lark_account() {
    local current_dir="${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli}"
    current_dir="$(eval echo "$current_dir")"

    # 1. 从 marker 文件读
    local marker_file="$HOME/.lark-cli-account"
    if [ -f "$marker_file" ]; then
        local marker_name marker_dir
        marker_name=$(grep '^name=' "$marker_file" 2>/dev/null | cut -d'=' -f2)
        marker_dir=$(grep '^configDir=' "$marker_file" 2>/dev/null | cut -d'=' -f2)
        if [ -n "$marker_name" ]; then
            LARK_ACCOUNT_NAME="$marker_name"
            LARK_CONFIG_DIR="${marker_dir:-$current_dir}"
            return
        fi
    fi

    # 2. 从 configDir 匹配 feishu.json apps[]
    local feishu_conf
    feishu_conf="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../conf/feishu.json"
    if [ -f "$feishu_conf" ]; then
        local matched
        matched=$(python3 - "$feishu_conf" "$current_dir" << 'PYEOF' 2>/dev/null
import json, sys, os
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
target = os.path.expanduser(sys.argv[2])
for app in data.get('apps', []):
    lark = app.get('larkCli', {})
    if lark.get('enabled'):
        cd = os.path.expanduser(lark.get('configDir', '~/.lark-cli'))
        if cd == target:
            print(app.get('name', ''))
            break
PYEOF
        )
        if [ -n "$matched" ]; then
            LARK_ACCOUNT_NAME="$matched"
            LARK_CONFIG_DIR="$current_dir"
            return
        fi
    fi

    # 3. 按 appId 回退匹配（configDir 不匹配时，从 config.json 读取 appId 来匹配）
    if [ -f "$feishu_conf" ] && [ -f "$current_dir/config.json" ]; then
        local app_id_matched
        app_id_matched=$(python3 - "$feishu_conf" "$current_dir" << 'PYEOF' 2>/dev/null
import json, sys, os
with open(sys.argv[1], 'r') as f:
    data = json.load(f)
cfg = json.load(open(os.path.join(sys.argv[2], 'config.json')))
cfg_app_id = cfg.get('apps', [{}])[0].get('appId', '')
if cfg_app_id:
    for app in data.get('apps', []):
        if app.get('larkCli', {}).get('enabled') and app.get('appId') == cfg_app_id:
            print(json.dumps({'name': app['name'], 'configDir': os.path.expanduser(app.get('larkCli', {}).get('configDir', '~/.lark-cli'))}))
            break
PYEOF
        )
        if [ -n "$app_id_matched" ]; then
            LARK_ACCOUNT_NAME=$(echo "$app_id_matched" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
            LARK_CONFIG_DIR=$(echo "$app_id_matched" | python3 -c "import json,sys; print(json.load(sys.stdin)['configDir'])")
            return
        fi
    fi

    # 4. 未匹配
    LARK_ACCOUNT_NAME=""
    LARK_CONFIG_DIR="$current_dir"
}

_detect_lark_account

# 探测工作目录（CC小能手）
_detect_lark_workspace() {
    local ws_file="$HOME/.claude/lark-workspace.json"
    if [ -f "$ws_file" ]; then
        LARK_WORKSPACE_NAME=$(python3 -c "import json;d=json.load(open('$ws_file'));print(d['workspace']['name'])" 2>/dev/null)
        LARK_WORKSPACE_NODE=$(python3 -c "import json;d=json.load(open('$ws_file'));print(d['workspace']['nodeToken'])" 2>/dev/null)
        LARK_WORKSPACE_SPACE_ID=$(python3 -c "import json;d=json.load(open('$ws_file'));print(d['workspace']['spaceId'])" 2>/dev/null)
        LARK_WORKSPACE_URL=$(python3 -c "import json;d=json.load(open('$ws_file'));print(d['workspace']['url'])" 2>/dev/null)
    fi
}

_detect_lark_workspace

# 直接执行时输出
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ "${1:-}" = "-v" ] || [ "${1:-}" = "--verbose" ]; then
        echo -e "账号:   ${GREEN}${LARK_ACCOUNT_NAME:-(none)}${NC}"
        echo -e "配置目录: ${GRAY}${LARK_CONFIG_DIR}${NC}"
        if [ -n "$LARK_ACCOUNT_NAME" ]; then
            marker_file="$HOME/.lark-cli-account"
            if [ -f "$marker_file" ]; then
                switched_at=$(grep '^switchedAt=' "$marker_file" 2>/dev/null | cut -d'=' -f2-)
                [ -n "$switched_at" ] && echo -e "切换时间: ${GRAY}${switched_at}${NC}"
            fi
        fi
        if [ -n "${LARK_WORKSPACE_NAME:-}" ]; then
            echo -e "工作目录: ${GREEN}${LARK_WORKSPACE_NAME}${NC}"
            echo -e "  wiki:   ${GRAY}${LARK_WORKSPACE_URL:-}${NC}"
        fi
    else
        if [ -n "$LARK_ACCOUNT_NAME" ]; then
            echo "$LARK_ACCOUNT_NAME"
        fi
    fi
fi

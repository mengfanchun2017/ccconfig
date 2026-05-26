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

    # 3. 未匹配
    LARK_ACCOUNT_NAME=""
    LARK_CONFIG_DIR="$current_dir"
}

_detect_lark_account

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
    else
        if [ -n "$LARK_ACCOUNT_NAME" ]; then
            echo "$LARK_ACCOUNT_NAME"
        fi
    fi
fi

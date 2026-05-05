#!/bin/bash
# ccconfig/feishu/init-cconnect.sh
# 兼容重定向 → ccconfig/cconnect/scripts/init.sh
#
# 使用：
#   bash ccconfig/feishu/init-cconnect.sh   # 完整安装+配置

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCONNECT_INIT="$SCRIPT_DIR/../cconnect/scripts/init.sh"

if [ -x "$CCONNECT_INIT" ]; then
    exec bash "$CCONNECT_INIT" "$@"
else
    echo "❌ cconnect/scripts/init.sh 不存在"
    exit 1
fi

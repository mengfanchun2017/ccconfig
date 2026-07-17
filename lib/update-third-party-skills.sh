#!/bin/bash
# 更新所有 skill（CLI 工具 + npx skills）→ 委托 init-skill.sh update
#
# 用法：bash lib/update-third-party-skills.sh
# 等价：bash ccconfig/init-skill.sh update

export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/../init-skill.sh" update

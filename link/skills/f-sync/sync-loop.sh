#!/usr/bin/env bash
# f-sync polling daemon — 循环执行 sync.py，间隔由 config.json 决定
set -euo pipefail
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

CONFIG_FILE="${HOME}/.config/f-sync/config.json"

# 取所有 job 中最短的 interval_seconds
INTERVAL=$(python3 -c "
import json, os
with open(os.path.expanduser('$CONFIG_FILE')) as f:
    cfg = json.load(f)
iv = min((j.get('interval_seconds', 30) for j in cfg.get('jobs', [])), default=30)
print(iv)
")

echo "[f-sync] 轮询模式启动，间隔 ${INTERVAL}s"

while true; do
    python3 "$SCRIPT_DIR/sync.py"
    sleep "$INTERVAL"
done

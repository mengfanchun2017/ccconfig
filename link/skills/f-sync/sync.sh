#!/usr/bin/env bash
# f-sync 入口 — 委托 sync.py 执行
set -euo pipefail
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
exec python3 "$SCRIPT_DIR/sync.py" "$@"

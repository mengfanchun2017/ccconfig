#!/bin/bash
# bridge-restart.sh — 重探候选路径 + 起 openai_bridge.py
# 被 bridge watchdog / selfheal 调用：环境可能已变（单位↔家），重启时重探选最佳 upstream
#
# 用法: bridge-restart.sh <cfg> <preset> <model> <key> <port>
# 返回：后台启动 bridge 进程，自身退出

set -uo pipefail

CCCONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$CCCONFIG_ROOT/lib/ensure-bridge.sh"

cfg="${1:-}" preset="${2:-}" model="${3:-}" key="${4:-}" port="${5:-${BRIDGE_PORT:-8898}}"

[[ -z "$cfg" || -z "$preset" || -z "$model" || -z "$key" ]] && exit 1

picked=$(pick_best_upstream_live "$cfg" "$preset")
up="${picked%%|*}"
hh="${picked#*|}"
[[ -z "$up" ]] && exit 1

# kill 端口旧进程
old=$( { lsof -ti :"$port" 2>/dev/null || true; } | head -1 || true)
[[ -n "$old" ]] && kill "$old" 2>/dev/null || true
sleep 1

extra_args=""
[[ "$up" == https:* ]] && extra_args="--skip-tls-verify"
win_curl=""
if command -v curl.exe &>/dev/null && [[ "$up" =~ ://(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
    win_curl="--use-win-curl"
fi

cd "$CCCONFIG_ROOT" || exit 1
env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
    OPENAI_BRIDGE_UPSTREAM="$up" OPENAI_BRIDGE_KEY="$key" OPENAI_BRIDGE_MODEL="$model" OPENAI_BRIDGE_HOST="$hh" \
    python3 option-llmswitch/openai_bridge.py --port "$port" $extra_args $win_curl \
    >> "$HOME/.cache/openai_bridge.log" 2>&1 &
disown 2>/dev/null || true

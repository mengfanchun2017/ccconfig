#!/bin/bash
# bridge-restart.sh — 按当前 preset 重启 openai_bridge.py
#
# 用法: bridge-restart.sh <llm.json> [<preset>]
#   preset 省略时读 ~/.claude/llm-current
# 返回: 0=已就绪 / 当前 preset 不需要 bridge；1=配置或启动失败
#
# why 自动读配置：旧版从调用方命令行取 upstream/model/key，而 watchdog 是启动时
# 一次性生成 wrapper 的，切 preset 后老 watchdog 仍用旧 upstream 重启 bridge，把
# 用户刚选的 preset 覆盖掉（在家切 tailscale 后被换成单位地址 → 全挂）。

set -uo pipefail

CCCONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cfg="${1:-}"
[[ -z "$cfg" || ! -f "$cfg" ]] && exit 1
preset="${2:-}"
[[ -z "$preset" ]] && preset="$(tr -d '[:space:]' < "$HOME/.claude/llm-current" 2>/dev/null || true)"
[[ -z "$preset" ]] && exit 0

# 读 preset 配置；use_bridge 三态 → true/false/空
IFS='|' read -r use_bridge up model key hh <<< "$(python3 - "$cfg" "$preset" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("|||"); raise SystemExit(0)
llm = d.get('llms', {}).get(sys.argv[2], {})
ub = llm.get('use_bridge')
flag = 'true' if ub is True else ('false' if ub is False else '')
print(f"{flag}|{llm.get('base_url','')}|{llm.get('model','')}|{llm.get('key','')}|{llm.get('host_header','')}")
PY
)"

# 当前 preset 不走 bridge（直连/显式 false/字段缺失）→ 不是故障，不拉起
[[ "$use_bridge" != "true" ]] && exit 0
[[ -z "$up" || -z "$key" || -z "$model" ]] && exit 1

port="${BRIDGE_PORT:-8898}"
old=$( { lsof -ti :"$port" 2>/dev/null || true; } | head -1 || true)
[[ -n "$old" ]] && kill "$old" 2>/dev/null || true
sleep 1

extra_args=""
[[ "$up" == https:* ]] && extra_args="--skip-tls-verify"
win_curl=""
if command -v curl.exe &>/dev/null && [[ "$up" =~ ://(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.) ]]; then
    win_curl="--use-win-curl"
fi

cd "$CCCONFIG_ROOT" || exit 1
mkdir -p "$HOME/.cache"   # 目录不存在会让重定向失败、bridge 起不来
env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
    OPENAI_BRIDGE_UPSTREAM="$up" OPENAI_BRIDGE_KEY="$key" OPENAI_BRIDGE_MODEL="$model" OPENAI_BRIDGE_HOST="$hh" \
    python3 option-llmswitch/openai_bridge.py --port "$port" $extra_args $win_curl \
    >> "$HOME/.cache/openai_bridge.log" 2>&1 &
disown 2>/dev/null || true
exit 0

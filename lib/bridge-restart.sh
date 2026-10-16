#!/bin/bash
# bridge-restart.sh — 按当前 preset 重启 openai_bridge.py（watchdog 专用入口）
#
# 用法: bridge-restart.sh <llm.json> [<preset>]
#   preset 省略时读 ~/.claude/llm-current
# 返回: 0=已就绪（health 已确认）
#       3=当前 preset 不需要 bridge（直连）→ supervisor 据此退出（不该空转）
#       1=瞬时失败（启动后 health 未起，可重试）
#       2=永久性错误（preset 已删除 / 配置不可用）→ watchdog 据此长退避
#
# why 自动读配置：旧版从调用方命令行取 upstream/model/key，而 watchdog 是启动时
# 一次性生成 wrapper 的，切 preset 后老 watchdog 仍用旧 upstream 重启 bridge，把
# 用户刚选的 preset 覆盖掉（在家切 tailscale 后被换成单位地址 → 全挂）。
#
# 本文件不自己实现任何判定与 spawn：模式判定用 preset_bridge_mode、传输栈用
# bridge_win_curl、拉起用 _bridge_spawn，全部来自 ensure-bridge.sh。旧版把
# 「是否需要 bridge」和 win_curl 正则各抄了一份，已经漂移过一次（域名上游首启
# 走 win_curl、watchdog 一重启就退回 httpx）。

set -uo pipefail

CCCONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 只 source 函数定义，不触发其中的顶层逻辑
source "$CCCONFIG_ROOT/lib/ensure-bridge.sh"

cfg="${1:-}"
[[ -z "$cfg" || ! -f "$cfg" ]] && exit 2   # 缓存缺失：重试无意义
preset="${2:-}"
[[ -z "$preset" ]] && preset="$( [[ -f "$HOME/.claude/llm-current" ]] && tr -d '[:space:]' < "$HOME/.claude/llm-current" || true )"
[[ -z "$preset" ]] && exit 2   # 无 preset 可拉起：等 llm-current 被写入

# 接入模式：与 switch_llm / test_llm 同源，不再自写一份
mode="$(preset_bridge_mode "$preset" "$cfg")" || exit 2
[[ "$mode" == "direct" ]] && exit 3      # 当前 preset 不需要 bridge：让 supervisor 退出，不该空转
[[ "$mode" == "conflict" ]] && exit 2    # OpenAI-only + 显式直连，重试无意义

bc="$(read_bridge_config "$cfg" "$preset")" || exit 2
IFS='|' read -r up model key hh <<< "$bc"
[[ -z "$up" || -z "$key" || -z "$model" ]] && exit 2   # preset 配置不完整/已删除

port="${BRIDGE_PORT:-8898}"
_kill_by_port "$port"
win_curl="$(bridge_win_curl "$up" "$cfg" "$preset")"
_bridge_spawn "$up" "$model" "$key" "$hh" "$win_curl" "$port"

# 等 health 确认真的起来了：旧版无条件 exit 0，watchdog 永远学不到"启动失败"，
# 只能靠下一轮的 health 间接推断
for _i in 1 2 3 4 5; do
    sleep 1
    curl -s --max-time 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1 && exit 0
done
exit 1

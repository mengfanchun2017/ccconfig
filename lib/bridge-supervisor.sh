#!/bin/bash
# bridge-supervisor.sh — bridge 前台守护循环（两路共用）
#
# 用法: bridge-supervisor.sh <merged_cfg> [<fallback_preset>]
#
# 同一份脚本既作 systemd 服务的 ExecStart（Type=simple，前台跑），又作
# shell watchdog（setsid 后台跑）。此前前台循环是 start_bridge_watchdog 里用
# heredoc 生成的一次性 wrapper —— 生成出来的脚本无法被 unit 引用，systemd 化就得
# 再抄一份循环，两处必然漂移。抽成实体文件后：改一处，两路同时生效。
#
# 职责只有「巡检 + 拉起」，拉起仍走 bridge-restart.sh（→ preset_bridge_mode /
# read_bridge_config / bridge_win_curl / _bridge_spawn），判定与传输栈不在这里重写。
#
# 退出语义（与 unit 的 Restart=on-failure 配合，避免重启风暴）：
#   0 = 当前 preset 直连、无需 bridge → 主动退出，systemd 不再拉起
#   非0 = 异常 → 交给 systemd 重启（shell 模式下由调用方决定）

set -uo pipefail

CCCONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 端口解析与 ensure-bridge.sh 同源（本脚本不 source 它：那是函数库，顶层有逻辑）。
# mirrored 多发行版并存时各发行版需不同端口，见 ensure-bridge.sh 顶部说明。
_bridge_port_file="$HOME/.claude/bridge-port"
if [[ -z "${BRIDGE_PORT:-}" && -r "$_bridge_port_file" ]]; then
    BRIDGE_PORT="$(tr -d '[:space:]' < "$_bridge_port_file")"
fi
BRIDGE_PORT="${BRIDGE_PORT:-8898}"
unset _bridge_port_file
BRIDGE_WD_PID="${BRIDGE_WD_PID:-$HOME/.cache/bridge-watchdog.pid}"
BRIDGE_WD_LOG="${BRIDGE_WD_LOG:-$HOME/.cache/bridge-watchdog.log}"

cfg="${1:-}"
initial_preset="${2:-}"

mkdir -p "$HOME/.cache"
# 自记 PID：调用方拿到的 $! 是 setsid 的 pid，而 setsid 成为进程组长时会 fork，
# 于是父进程写进 PID 文件的是那个短命进程 —— 文件里的值长期是错的。
# systemd 模式下不写这个文件：PID 由 systemd 自己跟踪（MainPID），写进去反而会让
# bridge_state_check / stop_bridge_watchdog 把「服务」当成「shell watchdog」处理。
[[ -z "${INVOCATION_ID:-}" ]] && echo $$ > "$BRIDGE_WD_PID"

_wd_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$BRIDGE_WD_LOG"; }

# 被守护文件的指纹 —— 用于检出「磁盘代码已更新、内存里跑的还是旧代码」。
# ccconfig 由 auto-sync 自动 git pull，bridge.py 随时可能被更新；不重启则
# 旧代码一直服务到进程自然退出，期间行为与新代码不一致且无任何提示。
#
# 只指纹 openai_bridge.py —— 它是**常驻进程**加载的代码，改了必须重启才生效。
# 不能把 ensure-bridge.sh / bridge-restart.sh 也算进来：它们是**每次调用都重新
# 读盘**的 shell 脚本，本来就实时生效，无需重启 bridge。放进来会造成「改一个 shell
# 脚本 → supervisor 把好好的 bridge 杀掉重启 → 用户 session 瞬间 ECONNREFUSED」，
# 而那时根本没有任何请求需要中断（实测踩过）。
_code_fingerprint() {
    md5sum < "$CCCONFIG_ROOT/option-llmswitch/openai_bridge.py" 2>/dev/null | cut -d' ' -f1
}

# 代码漂移的处理策略：**只告警，不自动重启**。
#
# why 不自动部署：一个正在正常服务的 bridge 跑旧代码是可接受的代价；为了套用新代码
#     把它杀掉，代价是「每次 ccconfig git pull 都中断一次用户实时会话」（实测：
#     auto-sync 拉取 → 重启 bridge → 会话 ECONNREFUSED）。拿"避免静默陈旧"换
#     "每次拉取都断线"不划算。
# 新代码何时生效：下次自然重启（崩溃恢复 / 切 preset / 重启机器），或手动
#     `bash maintain.sh fix` / `bash lib/bridge-service.sh restart`。
# 告警去重：同一指纹只报一次，避免每 10s 刷一行日志。
_warn_drift_once() {
    local fp="$1"
    [[ "$fp" == "$last_warned_fp" ]] && return 0
    last_warned_fp="$fp"
    _wd_log "注: openai_bridge.py 已更新（$fp），运行中的 bridge 仍为旧代码；下次重启生效，或跑 bash maintain.sh fix"
}

# 冷启动时 merged 缓存可能尚未生成（init-llm merge 还没跑）—— 等它出现而不是退出。
# 退出会让 systemd 每 RestartSec 重启一次，反复失败刷日志。
wait_for_cfg() {
    local i
    for i in $(seq 1 60); do
        [[ -n "$cfg" && -f "$cfg" ]] && return 0
        sleep 5
    done
    return 1
}

if ! wait_for_cfg; then
    _wd_log "merged 缓存 $cfg 300s 内未出现，supervisor 退出（每次开机由 systemd 再拉起）"
    exit 1
fi

last_fp="$(_code_fingerprint)"
last_warned_fp=""
fail=0

while true; do
    if curl -s --max-time 3 "http://127.0.0.1:${BRIDGE_PORT}/health" >/dev/null 2>&1; then
        # 代码漂移：只告警不重启（见 _warn_drift_once 的 why）
        cur_fp="$(_code_fingerprint)"
        [[ "$cur_fp" != "$last_fp" ]] && _warn_drift_once "$cur_fp"
        [[ $fail -gt 0 ]] && _wd_log "bridge 恢复 (第 ${fail} 次重试)"
        fail=0
        sleep "${BRIDGE_WD_INTERVAL:-10}"
        continue
    fi

    fail=$((fail + 1))
    _wd_log "bridge 无响应，按当前 preset 拉起 (第 ${fail} 次)"
    rc=0
    bash "${CCCONFIG_ROOT}/lib/bridge-restart.sh" "$cfg" "$initial_preset" >> "$BRIDGE_WD_LOG" 2>&1 || rc=$?

    # rc=3：切到直连 preset，本 supervisor 无事可做。主动 exit 0，配合 unit 的
    # Restart=on-failure 即可干净停下（用 Restart=always 会变成退出→重启风暴）。
    if [[ $rc -eq 3 ]]; then
        _wd_log "当前 preset 不需要 bridge，supervisor 退出"
        exit 0
    fi
    # rc=2 是永久性错误（preset 已从配置删除 / 配置不可用）：重启一万次也没用，
    # 旧版在这里以 60s 上限无限空转刷日志。改为长退避，仍保留恢复能力。
    if [[ $rc -eq 2 ]]; then
        _wd_log "preset 配置不可用（rc=2），300s 后再试；修: bash maintain.sh llm"
        sleep 300
        continue
    fi
    sleep_sec=$(( 5 * (1 << (fail - 1)) ))
    [[ $sleep_sec -gt 60 ]] && sleep_sec=60
    sleep "$sleep_sec"
done
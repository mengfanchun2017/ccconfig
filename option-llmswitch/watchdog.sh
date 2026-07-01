#!/bin/bash
# option-llmswitch watchdog — 定期 health check，死了自动重启
#
# 用法：
#   bash watchdog.sh          # 前台循环（默认 30s 间隔）
#   bash watchdog.sh --daemon # 后台跑一次健康检查后退出
#   bash watchdog.sh --stop   # 停止后台 watchdog

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PID_FILE="$HOME/.cache/llmswitch.pid"
WATCHDOG_PID_FILE="$HOME/.cache/llmswitch-watchdog.pid"
WATCHDOG_LOG="$HOME/.cache/llmswitch-watchdog.log"
MONITOR_LOG="$REPO_DIR/.monitor-sync.log"
ROUTE_CACHE="$HOME/.cache/llmswitch-route-cache"
HEALTH_URL="http://127.0.0.1:8899/health"
INTERVAL=30

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; GRAY='\033[0;90m'; NC='\033[0m'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WATCHDOG_LOG"; }

notify_route_change() {
    local route="$1" peak="$2"
    local prev=""
    [ -f "$ROUTE_CACHE" ] && prev=$(cat "$ROUTE_CACHE")
    if [ "$route" != "$prev" ]; then
        echo "$route" > "$ROUTE_CACHE"
        echo "[$(date '+%H:%M:%S')] llmswitch route: $route ($([ "$peak" = "True" ] && echo peak || echo off-peak))" >> "$MONITOR_LOG"
    fi
}

check_and_restart() {
    local h=$(curl -s --max-time 3 "$HEALTH_URL" 2>/dev/null)
    if [ -n "$h" ] && echo "$h" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d.get('status')=='ok' else 1)" 2>/dev/null; then
        local route=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_route','?'))" 2>/dev/null)
        local peak=$(echo "$h" | python3 -c "import json,sys; print(json.load(sys.stdin).get('peak',False))" 2>/dev/null)
        notify_route_change "$route" "$peak"
        return 0
    fi

    log "代理不健康，尝试重启"
    echo -e "${YELLOW}[watchdog] 代理不健康，重启中...${NC}"

    if [ -f "$PID_FILE" ]; then
        local wd_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$wd_pid" ] && kill -0 "$wd_pid" 2>/dev/null; then
            kill "$wd_pid" 2>/dev/null || true
            sleep 1
            kill -9 "$wd_pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi

    if bash "$SCRIPT_DIR/init.sh" --start >> "$WATCHDOG_LOG" 2>&1; then
        log "重启成功"
        echo -e "${GREEN}[watchdog] 重启成功${NC}"
        echo "[$(date '+%H:%M:%S')] llmswitch restarted by watchdog" >> "$MONITOR_LOG"
        rm -f "$ROUTE_CACHE"
    else
        log "重启失败，查看 $WATCHDOG_LOG"
        echo -e "${RED}[watchdog] 重启失败${NC}"
    fi
}

case "${1:-}" in
    --daemon)
        echo $$ > "$WATCHDOG_PID_FILE"
        log "watchdog 启动 (PID: $$, interval: ${INTERVAL}s)"
        while true; do
            check_and_restart
            sleep "$INTERVAL"
        done
        ;;
    --stop)
        if [ -f "$WATCHDOG_PID_FILE" ]; then
            local wd_stop_pid=$(cat "$WATCHDOG_PID_FILE")
            if kill -0 "$wd_stop_pid" 2>/dev/null; then
                kill "$wd_stop_pid" 2>/dev/null
                echo -e "${GREEN}watchdog 已停止 (PID: $wd_stop_pid)${NC}"
            fi
            rm -f "$WATCHDOG_PID_FILE"
        else
            echo -e "${YELLOW}watchdog 未运行${NC}"
        fi
        ;;
    *)
        echo -e "${GRAY}watchdog 前台模式 (Ctrl+C 退出)${NC}"
        while true; do
            check_and_restart
            sleep "$INTERVAL"
        done
        ;;
esac

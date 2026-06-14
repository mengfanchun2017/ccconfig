#!/usr/bin/env bash
# Vessel 健康检查 + 自动恢复
# 用法: vessel-healthcheck.sh [--fix] [--json]
#   --fix  自动重启不健康的 Vessel
#   --json 输出 JSON 格式
set -euo pipefail

FIX_MODE=false
JSON_MODE=false
for arg in "$@"; do
    case "$arg" in
        --fix) FIX_MODE=true ;;
        --json) JSON_MODE=true ;;
    esac
done

MCP_PORT=3100
MAX_GPU_CPU=30
MAX_INSTANCES=1
AUTH_FILE="$HOME/.config/vessel/mcp-auth.json"

# --- checks ---
issues=()
warnings=()

# 1. Vessel 主进程数
vessel_count=$(pgrep -f "vessel --no-sandbox" 2>/dev/null | wc -l || echo 0)
if [ "$vessel_count" -eq 0 ]; then
    issues+=("no_vessel_process")
elif [ "$vessel_count" -gt "$MAX_INSTANCES" ]; then
    issues+=("too_many_instances($vessel_count)")
fi

# 2. GPU 进程 CPU（检查所有 GPU 进程，取最大值）
gpu_cpu=0
gpu_pids=$(pgrep -f "vessel.*gpu-process" 2>/dev/null || true)
if [ -n "$gpu_pids" ]; then
    gpu_count=$(echo "$gpu_pids" | wc -l)
    for pid in $gpu_pids; do
        cpu=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | awk '{print int($1)}' || echo 0)
        [ "$cpu" -gt "$gpu_cpu" ] && gpu_cpu=$cpu
    done
    if [ "$gpu_cpu" -gt "$MAX_GPU_CPU" ]; then
        issues+=("gpu_cpu_high(${gpu_cpu}%_across_${gpu_count}_gpu_procs)")
    fi
else
    warnings+=("no_gpu_process")
fi

# 3. MCP 端口连通性
if ss -tlnp 2>/dev/null | grep -q "127.0.0.1:$MCP_PORT"; then
    # 4. MCP 端点响应
    TOKEN=""
    if [ -f "$AUTH_FILE" ]; then
        TOKEN=$(python3 -c "import json; print(json.load(open('$AUTH_FILE')).get('token',''))" 2>/dev/null || echo "")
    fi
    if [ -n "$TOKEN" ]; then
        mcp_resp=$(curl -s -m 5 -X POST "http://127.0.0.1:$MCP_PORT/mcp" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json, text/event-stream" \
            -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"healthcheck","version":"1.0"}}}' 2>&1 || true)
        if echo "$mcp_resp" | grep -q '"serverInfo"'; then
            : # MCP OK
        else
            issues+=("mcp_not_responding")
        fi
    else
        issues+=("no_auth_token")
    fi
else
    issues+=("port_not_listening")
fi

# --- 判断 ---
if [ ${#issues[@]} -eq 0 ]; then
    STATUS="healthy"
else
    STATUS="unhealthy"
fi

# --- 修复 ---
action="none"
if [ "$FIX_MODE" = true ] && [ "$STATUS" = "unhealthy" ]; then
    systemctl --user restart vessel.service 2>/dev/null || true
    sleep 3
    action="restarted"
    # 重新检查
    if ss -tlnp 2>/dev/null | grep -q "127.0.0.1:$MCP_PORT"; then
        STATUS="recovered"
    fi
fi

# --- 输出 ---
if [ "$JSON_MODE" = true ]; then
    python3 -c "
import json
print(json.dumps({
    'status': '$STATUS',
    'issues': '${issues[*]:-none}',
    'warnings': '${warnings[*]:-none}',
    'action': '$action',
    'vessel_count': '$vessel_count',
    'gpu_cpu': '${gpu_cpu:-0}',
    'port': '$MCP_PORT'
}))
"
else
    echo "Vessel: $STATUS"
    [ ${#issues[@]} -gt 0 ] && echo "  Issues: ${issues[*]}"
    [ ${#warnings[@]} -gt 0 ] && echo "  Warnings: ${warnings[*]}"
    [ "$action" != "none" ] && echo "  Action: $action"
fi

[ "$STATUS" = "healthy" ] || [ "$STATUS" = "recovered" ]

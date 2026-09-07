#!/bin/bash
# lib/ensure-bridge.sh
# Anthropic↔OpenAI bridge 生命周期（port 8898）
# 被 init-llm.sh 切换时 + status.sh SessionStart hook 自愈共用
#
# 简化原则：仅做健康检测 + upstream 匹配 + 启停。WSL 网络问题由 Windows 侧用户处理。
#
# 依赖: 调用方已 source lib/colors.sh（info/warn）

CCCONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_PORT=8898
BRIDGE_WD_PID="$HOME/.cache/bridge-watchdog.pid"
BRIDGE_WD_LOG="$HOME/.cache/bridge-watchdog.log"

_bridge_wd_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$BRIDGE_WD_LOG"; }

# bridge watchdog：30s 检查，挂了调用 bridge-restart.sh 重探路径 + 重启
# 被 ensure_bridge 成功后在后台启动
# why: 不再 exec 替换（旧版 exec 后 watchdog 死、只救一次）；改成循环调 bridge-restart.sh
# bridge-restart.sh 会重探候选路径，环境变了（单位↔家）自动选对路径
# 参数: upstream model key host_header cfg preset
start_bridge_watchdog() {
    local upstream="$1" model="$2" key="$3" host_header="${4:-}"
    local cfg="${5:-}" preset="${6:-}"
    # 已有 watchdog 在跑 → 跳过
    if [[ -f "$BRIDGE_WD_PID" ]]; then
        local old_pid
        old_pid=$(cat "$BRIDGE_WD_PID" 2>/dev/null) || true
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$BRIDGE_WD_PID"
    fi

    local wrapper="/tmp/bridge-watchdog-$RANDOM-$$.sh"
    cat > "$wrapper" << WDEOF
#!/bin/bash
while true; do
    h=\$(curl -s --max-time 3 http://127.0.0.1:${BRIDGE_PORT}/health 2>/dev/null) || h=''
    if [[ -z "\$h" ]]; then
        if [[ -n "${cfg}" && -n "${preset}" ]]; then
            # 重探候选路径后重启（环境可能已变）
            bash "${CCCONFIG_ROOT}/lib/bridge-restart.sh" "${cfg}" "${preset}" "${model}" "${key}" "${BRIDGE_PORT}" >> "${BRIDGE_WD_LOG}" 2>&1 || true
        else
            # 无候选信息：硬编码 upstream 重启（兼容）
            old=\$( { lsof -ti :${BRIDGE_PORT} 2>/dev/null || true; } | head -1 || true)
            [[ -n "\$old" ]] && kill "\$old" 2>/dev/null || true
            sleep 1
            cd "${CCCONFIG_ROOT}" || exit 1
            env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \\
                OPENAI_BRIDGE_UPSTREAM="${upstream}" OPENAI_BRIDGE_KEY="${key}" OPENAI_BRIDGE_MODEL="${model}" OPENAI_BRIDGE_HOST="${host_header}" \\
                python3 option-llmswitch/openai_bridge.py --port ${BRIDGE_PORT} \$( [[ "${upstream}" == https:* ]] && echo '--skip-tls-verify' ) \$( command -v curl.exe &>/dev/null && [[ "${upstream}" =~ ://(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.) ]] && echo '--use-win-curl' || true ) >> "${BRIDGE_WD_LOG}" 2>&1 &
            disown 2>/dev/null || true
        fi
        sleep 5
    fi
    sleep 30
done
WDEOF
    chmod +x "$wrapper"
    nohup "$wrapper" > "$BRIDGE_WD_LOG" 2>&1 < /dev/null &
    local wd_pid=$!
    disown "$wd_pid" 2>/dev/null || true
    echo "$wd_pid" > "$BRIDGE_WD_PID"
    _bridge_wd_log "watchdog 启动 (PID: $wd_pid) cfg=${cfg} preset=${preset}"
}

stop_bridge_watchdog() {
    if [[ ! -f "$BRIDGE_WD_PID" ]]; then return 0; fi
    local wd_pid
    wd_pid=$(cat "$BRIDGE_WD_PID" 2>/dev/null) || true
    if [[ -n "$wd_pid" ]]; then
        kill "$wd_pid" 2>/dev/null || true
        _bridge_wd_log "watchdog 停止 (PID: $wd_pid)"
    fi
    rm -f "$BRIDGE_WD_PID"
}

_bridge_supported() {
    local upstream="$1"
    [[ -z "$upstream" ]] && return 1
    [[ "$upstream" == *"/anthropic"* ]] && return 1
    [[ "$upstream" == *"://127.0.0.1"* ]] && return 1
    return 0
}

# 读 llm.json 预设的 base_url|model|key|host_header（无 upstream_original 兼容）
# host_header 可选：tailscale/SSH 透传场景证书 SAN 不匹配 IP 时，把 SNI+Host 改成证书里的真实域名/IP
read_bridge_config() {
    python3 - "$1" "$2" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    llm = d.get('llms', {}).get(sys.argv[2], {})
    print(f"{llm.get('base_url','')}|{llm.get('model','')}|{llm.get('key','')}|{llm.get('host_header','')}")
except Exception:
    sys.exit(1)
PYEOF
}

# 读 upstream_candidates（多路径探测：单位直连 / 家里 tailscale）
# 输出每行 "base_url|host_header"，无候选则空
get_upstream_candidates() {
    python3 - "$1" "$2" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    for c in d.get('llms', {}).get(sys.argv[2], {}).get('upstream_candidates', []):
        print(f"{c.get('base_url','')}|{c.get('host_header','')}")
except Exception:
    pass
PYEOF
}

# 候选路径可达性探测：GET，任何 HTTP 响应=可达（000=不可达）
# linux curl 先试；不通则试 curl.exe（tailscale 可能在 Windows 侧，WSL 看不到）
# why: 探测传输须与 bridge 实际传输一致，否则误判路径可用性
_bridge_probe_reachable() {
    local base_url="$1" host_header="${2:-}"
    local code
    code=$(curl -sk --max-time 3 -o /dev/null -w "%{http_code}" "$base_url" 2>/dev/null) || code="000"
    [[ -n "$code" && "$code" != "000" ]] && return 0
    if command -v curl.exe &>/dev/null; then
        code=$(curl.exe -sk --max-time 3 -o /dev/null -w "%{http_code}" "$base_url" 2>/dev/null) || code="000"
        [[ -n "$code" && "$code" != "000" ]] && return 0
    fi
    return 1
}

# 选最佳 upstream：有 candidates 则逐个探测选第一条可达（都不通则回退首条）；
# 无候选则返回顶层 base_url|host_header（不探测，兼容旧预设）
# 用法: pick_best_upstream_live <cfg> <preset>
# 输出: "base_url|host_header"
pick_best_upstream_live() {
    local cfg="$1" name="$2"
    local cands
    cands=$(get_upstream_candidates "$cfg" "$name")
    if [[ -n "$cands" ]]; then
        local first_url="" first_host="" url host
        while IFS='|' read -r url host; do
            [[ -z "$url" ]] && continue
            [[ -z "$first_url" ]] && { first_url="$url"; first_host="$host"; }
            if _bridge_probe_reachable "$url" "$host"; then
                echo "${url}|${host}"
                return 0
            fi
        done <<< "$cands"
        echo "${first_url}|${first_host}"
        return 0
    fi
    python3 - "$cfg" "$name" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
llm = d.get('llms', {}).get(sys.argv[2], {})
print(f"{llm.get('base_url','')}|{llm.get('host_header','')}")
PYEOF
}

# 确保 bridge 跑且 upstream 正确
# 用法: ensure_bridge <upstream> <model> <key> [<host_header>]
# host_header 可选：tailscale/SSH 透传场景证书 SAN 不匹配 IP 时，把 SNI+Host 改成证书里的真实域名/IP
# 返回 0=就绪 1=失败
ensure_bridge() {
    local upstream="$1" model="$2" key="$3" host_header="${4:-}"
    local cfg="${5:-}" preset="${6:-}"
    _bridge_supported "$upstream" || return 1

    # 已健康且 upstream 匹配 → 确保 watchdog 在跑后返回
    local health
    health=$(curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
    local old_pid=""
    if [[ -n "$health" ]]; then
        local cur_upstream
        cur_upstream=$(echo "$health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('upstream',''))" 2>/dev/null || echo "")
        if [[ "$cur_upstream" == "$upstream" ]]; then
            start_bridge_watchdog "$upstream" "$model" "$key" "$host_header" "$cfg" "$preset"
            return 0
        fi
        info "  upstream 变化 ($cur_upstream → $upstream)，重启 bridge..."
        # Why: lsof 无结果时 exit 1 + pipefail + set -e 会让函数直接退出
        old_pid=$( { lsof -ti :${BRIDGE_PORT} 2>/dev/null || true; } | head -1 || true)
        old_pid="${old_pid:-}"
    fi

    # 杀老 bridge（按端口号精确 kill，避免误杀）
    if [[ -n "$old_pid" ]]; then
        kill "$old_pid" 2>/dev/null || true
        sleep 1
    fi

local extra_args=""
    [[ "$upstream" == https:* ]] && extra_args="--skip-tls-verify"

    # WSL 场景：Windows 侧 tailscale 有 subnet route，但 WSL 看不到
    # RFC1918 私有段统一触发 --use-win-curl（10/8, 172.16/12, 192.168/16）
    # Why: 这些段通常是企业内网，WSL 用户多半通过 Windows tailscale 才能访问
    local win_curl=""
    if command -v curl.exe &>/dev/null && [[ "$upstream" =~ ://(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]; then
        win_curl="--use-win-curl"
    fi

    # 写 wrapper 脚本（与 Bash 父子进程组解耦）
    # Why: 之前 ( cd; nohup ... &; disown ) 子 shell 退出时 python 进程被 SIGHUP 杀
    # wrapper 文件名加随机后缀避免冲突
    local wrapper="/tmp/ensure-bridge-$RANDOM-$$.sh"
    cat > "$wrapper" << WRAPEOF
#!/bin/bash
cd "$CCCONFIG_ROOT" || exit 1
exec env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
    OPENAI_BRIDGE_UPSTREAM="$upstream" \
    OPENAI_BRIDGE_KEY="$key" \
    OPENAI_BRIDGE_MODEL="$model" \
    OPENAI_BRIDGE_HOST="$host_header" \
    python3 option-llmswitch/openai_bridge.py --port "$BRIDGE_PORT" $extra_args $win_curl
WRAPEOF
    chmod +x "$wrapper"
    nohup "$wrapper" > "$HOME/.cache/openai_bridge.log" 2>&1 < /dev/null &
    local bridge_pid=$!
    disown $bridge_pid 2>/dev/null || true

    # 等启动（最多 5s）
    # Why: 必须等 wrapper 完成 exec python3 再删，否则 bash 子进程会因找不到文件直接退出
    local h=""
    for _ in 1 2 3 4 5; do
        sleep 1
        h=$(curl -s --max-time 2 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
        [[ -n "$h" ]] && break
    done
    rm -f "$wrapper"

    [[ -n "$h" ]] && start_bridge_watchdog "$upstream" "$model" "$key" "$host_header" "$cfg" "$preset"
}

# 仅自愈：env 指向 127.0.0.1:8898 但 bridge 死了时拉起
# 用法: selfheal_bridge <llm.json 路径>
# 返回 0=健康或拉起成功 1=拉起失败
selfheal_bridge() {
    local cfg="$1"
    [[ -z "$cfg" ]] && return 0

    # env 不指向 8898 → 不需要 bridge
    local sf="$HOME/.claude/settings.json"
    [[ -f "$sf" ]] || return 0
    if ! grep -q '127.0.0.1:8898' "$sf" 2>/dev/null; then
        return 0
    fi

    # bridge 已响应 → OK
    if curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" >/dev/null 2>&1; then
        return 0
    fi

    # 读 current preset 配置拉起
    local cur
    cur=$(python3 -c "import json; print(json.load(open('$cfg')).get('current',''))" 2>/dev/null) || return 1
    [[ -z "$cur" ]] && return 0

    local bc
    bc=$(read_bridge_config "$cfg" "$cur") || return 1
    IFS='|' read -r _ model key _ <<< "$bc"

    # 多路径候选：重探选最佳 upstream（环境可能已变）
    local picked upstream host_header
    picked=$(pick_best_upstream_live "$cfg" "$cur")
    IFS='|' read -r upstream host_header <<< "$picked"

    warn "  bridge ($BRIDGE_PORT) 未响应，自动拉起 ($cur)..."
    ensure_bridge "$upstream" "$model" "$key" "$host_header" "$cfg" "$cur"
}

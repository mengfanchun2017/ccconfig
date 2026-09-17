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

# bridge watchdog：只守护进程存活 —— bridge 没了就按「当前」preset 拉起
#
# why 不做 upstream 主动探测：探测失败 ≠ bridge 故障。网络断了重启 bridge 修不了，
#     反而杀掉正在服务的进程、打断进行中的请求（旧版就是这么把好 bridge 换掉的）。
# why 每轮读 llm-current 而非启动时绑参：watchdog wrapper 是启动时一次性生成的，
#     绑参后切 preset 会拿旧 upstream 覆盖用户刚选的 preset。
# 参数: cfg(llm.json 路径)
start_bridge_watchdog() {
    local cfg="${1:-}"
    local initial_preset="${2:-}"
    [[ -z "$cfg" ]] && return 0

    # 无条件清掉残留（旧版只认 PID 文件，被覆盖/失联的老 watchdog 会永久残留）
    stop_bridge_watchdog >/dev/null 2>&1 || true

    mkdir -p "$HOME/.cache"
    local wrapper="$HOME/.cache/bridge-watchdog-$RANDOM-$$.sh"
    cat > "$wrapper" << WDEOF
#!/bin/bash
fail=0
while true; do
    if curl -s --max-time 3 http://127.0.0.1:${BRIDGE_PORT}/health >/dev/null 2>&1; then
        [[ \$fail -gt 0 ]] && echo "[\$(date '+%Y-%m-%d %H:%M:%S')] bridge 恢复 (第 \${fail} 次重试)" >> "${BRIDGE_WD_LOG}"
        fail=0
        sleep ${BRIDGE_WD_INTERVAL:-10}
        continue
    fi
    fail=\$((fail + 1))
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] bridge 无响应，按当前 preset 拉起 (第 \${fail} 次)" >> "${BRIDGE_WD_LOG}"
    # 传本 wrapper 启动时的 preset 作 fallback：llm-current 缺失时仍能兜住
    bash "${CCCONFIG_ROOT}/lib/bridge-restart.sh" "${cfg}" "${initial_preset}" >> "${BRIDGE_WD_LOG}" 2>&1 || true
    sleep_sec=\$(( 5 * (1 << (fail - 1)) ))
    [[ \$sleep_sec -gt 60 ]] && sleep_sec=60
    sleep \$sleep_sec
done
WDEOF
    chmod +x "$wrapper"
    setsid nohup "$wrapper" > "$BRIDGE_WD_LOG" 2>&1 < /dev/null &
    local wd_pid=$!
    disown "$wd_pid" 2>/dev/null || true
    echo "$wd_pid" > "$BRIDGE_WD_PID"
    _bridge_wd_log "watchdog 启动 (PID: $wd_pid) cfg=${cfg} preset=${initial_preset:-<llm-current>}"
}

stop_bridge_watchdog() {
    if [[ -f "$BRIDGE_WD_PID" ]]; then
        local wd_pid
        wd_pid=$(cat "$BRIDGE_WD_PID" 2>/dev/null) || true
        if [[ -n "$wd_pid" ]]; then
            kill "$wd_pid" 2>/dev/null || true
            _bridge_wd_log "watchdog 停止 (PID: $wd_pid)"
        fi
        rm -f "$BRIDGE_WD_PID"
    fi
    # PID 文件失联/被覆盖时兜底（pattern 用 [[]] 避免 pgrep 匹配到自己这条命令）
    local p
    for p in $(pgrep -f "bridge-watchdo[g]-" 2>/dev/null || true); do
        [[ "$p" == "$$" ]] && continue
        kill "$p" 2>/dev/null || true
    done
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

# 确保 bridge 跑且 upstream 正确
# 用法: ensure_bridge <upstream> <model> <key> [<host_header>]
# host_header 可选：tailscale/SSH 透传场景证书 SAN 不匹配 IP 时，把 SNI+Host 改成证书里的真实域名/IP
# 返回 0=就绪 1=失败
ensure_bridge() {
    local upstream="$1" model="$2" key="$3" host_header="${4:-}"
    local cfg="${5:-}" preset="${6:-}"
    _bridge_supported "$upstream" || return 1

    # WSL2 MTU 1280 杀 tailscale 大包 — https://github.com/tailscale/tailscale/issues/4833
    # 家里场景：WSL eth0 默认 MTU 1280，WireGuard overhead 让 1500-byte packet 被 silent drop
    # why: 理论上 tailscale 链路所有 HTTPS 请求都可能撞，特别是大 body（SSE 流 + 长 context）
    # why uname 而非 /proc/sys/fs/ostype：后者在标准内核里不存在，旧写法是死代码从不触发
    if [[ "$(uname -r)" == *microsoft* ]] \
       && command -v ip >/dev/null 2>&1 \
       && ip link show eth0 2>/dev/null | grep -q 'mtu 1280'; then
        warn "  ⚠ WSL2 默认 MTU 1280，tailscale 大包可能被静默丢弃"
        warn "    修：/etc/wsl.conf 加 [boot] command=\"ip link set eth0 mtu 1500\" 后 wsl --shutdown"
    fi

    # 已健康且 upstream 匹配 → 确保 watchdog 在跑后返回
    local health
    health=$(curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
    local old_pid=""
    if [[ -n "$health" ]]; then
        local cur_upstream
        cur_upstream=$(echo "$health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('upstream',''))" 2>/dev/null || echo "")
        if [[ "$cur_upstream" == "$upstream" ]]; then
            start_bridge_watchdog "$cfg" "$preset"
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
    # RFC1918 (10/8, 172.16/12, 192.168/16) + tailscale CGNAT (100.64/10) 统一触发 --use-win-curl
    # Why: 这些段通常是企业内网 / tailscale 跳板，WSL 用户多半通过 Windows 侧才能访问
    local win_curl=""
    if command -v curl.exe &>/dev/null && [[ "$upstream" =~ ://(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.) ]]; then
        win_curl="--use-win-curl"
    fi

    # 写 wrapper 脚本（与 Bash 父子进程组解耦）
    # Why: 之前 ( cd; nohup ... &; disown ) 子 shell 退出时 python 进程被 SIGHUP 杀
    # wrapper 文件名加随机后缀避免冲突
    # why: 日志重定向目标目录不存在会让整个重定向失败、bridge 根本起不来
    mkdir -p "$HOME/.cache"

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

    [[ -n "$h" ]] && start_bridge_watchdog "$cfg" "$preset"
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
    IFS='|' read -r upstream model key host_header <<< "$bc"

    warn "  bridge ($BRIDGE_PORT) 未响应，自动拉起 ($cur)..."
    ensure_bridge "$upstream" "$model" "$key" "$host_header" "$cfg" "$cur"
}

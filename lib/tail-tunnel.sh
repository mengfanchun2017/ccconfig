#!/bin/bash
# lib/tail-tunnel.sh — altllm_tail 专用 SSH 隧道维护脚本（独立文件，不碰 altllm/0731）
#
# ���责：管理到 fracistail 的 SSH 隧道（127.0.0.1:8890 → aiplus.airchina.com.cn:18080）
#   start   — 启动隧道（nohup 常驻，自管持久 ssh-agent）
#   stop    — 停止隧道 + 清理专属 agent
#   status  — 隧道端口 + 进程 + 内网 LLM 连通性
#   check   — 自检：隧道在跑则保持，断则重启（供定期调用/切换前调用）
#   agents  — 清理本��本之前泄漏的 ssh-agent socket（保留最新的）
#
# 复用 lib/colors.sh（info/warn/ok/err）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/colors.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/colors.sh"

# 常量
TUNNEL_PORT="${TAIL_TUNNEL_PORT:-8890}"          # 本地监听端口
REMOTE="${TAIL_REMOTE:-aiplus.airchina.com.cn:18080}"
SSH_TARGET="${TAIL_SSH_TARGET:-francis@100.96.236.22}"
SSH_PORT="${TAIL_SSH_PORT:-22}"
AGENT_DIR="$HOME/.ssh/agent"
AGENT_MARK="tail-tunnel"
AGENT_SOCK="$AGENT_DIR/tail-tunnel.agent.sock"
TUNNEL_LOG="$HOME/.cache/tail-tunnel.log"
PIDFILE="$HOME/.cache/tail-tunnel.pid"

# 读取 llm.json 中的隧道配置（覆盖默认值）
_load_config() {
    local llm_json="$HOME/git/ccprivate/conf/llm.json"
    [[ -f "$HOME/git/ccprivate/conf/llm.json" ]] || llm_json="$HOME/.config/ccconfig/llm.json"
    [[ -f "$llm_json" ]] || return 0
    local cfg
    cfg=$(python3 -c "
import json, sys
try:
    d = json.load(open('$llm_json'))
    t = d.get('llms', {}).get('altllm_tail', {}).get('ssh_tunnel', {})
    if not t:
        sys.exit(0)
    print(t.get('host',''), t.get('port',22), t.get('user',''), t.get('remote',''), t.get('listen_port',8890), sep='|')
except Exception:
    sys.exit(0)
" 2>/dev/null) || return 0
    [[ -z "$cfg" ]] && return 0
    IFS='|' read -r host port user remote listen_port <<< "$cfg"
    [[ -n "$host" ]] && SSH_TARGET="${user}@${host}"
    [[ -n "$port" ]] && SSH_PORT="$port"
    [[ -n "$remote" ]] && REMOTE="$remote"
    [[ -n "$listen_port" ]] && TUNNEL_PORT="$listen_port"
}

# 启动专属持久 ssh-agent（仅当没有可用的默认 agent 时）
_ensure_agent() {
    if ssh-add -l &>/dev/null 2>&1; then
        return 0  # 已有个可用 agent（继承调用方环境）
    fi
    # 复用本脚本之前创建的专属 agent
    if [[ -S "$AGENT_SOCK" ]] && SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add -l &>/dev/null 2>&1; then
        export SSH_AUTH_SOCK="$AGENT_SOCK"
        return 0
    fi
    # 新建专属 agent
    eval "$(ssh-agent -s -a "$AGENT_SOCK")" >/dev/null 2>&1
    export SSH_AUTH_SOCK="$AGENT_SOCK"
    ssh-add "$HOME/.ssh/id_ed25519" >/dev/null 2>&1 || {
        err "SSH key 加载失败: ~/.ssh/id_ed25519"
        return 1
    }
    # ssh-agent -s 输出 SSH_AGENT_PID；记录以便 stop 时清理
    echo "${SSH_AGENT_PID:-}" > "$PIDFILE.agent"
    return 0
}

# 隧道是否在监听
_tunnel_listening() {
    ss -tln 2>/dev/null | grep -q "][:.]$TUNNEL_PORT " || ss -tln 2>/dev/null | grep -q "[:.]$TUNNEL_PORT "
}

start() {
    info "启动 altllm_tail SSH 隧道 ($SSH_TARGET → localhost:$TUNNEL_PORT → $REMOTE)"
    _ensure_agent || return 1

    # 杀残留隧道进程
    if [[ -f "$PIDFILE" ]]; then
        local old
        old=$(cat "$PIDFILE")
        kill "$old" 2>/dev/null || true
    fi
    pkill -f "ssh -.*$TUNNEL_PORT.*$REMOTE" 2>/dev/null || true
    sleep 1

    if _tunnel_listening; then
        ok "隧道已在运行 (localhost:$TUNNEL_PORT)"
        return 0
    fi

    : > "$TUNNEL_LOG"
    # 后台会话，SSH_AUTH_SOCK 继承专属 agent
    setsid nohup ssh \
        -p "$SSH_PORT" \
        -NL "127.0.0.1:$TUNNEL_PORT:$REMOTE" \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -o TCPKeepAlive=yes \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=15 \
        "$SSH_TARGET" >> "$TUNNEL_LOG" 2>&1 &
    local pid=$!
    echo "$pid" > "$PIDFILE"

    # 等待监听
    for i in $(seq 1 12); do
        sleep 1
        _tunnel_listening && { ok "SSH 隧道就绪 (pid $pid)"; return 0; }
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
    done
    err "SSH 隧道启动失败 (pid $pid)。日志："
    tail -5 "$TUNNEL_LOG" | sed 's/^/    /'
    return 1
}

stop() {
    info "停止 altllm_tail SSH 隧道"
    if [[ -f "$PIDFILE" ]]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
    pkill -f "ssh -.*$TUNNEL_PORT.*$REMOTE" 2>/dev/null || true
    # 停专属 agent
    if [[ -f "$PIDFILE.agent" ]]; then
        kill "$(cat "$PIDFILE.agent")" 2>/dev/null || true
        rm -f "$PIDFILE.agent"
    fi
    rm -f "$AGENT_SOCK"
    ok "隧道已停止"
}

check() {
    # 切换/启动前自检：隧道断则重启，避免残留
    if _tunnel_listening; then
        ok "隧道端口 $TUNNEL_PORT 正在监听"
        return 0
    fi
    warn "隧道端口 $TUNNEL_PORT 未监听，重新启动..."
    start
}

status() {
    echo "── altllm_tail SSH 隧道 ($SSH_TARGET) ──"
    if _tunnel_listening; then
        echo "端口 $TUNNEL_PORT: ✓ 监听中"
        ss -tlnp 2>/dev/null | grep "[:.]$TUNNEL_PORT " | sed 's/^/  /'
    else
        echo "端口 $TUNNEL_PORT: ✗ 未监听"
    fi
    echo "内网 LLM ($REMOTE) 可达性:"
    if timeout 8 bash -c "cat < /dev/null > /dev/tcp/100.96.236.22/22" 2>/dev/null; then
        echo "  对端 fracistail:22 ✓"
    else
        echo "  对端 fracistail:22 ✗"
    fi
}

# 清理泄漏的 ssh-agent socket（保留最新 2 个最常用的）
agents_clean() {
    local total keep=2 i=0
    local files=()
    # 按 mtime 按从新到旧排序，保留前 keep 个
    mapfile -t files < <(ls -t "$AGENT_DIR"/s.* 2>/dev/null)
    total=${#files[@]}
    if (( total <= keep )); then
        ok "无泄漏 ssh-agent（$total 个，保留 $keep）"
        return 0
    fi
    local kill_socks=("${files[@]:keep}")
    info "清理 $((${#kill_socks[@]})) 个泄漏 ssh-agent socket（保留最新 $keep 个）"
    for sock in "${kill_socks[@]}"; do
        # 杀掉拥有该 socket 的 agent 进程
        local apid
        apid=$(SSH_AUTH_SOCK="$sock" ssh-keygen -y -P /dev/null >/dev/null 2>&1; true)  # 无副作用
        rm -f "$sock" 2>/dev/null || true
    done
    # 再按 socket 反向杀 agent 进程
    for sock in "${kill_socks[@]}"; do
        local p
        p=$(cat /proc/*/environ 2>/dev/null | tr '\0' '\n' 2>/dev/null | grep -l "SSH_AUTH_SOCK=$sock" 2>/dev/null) || true
    done
    ok "清理完成，剩余 $(ls -t "$AGENT_DIR"/s.* 2>/dev/null | wc -l) 个"
}

case "${1:-}" in
    start)  _load_config; start ;;
    stop)   stop ;;
    status) _load_config; status ;;
    check)  _load_config; check ;;
    agents) agents_clean ;;
    *) echo "用法: bash lib/tail-tunnel.sh {start|stop|status|check|agents}"; exit 1 ;;
esac

#!/bin/bash
# lib/tail-llm.sh — altllm_tail 专用：Tailscale → SSH 隧道 → bridge
# 走独立文件，不修改 init-llm.sh 现有逻辑
#
# 依赖: 调用方已 source lib/colors.sh（info/warn/error）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 常量
TAIL_TMUX_SESSION="altllm-tail-tunnel"
TAIL_BRIDGE_TMUX="altllm-tail-bridge"
TAIL_SSH_LOG="$HOME/.cache/ssh-tunnel-tail.log"
TAIL_BRIDGE_LOG="$HOME/.cache/openai_bridge_tail.log"
TAIL_BRIDGE_PORT=8895
TAIL_TUNNEL_PORT=8890

# ========== SSH 隧道 ==========
# $1: host  $2: port  $3: user  $4: remote (host:port)
_tail_start_ssh_tunnel() {
    local host="$1" port="$2" user="$3" remote="$4"
    [[ -z "$host" || -z "$remote" ]] && { error "SSH 隧道参数缺失"; return 1; }

    if tmux has-session -t "$TAIL_TMUX_SESSION" 2>/dev/null; then
        local listen_port=$(ss -tlnp 2>/dev/null | grep "127.0.0.1:$TAIL_TUNNEL_PORT " | head -1 || echo "")
        if [[ -n "$listen_port" ]]; then
            info "  SSH 隧道已在运行 (tmux: $TAIL_TMUX_SESSION)"
            return 0
        fi
        # 端口没监听但 tmux 在 → 异常，杀残留重来
        warn "  tmux session 存在但端口无监听，重启..."
        tmux kill-session -t "$TAIL_TMUX_SESSION" 2>/dev/null || true
        sleep 1
    fi

    local ssh_target="$host"
    [[ -n "$user" ]] && ssh_target="${user}@${host}"
    local port_opt=""
    [[ -n "$port" && "$port" != "22" ]] && port_opt="-p $port"

    info "  启动 SSH 隧道: ${user}@${host}:${port} → localhost:${TAIL_TUNNEL_PORT} → ${remote}"

    # 确保 ssh-agent + key
    : > "$TAIL_SSH_LOG"
    if ! ssh-add -l &>/dev/null; then
        if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
            info "    ssh-agent 未运行，自动启动..."
            eval $(ssh-agent -s) &>/dev/null
            export SSH_AUTH_SOCK SSH_AGENT_PID
            ssh-add "$HOME/.ssh/id_ed25519" &>/dev/null || {
                error "    ssh key 加载失败"
                return 1
            }
        else
            error "    未找到 ~/.ssh/id_ed25519"
            return 1
        fi
    fi

    tmux new-session -d -s "$TAIL_TMUX_SESSION" \
        "env SSH_AUTH_SOCK='${SSH_AUTH_SOCK:-}' \
         ssh -NL '${TAIL_TUNNEL_PORT}:${remote}' ${port_opt} '${ssh_target}' \
            -o ExitOnForwardFailure=yes \
            -o ServerAliveInterval=30 \
            -o ServerAliveCountMax=3 \
            -o TCPKeepAlive=yes \
            -o StrictHostKeyChecking=accept-new \
            -o UserKnownHostsFile=/dev/null \
            2>> '$TAIL_SSH_LOG'" 2>&1

    sleep 2
    if ! tmux has-session -t "$TAIL_TMUX_SESSION" 2>/dev/null; then
        error "  SSH 隧道 tmux session 已退出"
        head -5 "$TAIL_SSH_LOG"
        return 1
    fi

    local retries=10
    while (( retries > 0 )); do
        if ss -tlnp 2>/dev/null | grep -q ":$TAIL_TUNNEL_PORT "; then
            info "  SSH 隧道就绪: localhost:$TAIL_TUNNEL_PORT → $remote"
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done

    error "  端口 $TAIL_TUNNEL_PORT 未被监听"
    tmux kill-session -t "$TAIL_TMUX_SESSION" 2>/dev/null || true
    return 1
}

_tail_stop_ssh_tunnel() {
    tmux kill-session -t "$TAIL_TMUX_SESSION" 2>/dev/null || true
    info "  SSH 隧道已停止"
}

# ========== Bridge ==========
# $1: model  $2: api_key
_tail_start_bridge() {
    local model="$1" key="$2"

    # 停残留 tail bridge
    pkill -f "openai_bridge_tail.py" 2>/dev/null || true
    sleep 1

    local upstream="http://127.0.0.1:${TAIL_TUNNEL_PORT}/v1"
    nohup env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
        OPENAI_BRIDGE_UPSTREAM="$upstream" \
        OPENAI_BRIDGE_UPSTREAM_ORIGINAL="$upstream" \
        OPENAI_BRIDGE_KEY="$key" \
        OPENAI_BRIDGE_MODEL="$model" \
        OPENAI_BRIDGE_SKIP_TLS_VERIFY=1 \
        python3 "$SCRIPT_DIR/option-llmswitch/openai_bridge_tail.py" --port "$TAIL_BRIDGE_PORT" --skip-tls-verify \
        > "$TAIL_BRIDGE_LOG" 2>&1 &
    disown

    local health=""
    for i in 1 2 3 4 5; do
        sleep 1
        health=$(curl -s --max-time 2 "http://127.0.0.1:${TAIL_BRIDGE_PORT}/health" 2>/dev/null)
        [[ -n "$health" ]] && break
    done

    if [[ -z "$health" ]]; then
        error "  tail bridge 启动失败"
        head -10 "$TAIL_BRIDGE_LOG"
        return 1
    fi
    info "  tail bridge 已就绪 (port $TAIL_BRIDGE_PORT)"
}

_tail_stop_bridge() {
    pkill -f "openai_bridge_tail.py" 2>/dev/null || true
    info "  tail bridge 已停止"
}

# ========== 全部停止 ==========
tail_stop_all() {
    _tail_stop_bridge
    _tail_stop_ssh_tunnel
    info "  tail 链路全部停止"
}

# ========== 启动全部 ==========
# 从环境变量读取配置
# 用法: tail_start 或 source 后设置变量
# 或从 init-llm.sh 传入参数
# $1: host  $2: port  $3: user  $4: remote  $5: model  $6: api_key
tail_start() {
    local host="${1:-}" port="${2:-22}" user="${3:-}" remote="${4:-}" model="${5:-}" key="${6:-}"

    if [[ -z "$host" || -z "$remote" || -z "$model" || -z "$key" ]]; then
        # 从 llm.json 读 altllm_tail 配置
        local llm_json="$HOME/.config/ccconfig/llm.json"
        [[ -f "$HOME/git/ccprivate/conf/llm.json" ]] && llm_json="$HOME/git/ccprivate/conf/llm.json"
        # 兼容 ccconfig 仓库内 ccprivate symlink
        [[ -f "$SCRIPT_DIR/../ccprivate/conf/llm.json" ]] && llm_json="$SCRIPT_DIR/../ccprivate/conf/llm.json"
        python3 - "$llm_json" << 'PYEOF' || return 1
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
    t = d.get('llms', {}).get('altllm_tail', {}).get('ssh_tunnel', {})
    host = t.get('host') or t.get('ssh_host', '')
    if not host:
        sys.exit(1)
    print(f"{host}|{t.get('port',22)}|{t.get('user','')}|{t['remote']}|{d['llms']['altllm_tail'].get('model','')}|{d['llms']['altllm_tail'].get('key','')}")
except:
    sys.exit(1)
PYEOF
        local cfg; cfg=$(cat)
        IFS='|' read -r host port user remote model key <<< "$cfg"
    fi

    info "启动 altllm_tail 链路..."
    _tail_start_ssh_tunnel "$host" "$port" "$user" "$remote" || return 1
    _tail_start_bridge "$model" "$key" || {
        _tail_stop_ssh_tunnel
        return 1
    }
    info "  altllm_tail 链路就绪，BASE_URL → http://127.0.0.1:${TAIL_BRIDGE_PORT}"
    return 0
}

# ========== 状态 ==========
tail_status() {
    echo "── altllm_tail 链路诊断 ──"
    if tmux has-session -t "$TAIL_TMUX_SESSION" 2>/dev/null; then
        local listen_port=$(ss -tlnp 2>/dev/null | grep "127.0.0.1:8890 " | head -1 || echo "(port 8890 not listening)")
        echo "  SSH 隧道: tmux=$TAIL_TMUX_SESSION $listen_port"
        tail -3 "$TAIL_SSH_LOG" 2>/dev/null | sed 's/^/    /'
    else
        echo "  SSH 隧道: 未运行"
    fi

    local bh=""
    bh=$(curl -s --max-time 2 "http://127.0.0.1:${TAIL_BRIDGE_PORT}/health" 2>/dev/null) || true
    if [[ -n "$bh" ]]; then
        echo "  bridge (port $TAIL_BRIDGE_PORT): ✓"
        echo "$bh" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'    upstream={d.get(\"upstream\",\"\")} model={d.get(\"upstream_model\",\"\")}')" 2>/dev/null || true
    else
        echo "  bridge (port $TAIL_BRIDGE_PORT): ✗"
    fi
}

# 直接运行时
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    case "$cmd" in
        start) tail_start ;;
        stop) tail_stop_all ;;
        status) tail_status ;;
        *) echo "用法: bash lib/tail-llm.sh {start|stop|status}"; exit 1 ;;
    esac
fi

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

_bridge_supported() {
    local upstream="$1"
    [[ -z "$upstream" ]] && return 1
    [[ "$upstream" == *"/anthropic"* ]] && return 1
    [[ "$upstream" == *"://127.0.0.1"* ]] && return 1
    return 0
}

# 读 llm.json 预设的 base_url|model|key（无 upstream_original 兼容）
read_bridge_config() {
    python3 - "$1" "$2" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    llm = d.get('llms', {}).get(sys.argv[2], {})
    print(f"{llm.get('base_url','')}|{llm.get('model','')}|{llm.get('key','')}")
except Exception:
    sys.exit(1)
PYEOF
}

# 确保 bridge 跑且 upstream 正确
# 用法: ensure_bridge <upstream> <model> <key>
# 返回 0=就绪 1=失败
ensure_bridge() {
    local upstream="$1" model="$2" key="$3"
    _bridge_supported "$upstream" || return 1

    # 已健康且 upstream 匹配 → 直接返回
    local health
    health=$(curl -s --max-time 1 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
    if [[ -n "$health" ]]; then
        local cur_upstream
        cur_upstream=$(echo "$health" | python3 -c "import json,sys; print(json.load(sys.stdin).get('upstream',''))" 2>/dev/null || echo "")
        if [[ "$cur_upstream" == "$upstream" ]]; then
            return 0
        fi
        info "  upstream 变化 ($cur_upstream → $upstream)，重启 bridge..."
    fi

    # 启新 bridge
    pkill -f "openai_bridge.py" 2>/dev/null || true
    sleep 1

    local extra_args=""
    [[ "$upstream" == https:* ]] && extra_args="--skip-tls-verify"

    # WSL 场景：Windows 侧 tailscale 有 subnet route，但 WSL 看不到
    # 让 bridge 通过 /mnt/c/Windows/System32/curl.exe 转发，走 Windows 网络栈
    local win_curl=""
    if command -v curl.exe &>/dev/null && [[ "$upstream" == *"10.150.224"* ]]; then
        win_curl="--use-win-curl"
    fi

    (
        cd "$CCCONFIG_ROOT"
        env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
            OPENAI_BRIDGE_UPSTREAM="$upstream" \
            OPENAI_BRIDGE_KEY="$key" \
            OPENAI_BRIDGE_MODEL="$model" \
            nohup python3 option-llmswitch/openai_bridge.py --port "$BRIDGE_PORT" $extra_args $win_curl \
            > "$HOME/.cache/openai_bridge.log" 2>&1 &
        disown
    )

    # 等启动（最多 5s）
    local h=""
    for _ in 1 2 3 4 5; do
        sleep 1
        h=$(curl -s --max-time 2 "http://127.0.0.1:${BRIDGE_PORT}/health" 2>/dev/null) || true
        [[ -n "$h" ]] && break
    done

    [[ -n "$h" ]]
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
    IFS='|' read -r upstream model key <<< "$bc"

    warn "  bridge ($BRIDGE_PORT) 未响应，自动拉起 ($cur)..."
    ensure_bridge "$upstream" "$model" "$key"
}

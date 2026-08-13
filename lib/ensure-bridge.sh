#!/bin/bash
# lib/ensure-bridge.sh
# Anthropic↔OpenAI bridge 生命周期（port 8898）
# 被 init-llm.sh 切换时 + status.sh SessionStart hook 自愈共用
#
# 依赖: 调用方已 source lib/colors.sh（info/warn）

CCCONFIG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 只服务 OpenAI-only 端点（非 /anthropic、非本地）
_bridge_supported() {
    local upstream="$1"
    [[ -z "$upstream" ]] && return 1
    [[ "$upstream" == *"/anthropic"* ]] && return 1
    [[ "$upstream" == *"://127.0.0.1"* ]] && return 1
    return 0
}

# 从 llm.json 读预设的 base_url|model|key
# 用法: read_bridge_config <llm.json路径> <preset名>
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

# 确保 8898 bridge 运行，upstream 不匹配则重启
# 用法: ensure_bridge <upstream> <model> <key>
# 返回 0=就绪 1=失败
ensure_bridge() {
    local upstream="$1" model="$2" key="$3"
    local port=8898
    _bridge_supported "$upstream" || return 1

    local health
    health=$(curl -s --max-time 2 "http://127.0.0.1:${port}/health" 2>/dev/null)
    if [[ -n "$health" ]]; then
        local cur_upstream
        cur_upstream=$(echo "$health" | python3 -c "
import json, sys
try: print(json.load(sys.stdin).get('upstream', ''))
except: pass
" 2>/dev/null)
        if [[ "$cur_upstream" == "$upstream" ]]; then
            return 0
        fi
        pkill -f "openai_bridge.py" 2>/dev/null || true
        sleep 1
    fi

    # 启新 bridge（unset 代理 env 直连上游）
    cd "$CCCONFIG_ROOT"
    nohup env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
        OPENAI_BRIDGE_UPSTREAM="$upstream" \
        OPENAI_BRIDGE_KEY="$key" \
        OPENAI_BRIDGE_MODEL="$model" \
        python3 option-llmswitch/openai_bridge.py --port "$port" \
        > "$HOME/.cache/openai_bridge.log" 2>&1 &
    disown

    # 等待启动
    for i in 1 2 3 4 5; do
        sleep 1
        health=$(curl -s --max-time 2 "http://127.0.0.1:${port}/health" 2>/dev/null)
        [[ -n "$health" ]] && break
    done

    [[ -n "$health" ]]
}

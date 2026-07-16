#!/bin/bash
# 一键启动 openai_bridge（通用 OpenAI↔Anthropic 协议转换桥接）
# 适用：OpenAI-only 端点（不含 /anthropic 的路由，如自部署网关、部分第三方 API）
# 只启动 bridge，不切 LLM。切 LLM 用 init-llm.sh <provider>

set -e
SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"

# 解析参数
PROVIDER="${1:-}"

# 从 llm.json 读取 provider 信息
read_provider_from_json() {
    local provider="$1"
    python3 - "$CCCONFIG_ROOT/conftemp/llm.json" "$provider" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
prov = d.get('llms', {}).get(sys.argv[2], {})
for k in ('base_url', 'key', 'model'):
    print(prov.get(k, ''))
PYEOF
}

# 确定 target provider
if [[ -z "$PROVIDER" ]]; then
    # 没有参数 → 从 llm.json current 读
    PROVIDER=$(python3 -c "
import json
try:
    with open('$CCCONFIG_ROOT/conftemp/llm.json') as f:
        d = json.load(f)
    print(d.get('current', ''))
except: pass
" 2>/dev/null || echo "")
    if [[ -z "$PROVIDER" ]]; then
        echo "❌ 未指定 provider。用法:"
        echo "   bash lib/start-openai-bridge.sh <provider>"
        echo "   bash lib/start-openai-bridge.sh  # 自动读 llm.json current"
        exit 1
    fi
fi

# 读取 provider 配置
IFS=$'\n' read -r UPSTREAM KEY MODEL <<< "$(read_provider_from_json "$PROVIDER")"

if [[ -z "$UPSTREAM" ]]; then
    echo "❌ 未找到 provider '$PROVIDER' 的 base_url（检查 conftemp/llm.json）"
    exit 1
fi
if [[ -z "$KEY" ]]; then
    echo "❌ provider '$PROVIDER' key 为空"
    echo "   编辑 llm.json 或在 ccprivate 中配置"
    exit 1
fi

PORT="${OPENAI_BRIDGE_PORT:-8898}"

echo "🔌 启动 bridge → $PROVIDER ($UPSTREAM | $MODEL)"

# 1. 杀掉旧 bridge 实例
pkill -f "openai_bridge.py.*--port ${PORT}" 2>/dev/null || true
sleep 1

# 2. 启动新 bridge（unset 代理，直连）
cd "$CCCONFIG_ROOT"
nohup env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
    OPENAI_BRIDGE_UPSTREAM="$UPSTREAM" \
    OPENAI_BRIDGE_KEY="$KEY" \
    OPENAI_BRIDGE_MODEL="$MODEL" \
    python3 option-llmswitch/openai_bridge.py --port "$PORT" \
    > "$HOME/.cache/openai_bridge.log" 2>&1 &
disown

# 3. 等待启动
for i in 1 2 3 4 5; do
    sleep 1
    if curl -s --max-time 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        break
    fi
done

HEALTH=$(curl -s --max-time 2 "http://127.0.0.1:${PORT}/health" 2>/dev/null)
if [[ -n "$HEALTH" ]]; then
    echo "✅ bridge alive: $HEALTH"
else
    echo "❌ bridge 启动失败，查看日志: tail $HOME/.cache/openai_bridge.log"
    exit 1
fi

echo ""
echo "📋 用法: lib/init-llm.sh $PROVIDER   # 切 LLM 时自动启此 bridge"

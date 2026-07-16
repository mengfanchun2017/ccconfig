#!/bin/bash
# 一键启动 openai_bridge + 切到 myllm (airchina)
# 解决：Claude Code 直接连 airchina 会死（airchina 是 OpenAI-only 端点）

set -e
SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"

# 加载 ccprivate token if exists
ENV_FILE="${CCCONFIG_ROOT}/conftemp/.airchina-bridge.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

if [[ -z "${AIRCHINA_KEY:-}" ]]; then
    echo "❌ AIRCHINA_KEY 未设置"
    echo "   1) 编辑 ${ENV_FILE}，填入 AIRCHINA_KEY=sk-..."
    echo "   2) 或 export AIRCHINA_KEY=sk-... 后重试"
    exit 1
fi

UPSTREAM="${AIRCHINA_UPSTREAM:-https://aiplus.airchina.com.cn:18080}"
MODEL="${AIRCHINA_MODEL:-deepseek-v4-flash}"
PORT="${AIRCHINA_BRIDGE_PORT:-8898}"

# 1. 杀掉旧 bridge 实例
pkill -f "openai_bridge.py.*--port ${PORT}" 2>/dev/null || true
sleep 1

# 2. 启动新 bridge（unset 代理，直连）
cd "$CCCONFIG_ROOT"
nohup env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
    OPENAI_BRIDGE_UPSTREAM="$UPSTREAM" \
    OPENAI_BRIDGE_KEY="$AIRCHINA_KEY" \
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

# 4. 切到 myllm preset（指向 bridge）
echo ""
echo "切换 LLM 到 myllm (走 bridge)..."
bash "$SCRIPT_DIR/init-llm.sh" myllm 2>&1 | tail -8 || \
bash "$SCRIPT_DIR/init-llm.sh" 4 myllm "$AIRCHINA_KEY" y myllm 2>&1 | tail -8

echo ""
echo "📋 用法："
echo "  claude         # 默认走代理（minimax 等），没事"
echo "  claude-direct  # 自动检测 ANTHROPIC_BASE_URL 是否要绕代理（已在 .bashrc 自动加）"
echo ""
echo "📋 ANTHROPIC_BASE_URL 现在是: http://127.0.0.1:${PORT}"
echo "   Claude Code 调用会经 bridge 转 airchina OpenAI 协议"

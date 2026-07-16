#!/bin/bash
# 一键启动 openai_bridge（airchina OpenAI↔Anthropic 桥接）
# 解决：Claude Code 直接连 airchina 会死（airchina 是 OpenAI-only 端点）
# 只启动 bridge，不切 LLM。切 LLM 用 init-llm.sh airchina

set -e
SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"

# 优先 env，其次 .airchina-bridge.env，最后从 llm.json 自动读
ENV_FILE="${CCCONFIG_ROOT}/conftemp/.airchina-bridge.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

if [[ -z "${AIRCHINA_KEY:-}" ]]; then
	AIRCHINA_KEY=$(python3 -c "
import json
try:
    with open('${CCCONFIG_ROOT}/conftemp/llm.json') as f:
        d = json.load(f)
    print(d['llms']['airchina']['key'])
except: pass
" 2>/dev/null)
fi

if [[ -z "${AIRCHINA_KEY:-}" ]]; then
	echo "❌ AIRCHINA_KEY 未设置"
	echo "   1) 编辑 ${ENV_FILE}，填入 AIRCHINA_KEY=sk-..."
	echo "   2) 或 export AIRCHINA_KEY=sk-... 后重试"
	exit 1
fi

UPSTREAM="${AIRCHINA_UPSTREAM:-https://aiplus.airchina.com.cn:18080/v1}"
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

echo ""
echo "📋 用法: init-llm.sh airchina   # 切 LLM 时自动启此 bridge"

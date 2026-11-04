#!/bin/bash
# test-bridge-vision-route.sh — 视觉路由端到端回归
#
# 为什么需要：主模型是纯文本时（内网 deepseek、glm-*-flash 等），上游收到
# image_url 会**静默丢弃且不报错**，模型于是凭空编造图片内容。实测把同一张 PNG
# 发给纯文本主模型，返回"白底圆角矩形里写着 0"，而真图是深紫底粉色像素人；
# 流式则直接回"我看不到你提到的图片"，input_tokens 只有 16（整图该上千）。
#
# 所以 bridge 必须能在「请求含图」时改发视觉模型，且视觉侧可以是**另一个供应商**
# （主模型走内网 + 视觉走公网智谱是最常见的组合）。
#
# 这个测试用两个 mock upstream 把路由钉住：主上游故意返回错误标记，视觉上游返回
# 可辨识的答案。带图请求拿到视觉答案 = 路由生效；纯文本拿到主上游答案 = 未误触发。
#
# 用法: bash ccconfig/tests/test-bridge-vision-route.sh [--verbose]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BRIDGE_PY="${BRIDGE_PY:-$CCCONFIG_DIR/option-llmswitch/openai_bridge.py}"
MOCK_MAIN_PORT=18901
MOCK_VISION_PORT=18902
BRIDGE_PORT=18903
VERBOSE=false
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=true

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✅${NC} $1"; }
_fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}❌${NC} $1${2:+ — $2}"; }

WORKDIR=$(mktemp -d)
cleanup() {
    for p in "${BRIDGE_PID:-}" "${MAIN_PID:-}" "${VISION_PID:-}"; do
        [[ -n "$p" ]] && kill "$p" 2>/dev/null
    done
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# 一个 mock 同时服务两个端口，用 URL 路径区分身份：/main 或 /vision
cat > "$WORKDIR/mock.py" <<'PYEOF'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

TAG = sys.argv[1]   # MAIN 或 VISION

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get('content-length') or 0)
        body = json.loads(self.rfile.read(n) or b'{}')
        # 回显收到的模型名，测试据此判断路由去了哪一侧
        seen_model = body.get('model', '')
        # 探一下请求里到底有没有图片段（bridge 应当转换出来）
        has_img = False
        for m in body.get('messages') or []:
            c = m.get('content')
            if isinstance(c, list) and any(
                    isinstance(b, dict) and b.get('type') == 'image_url' for b in c):
                has_img = True
        text = f"FROM={TAG} MODEL={seen_model} HAS_IMAGE={has_img}"
        out = {"id": "x", "choices": [{"index": 0, "message": {"role": "assistant", "content": text},
                                       "finish_reason": "stop"}],
               "usage": {"prompt_tokens": 10, "completion_tokens": 5}}
        blob = json.dumps(out).encode()
        self.send_response(200)
        self.send_header('content-type', 'application/json')
        self.send_header('content-length', str(len(blob)))
        self.end_headers()
        self.wfile.write(blob)

class S(ThreadingMixIn, HTTPServer): daemon_threads = True
S(('127.0.0.1', int(sys.argv[2])), H).serve_forever()
PYEOF

python3 "$WORKDIR/mock.py" MAIN "$MOCK_MAIN_PORT" &
MAIN_PID=$!
python3 "$WORKDIR/mock.py" VISION "$MOCK_VISION_PORT" &
VISION_PID=$!

# bridge：主上游 MAIN、视觉上游 VISION。主上游地址正确但 mock 会自报 TAG=MAIN，
# 因此只看 TAG 就能判定走的是哪一边，不依赖主上游是否可用。
OPENAI_BRIDGE_UPSTREAM="http://127.0.0.1:$MOCK_MAIN_PORT/v1" \
OPENAI_BRIDGE_KEY="k" \
OPENAI_BRIDGE_MODEL="text-only-model" \
OPENAI_BRIDGE_VISION_MODEL="vision-model-x" \
OPENAI_BRIDGE_VISION_UPSTREAM="http://127.0.0.1:$MOCK_VISION_PORT/v1" \
OPENAI_BRIDGE_VISION_KEY="vk" \
python3 "$BRIDGE_PY" --port "$BRIDGE_PORT" > "$WORKDIR/bridge.log" 2>&1 &
BRIDGE_PID=$!

for _ in $(seq 1 30); do
    curl -s -m 1 "http://127.0.0.1:$BRIDGE_PORT/health" > /dev/null 2>&1 && break
    sleep 0.5
done
if ! curl -s -m 2 "http://127.0.0.1:$BRIDGE_PORT/health" > "$WORKDIR/health.json" 2>/dev/null; then
    echo "bridge 起不来，日志："; tail -20 "$WORKDIR/bridge.log"; exit 1
fi

ask() {
    local payload="$1"
    curl -s -m 20 -X POST "http://127.0.0.1:$BRIDGE_PORT/v1/messages" \
        -H 'content-type: application/json' -H 'anthropic-version: 2023-06-01' \
        -d "$payload" 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(''.join(b.get('text','') for b in d.get('content',[]) if b.get('type')=='text'))
except Exception:
    print('PARSE_FAIL')
"
}

echo "== /health 暴露视觉路由状态 =="
if grep -q '"vision_model": *"vision-model-x"' "$WORKDIR/health.json"; then
    _pass "health 报 vision_model"
else
    _fail "health 缺 vision_model" "$(head -c 300 "$WORKDIR/health.json")"
fi
if grep -q '"vision_upstream_set": *true' "$WORKDIR/health.json"; then
    _pass "health 报 vision_upstream_set"
else
    _fail "health 缺 vision_upstream_set"
fi

echo "== 纯文本请求走主上游、不改模型名 =="
out=$(ask '{"model":"whatever","max_tokens":64,"messages":[{"role":"user","content":"hi"}]}')
if [[ "$out" == *"FROM=MAIN"* && "$out" == *"MODEL=text-only-model"* ]]; then
    _pass "纯文本 → 主上游 + 主模型名"
else
    _fail "纯文本路由错" "$out"
fi

echo "== 带图请求改发视觉上游 + 视觉模型名 =="
# 1x1 PNG
IMG_B64="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
out=$(ask "{\"model\":\"whatever\",\"max_tokens\":200,\"messages\":[{\"role\":\"user\",\"content\":[
  {\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/png\",\"data\":\"$IMG_B64\"}},
  {\"type\":\"text\",\"text\":\"看图\"}]}]}")
if [[ "$out" == *"FROM=VISION"* && "$out" == *"MODEL=vision-model-x"* ]]; then
    _pass "带图 → 视觉上游 + 视觉模型名"
else
    _fail "带图路由错（应跨供应商走 VISION）" "$out"
fi
if [[ "$out" == *"HAS_IMAGE=True"* ]]; then
    _pass "图片段被转换保留（image_url 到达上游）"
else
    _fail "图片段丢失" "$out"
fi

echo "== tool_result 内层图同样触发视觉路由 =="
out=$(ask "{\"model\":\"whatever\",\"max_tokens\":200,\"messages\":[{\"role\":\"user\",\"content\":[
  {\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":[
     {\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/png\",\"data\":\"$IMG_B64\"}}]},
  {\"type\":\"text\",\"text\":\"这张截图说明什么\"}]}]}")
if [[ "$out" == *"FROM=VISION"* ]]; then
    _pass "tool_result 内层图 → 视觉上游"
else
    _fail "tool_result 内层图未触发视觉路由" "$out"
fi

echo
if (( FAIL > 0 )); then echo "通过 $PASS 项，失败 $FAIL"; else echo "通过 $PASS 项，全部通过"; fi
[[ $FAIL -eq 0 ]]

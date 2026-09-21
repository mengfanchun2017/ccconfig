#!/bin/bash
# option-evalscope/lib.sh — 供 run-perf.sh / run-eval.sh / run-all.sh source 的共享逻辑
#   读 llm.json preset → 决定如何连接 evalscope → 生成报告目录名

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$CCCONFIG_ROOT/lib/path-helper.sh"
source "$CCCONFIG_ROOT/lib/colors.sh"

# 独立 venv 里的 evalscope
EVALSCOPE_BIN="$SCRIPT_DIR/.venv/bin/evalscope"

# 结果输出根目录（可 env 覆盖）
EVAL_OUTPUT_ROOT="${EVAL_OUTPUT_ROOT:-$HOME/.cache/evalscope}"

# 读 llm.json 配置路径（ccprivate 真实值）
resolve_llm_json() {
    resolve_conf llm.json 2>/dev/null
}

# 读取 llm.json 里某 preset 的 base_url|model|key|host_header|use_bridge
# 用法: read_preset <llm_json> <preset>
# 输出: 每行一个字段，顺序: base_url / model / key / host_header / use_bridge
read_preset() {
    local cfg="$1" preset="$2"
    python3 - "$cfg" "$preset" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    llm = d.get('llms', {}).get(sys.argv[2], {})
    keys = ['base_url', 'model', 'key', 'host_header', 'use_bridge']
    for k in keys:
        print(llm.get(k, ''))
    if not llm:
        sys.exit(1)
except Exception:
    sys.exit(1)
PYEOF
}

# 列出 llm.json 所有 preset 名
list_presets() {
    local cfg="$1"
    python3 - "$cfg" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
for name in d.get('llms', {}):
    print(name)
PYEOF
}

# 判定端点协议: openai(含 /v1 /v4 等 OpenAI 兼容) | anthropic
# 依赖 read_preset 的输出。evalscope 直连原始 base_url：
#   — OpenAI 兼容端点直接可测；
#   — Anthropic(/messages) 端点仅 eval 支持（--eval-type anthropic_api），perf 不支持。
detect_endpoint_type() {
    local base_url="$1"
    if [[ "$base_url" == *"/anthropic"* || "$base_url" == *"/apps/anthropic"* ]]; then
        echo "anthropic"
    else
        echo "openai"
    fi
}

# 生成带时间戳的结果目录名，供多次运行区分
make_output_dir() {
    local kind="$1" preset="$2"
    local stamp
    stamp="$(date '+%Y%m%d-%H%M%S')"
    echo "$EVAL_OUTPUT_ROOT/$preset/$kind-$stamp"
}

# 检查 evalscope 是否装了
check_installed() {
    if [[ ! -x "$EVALSCOPE_BIN" ]]; then
        echo "❌ evalscope 未安装。先跑: bash ccconfig/option-evalscope/init.sh --install" >&2
        return 1
    fi
    return 0
}
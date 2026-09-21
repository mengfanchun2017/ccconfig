#!/bin/bash
# option-evalscope/run-perf.sh — 按 llm.json preset 做 evalscope 性能压测（并发/TPS/延迟）
#
# 用法:
#   bash run-perf.sh --preset <name> [--parallel 1 5 20] [--number 100] \
#                    [--max-tokens 256] [--duration 60] [--stream]
#   bash run-perf.sh --list              # 列出可用 preset
#
# 并行度 sweep: --parallel 1 5 20 50 会依次跑这几个并发，各出报告。
# 端点处理: 仅支持 OpenAI 兼容端点（/v1 等）直连。Anthropic(/messages) 端点 perf 不支持。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
    echo "用法: bash run-perf.sh --preset <name> [选项]"
    echo "  --preset <name>      llm.json 里的预设名（--list 查看）"
    echo "  --parallel <n...>    并发 sweep，默认 \"1 5\""
    echo "  --number <n>         每并发下的请求数，默认 50"
    echo "  --max-tokens <n>     输出 token 上限，默认 256"
    echo "  --duration <sec>     单次运行时长预算（可选，与 --number 先到先止）"
    echo "  --stream / --no-stream  是否流式，默认 --stream"
    echo "  --rate <n>           QPS 限制（可选，默认不限）"
    echo "  --outputs-dir <dir>  覆盖输出目录"
    echo "  --list               列出 preset"
    exit "${1:-0}"
}

do_list() {
    local cfg; cfg="$(resolve_llm_json)" || return 1
    echo "可用 preset（cconfig/conf/llm.json -> ccprivate）:"
    list_presets "$cfg"
}

main() {
    local preset="" parallel_set=0 parallel=(1 5) number=50 max_tokens=256 duration="" stream=1 rate="" outputs_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset)   preset="$2"; shift 2 ;;
            --parallel) parallel_set=1; parallel=(); shift; while [[ $# -gt 0 && "$1" != --* ]]; do parallel+=("$1"); shift; done ;;
            --number)   number="$2"; shift 2 ;;
            --max-tokens) max_tokens="$2"; shift 2 ;;
            --duration) duration="$2"; shift 2 ;;
            --stream)   stream=1; shift ;;
            --no-stream) stream=0; shift ;;
            --rate)     rate="$2"; shift 2 ;;
            --outputs-dir) outputs_dir="$2"; shift 2 ;;
            --list)     do_list; return 0 ;;
            -h|--help)  usage 0 ;;
            *) echo "未知参数: $1"; usage 1 ;;
        esac
    done

    check_installed || return 1
    [[ -z "$preset" ]] && { echo "❌ 缺 --preset"; usage 1; }
    local cfg; cfg="$(resolve_llm_json)" || return 1
    [[ "$preset" == "__list__" ]] && { do_list; return 0; }

    # 读 preset 配置（多行，read 到数组）
    local preset_data
    preset_data="$(read_preset "$cfg" "$preset")" || { echo "❌ preset '$preset' 不存在（--list 查看）"; return 1; }
    local base_url model key host_header use_bridge
    base_url="$(echo "$preset_data" | sed -n '1p')"
    model="$(echo "$preset_data" | sed -n '2p')"
    key="$(echo "$preset_data" | sed -n '3p')"
    host_header="$(echo "$preset_data" | sed -n '4p')"
    use_bridge="$(echo "$preset_data" | sed -n '5p')"

    local etype; etype="$(detect_endpoint_type "$base_url" "$use_bridge")"
    echo -e "${CYAN}══ 性能压测 preset=$preset model=$model ──${NC}"
    echo "  端点类型: $etype  并发: ${parallel[*]}  请求/并发: $number  max_tokens: $max_tokens"

    # 输出目录
    if [[ -z "$outputs_dir" ]]; then
        outputs_dir="$(make_output_dir perf "$preset")"
    fi
    mkdir -p "$outputs_dir"

    # 决定 evalscope 连接目标（evalscope perf 仅支持 OpenAI 协议，直连 base_url）
    if [[ "$etype" == "anthropic" ]]; then
        echo "❌ perf 不支持 Anthropic(/messages) 端点：$base_url"
        echo "   精度评估可用 run-eval.sh（自动走 --eval-type anthropic_api）；性能压测需 OpenAI 兼容端点。"
        return 1
    fi
    local url="$base_url" api_key="$key"

    # 逐并发 run
    local p
    for p in "${parallel[@]}"; do
        echo -e "\n${CYAN}── 并发 = $p ──${NC}"
        local args=(
            --model "$model"
            --url "$url"
            --api openai
            --parallel "$p"
            --number "$number"
            --max-tokens "$max_tokens"
            --outputs-dir "$outputs_dir/parallel-$p"
        )
        [[ -n "$api_key" ]] && args+=(--api-key "$api_key")
        [[ -n "$duration" ]] && args+=(--duration "$duration")
        [[ -n "$rate" ]] && args+=(--rate "$rate")
        if [[ "$stream" == "1" ]]; then args+=(--stream); else args+=(--no-stream); fi

        echo "  \`$EVALSCOPE_BIN perf ${args[*]}\`"
        "$EVALSCOPE_BIN" perf "${args[@]}"
    done

    echo -e "\n${CYAN}══ 完成。结果在: $outputs_dir ──${NC}"
}

main "$@"
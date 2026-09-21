#!/bin/bash
# option-evalscope/run-eval.sh — 按 llm.json preset 做 evalscope 精度评估（MMLU/GSM8K 等）
#
# 用法:
#   bash run-eval.sh --preset <name> [--datasets mmlu gsm8k] [--limit 50] \
#                    [--collect-perf|--no-collect-perf]
#   bash run-eval.sh --list
#
# 默认评估 MMLU + GSM8K。--limit 控制每 benchmark 采样数（小跑用 20-50，正式评估去掉）。
# --collect-perf 会在精度评估同时记录 TTFT/TPOT/throughput（性能+精度一次出）。
# 端点协议: openai_api(OpenAI 兼容) / anthropic_api(/messages)，按 base_url 自动选择并直连。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
    echo "用法: bash run-eval.sh --preset <name> [选项]"
    echo "  --preset <name>       llm.json 里的预设名（--list 查看）"
    echo "  --datasets <d...>     benchmark 列表，默认 \"mmlu gsm8k\""
    echo "  --limit <n>           每 benchmark 采样数（正式评估请省略）"
    echo "  --collect-perf        同时记录性能指标（默认开）"
    echo "  --no-collect-perf     仅精度"
    echo "  --outputs-dir <dir>   覆盖输出目录"
    echo "  --work-dir <dir>      evalscope 工作目录"
    echo "  --list                列出 preset"
    exit "${1:-0}"
}

do_list() {
    local cfg; cfg="$(resolve_llm_json)" || return 1
    echo "可用 preset（cconfig/conf/llm.json -> ccprivate）:"
    list_presets "$cfg"
}

main() {
    local preset="" datasets=(mmlu gsm8k) limit="" collect_perf=1 outputs_dir="" work_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset)   preset="$2"; shift 2 ;;
            --datasets) shift; while [[ $# -gt 0 && "$1" != --* ]]; do datasets+=("$1"); shift; done ;;
            --limit)    limit="$2"; shift 2 ;;
            --collect-perf)   collect_perf=1; shift ;;
            --no-collect-perf) collect_perf=0; shift ;;
            --outputs-dir) outputs_dir="$2"; shift 2 ;;
            --work-dir)  work_dir="$2"; shift 2 ;;
            --list)     do_list; return 0 ;;
            -h|--help)  usage 0 ;;
            *) echo "未知参数: $1"; usage 1 ;;
        esac
    done

    check_installed || return 1
    [[ -z "$preset" ]] && { echo "❌ 缺 --preset"; usage 1; }
    local cfg; cfg="$(resolve_llm_json)" || return 1

    local preset_data
    preset_data="$(read_preset "$cfg" "$preset")" || { echo "❌ preset '$preset' 不存在（--list 查看）"; return 1; }
    local base_url model key host_header use_bridge
    base_url="$(echo "$preset_data" | sed -n '1p')"
    model="$(echo "$preset_data" | sed -n '2p')"
    key="$(echo "$preset_data" | sed -n '3p')"
    host_header="$(echo "$preset_data" | sed -n '4p')"
    use_bridge="$(echo "$preset_data" | sed -n '5p')"

    local etype; etype="$(detect_endpoint_type "$base_url")"
    echo -e "${CYAN}══ 精度评估 preset=$preset model=$model ──${NC}"
    echo "  端点协议: $etype  benchmark: ${datasets[*]}  limit: ${limit:-<all>}  collect_perf: $collect_perf"

    # 输出目录
    if [[ -z "$outputs_dir" ]]; then
        outputs_dir="$(make_output_dir eval "$preset")"
    fi
    mkdir -p "$outputs_dir"

    # 决定 eval 类型：openai_api(OpenAI 兼容) / anthropic_api(/messages)
    local eval_type="openai_api"
    [[ "$etype" == "anthropic" ]] && eval_type="anthropic_api"

    local args=(
        --model "$model"
        --api-url "$base_url"
        --eval-type "$eval_type"
        --datasets "${datasets[@]}"
        --outputs-dir "$outputs_dir"
    )
    [[ -n "$key" ]] && args+=(--api-key "$key")
    [[ -n "$limit" ]] && args+=(--limit "$limit")
    [[ -n "$work_dir" ]] && args+=(--work-dir "$work_dir")
    if [[ "$collect_perf" == "1" ]]; then args+=(--collect-perf); else args+=(--no-collect-perf); fi

    echo -e "\n  \`$EVALSCOPE_BIN eval ${args[*]}\`\n"
    "$EVALSCOPE_BIN" eval "${args[@]}"

    echo -e "\n${CYAN}══ 完成。结果在: $outputs_dir ──${NC}"
}

main "$@"
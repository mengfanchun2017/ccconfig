#!/bin/bash
# option-evalscope/run-all.sh — 一键对某 preset 跑 性能压测 + 精度评估
#
# 用法:
#   bash run-all.sh --preset <name> [--parallel 1 5 20] [--number 50] \
#                   [--datasets mmlu gsm8k] [--limit 50]
#   bash run-all.sh --list
#
# 等价于依次: run-perf.sh + run-eval.sh，结果分目录落盘。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

usage() {
    echo "用法: bash run-all.sh --preset <name> [选项]"
    echo "  --preset <name>    llm.json 预设名（--list 查看）"
    echo "  --parallel <n...>  并发 sweep（perf），默认 \"1 5\""
    echo "  --number <n>       每并发请求数（perf），默认 50"
    echo "  --datasets <d...>  benchmark 列表（eval），默认 \"mmlu gsm8k\""
    echo "  --limit <n>        每 benchmark 采样数（eval，正式评估省略）"
    echo "  --list             列出 preset"
    exit "${1:-0}"
}

do_list() {
    local cfg; cfg="$(resolve_llm_json)" || return 1
    echo "可用 preset（cconfig/conf/llm.json -> ccprivate）:"
    list_presets "$cfg"
}

main() {
    local preset="" perf_args=() eval_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --preset)  preset="$2"; shift 2 ;;
            --parallel)[[ $# -gt 1 ]] && { shift; while [[ $# -gt 0 && "$1" != --* ]]; do perf_args+=(--parallel "$1"); shift; done; } ;;
            --number)  [[ $# -gt 1 ]] && { perf_args+=(--number "$2"); shift 2; } ;;
            --datasets) shift; while [[ $# -gt 0 && "$1" != --* ]]; do eval_args+=(--datasets "$1"); shift; done ;;
            --limit)   [[ $# -gt 1 ]] && { eval_args+=(--limit "$2"); shift 2; } ;;
            --list)    do_list; return 0 ;;
            -h|--help) usage 0 ;;
            *) echo "未知参数: $1"; usage 1 ;;
        esac
    done

    check_installed || return 1
    [[ -z "$preset" ]] && { echo "❌ 缺 --preset"; usage 1; }

    local cfg; cfg="$(resolve_llm_json)" || return 1
    read_preset "$cfg" "$preset" >/dev/null || { echo "❌ preset '$preset' 不存在（--list 查看）"; return 1; }

    echo -e "${CYAN}══════ option-evalscope 一键评估: $preset ══════${NC}"
    echo -e "${CYAN}── [1/2] 性能压测 ══════${NC}"
    bash "$SCRIPT_DIR/run-perf.sh" --preset "$preset" "${perf_args[@]}"

    echo -e "\n${CYAN}── [2/2] 精度评估 ══════${NC}"
    bash "$SCRIPT_DIR/run-eval.sh" --preset "$preset" "${eval_args[@]}"

    echo -e "\n${CYAN}══════ 全部完成 ══════${NC}"
    echo "结果目录: $EVAL_OUTPUT_ROOT/$preset/"
}

main "$@"
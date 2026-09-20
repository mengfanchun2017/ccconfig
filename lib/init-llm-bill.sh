#!/bin/bash
# ==============================================
# LLM 用量统计（init-llm.sh bill 子命令独立版本）
#
# 数据来自 ccprivate/usage/YYYY-MM-DD.csv（option-usage/token-usage.sh 每日归档）
# 按 model + day 聚合 token 用量
#
# 用法:
#   bash init-llm-bill.sh              # 交互菜单（30 天统计 + 最近 7 天明细）
#   bash init-llm-bill.sh today        # 仅今天
#   bash init-llm-bill.sh model <name> # 单 model
#
# 删除历史（ADR-0029 落地）：
#   - 不再输入价格，也不展示成本：费用以上游账单为准，本地不折算
#   - 模型发现三源（llm.json presets + usage CSV + jsonl 实扫）
# ==============================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/path-helper.sh"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/interact.sh"

CONFIG_FILE="$(resolve_conf llm.json)" || exit 1
USAGE_DIR="${CCPRIVATE_HOME:-$HOME/git/ccprivate}/usage"

# 输出有历史用量的模型名，供菜单构建
# 三源：llm.json presets + usage CSV + jsonl 实扫
# （曾经还读 llm.json 的 pricing 只为产出一个标记列，而调用方从不使用该列）
list_models() {
    CCPRIVATE_HOME="${CCPRIVATE_HOME:-$HOME/git/ccprivate}" \
    python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys, os, re, glob, csv
d = json.load(open(sys.argv[1]))
seen = []
EXCLUDE = {'unknown', 'model', '<synthetic>'}
def add(m):
    m = (m or '').strip()
    if m and m not in EXCLUDE and not m.startswith('<') and m not in seen:
        seen.append(m)
for k, v in d.get('llms', {}).items():
    add(v.get('model', ''))
ccpriv = os.environ.get('CCPRIVATE_HOME', os.path.expanduser('~/git/ccprivate'))
for f in glob.glob(os.path.join(ccpriv, 'usage', '*.csv')):
    try:
        with open(f) as fh:
            for row in csv.DictReader(fh): add(row.get('model', ''))
    except: pass
pat = re.compile(r'"model"\s*:\s*"([^"]+)"')
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    try:
        with open(f, errors='ignore') as fh:
            for line in fh:
                m = pat.search(line)
                if m: add(m.group(1))
    except: pass
for m in seen:
    print(m)
PYEOF
}

# 按 model 聚合 30 天用量（CSV 累积）
# 输出：model, total_tokens, input_tokens, cache_read_tokens, output_tokens, sessions, days
by_model_30d() {
    python3 - "$USAGE_DIR" << 'PYEOF'
import csv, glob, os, sys, collections
usage_dir = sys.argv[1]
EXCLUDE = {'unknown', 'model', '<synthetic>'}
totals = collections.defaultdict(lambda: collections.Counter())
days_seen = collections.defaultdict(set)
sessions = collections.defaultdict(set)
for f in sorted(glob.glob(os.path.join(usage_dir, "20??-??-??.csv"))):
    day = os.path.basename(f).replace(".csv", "")
    try:
        with open(f) as fh:
            for row in csv.DictReader(fh):
                m = row.get("model", "").strip()
                if not m or m in EXCLUDE or m.startswith('<'): continue
                totals[m]["total"] += int(row.get("total_tokens", 0) or 0)
                totals[m]["input"] += int(row.get("input_tokens", 0) or 0)
                totals[m]["cache"] += int(row.get("cache_read_tokens", 0) or 0)
                totals[m]["output"] += int(row.get("output_tokens", 0) or 0)
                totals[m]["requests"] += int(row.get("request_count", 0) or 0)
                days_seen[m].add(day)
                sessions[m].add(row.get("session_id", ""))
    except Exception: pass
print("MODEL|TOTAL|INPUT|CACHE|OUTPUT|REQUESTS|DAYS|SESSIONS")
for m, c in sorted(totals.items(), key=lambda x: -x[1]["total"]):
    print(f"{m}|{c['total']}|{c['input']}|{c['cache']}|{c['output']}|{c['requests']}|{len(days_seen[m])}|{len(sessions[m])}")
PYEOF
}

# 按 day 聚合最近 N 天（默认 7）
recent_days() {
    local days="${1:-7}"
    python3 - "$USAGE_DIR" "$days" << 'PYEOF'
import csv, glob, os, sys, collections
usage_dir, days = sys.argv[1], int(sys.argv[2])
files = sorted(glob.glob(os.path.join(usage_dir, "20??-??-??.csv")))[-days:]
print("DAY|TOKENS|REQUESTS")
for f in files:
    day = os.path.basename(f).replace(".csv", "")
    tok = req = 0
    try:
        with open(f) as fh:
            for row in csv.DictReader(fh):
                tok += int(row.get("total_tokens", 0) or 0)
                req += int(row.get("request_count", 0) or 0)
    except Exception: pass
    print(f"{day}|{tok}|{req}")
PYEOF
}

# 按 model + day 显示（最近 N 天，每个 model 一段）
recent_by_model() {
    local days="${1:-7}"
    python3 - "$USAGE_DIR" "$days" << 'PYEOF'
import csv, glob, os, sys, collections
usage_dir, days = sys.argv[1], int(sys.argv[2])
files = sorted(glob.glob(os.path.join(usage_dir, "20??-??-??.csv")))[-days:]
by_m = collections.defaultdict(lambda: collections.Counter())
for f in files:
    day = os.path.basename(f).replace(".csv", "")
    try:
        with open(f) as fh:
            for row in csv.DictReader(fh):
                m = row.get("model", "").strip()
                if not m: continue
                by_m[m][day] += int(row.get("total_tokens", 0) or 0)
    except Exception: pass
day_headers = sorted({d for c in by_m.values() for d in c})
print("MODEL|" + "|".join(day_headers) + "|TOTAL")
for m, c in sorted(by_m.items(), key=lambda x: -sum(x[1].values())):
    row = [m] + [f"{c.get(d, 0):,}" for d in day_headers]
    row.append(f"{sum(c.values()):,}")
    print("|".join(row))
PYEOF
}

# 渲染 30 天 model 聚合（人类可读）
render_by_model() {
    local lines; lines=$(by_model_30d)
    local header
    header=$(echo "$lines" | head -1)
    echo ""
    echo "═══ 30 天用量（按 model 聚合）═══"
    echo ""
    printf "%-32s  %15s  %12s  %10s  %s\n" "model" "total_tokens" "cache_read" "requests" "days/sess"
    printf "%-32s  %15s  %12s  %10s  %s\n" "----" "----" "----" "----" "----"
    echo "$lines" | tail -n +2 | while IFS='|' read -r model total input cache output requests days sess; do
        [[ -z "$model" ]] && continue
        printf "%-32s  %15s  %12s  %10s  %s/%s\n" \
            "${model:0:32}" "$(printf "%'d" "$total")" \
            "$(printf "%'d" "$cache")" \
            "$requests" "$days" "$sess"
    done
}

# 渲染最近 7 天每天总量
render_recent_days() {
    local days="${1:-7}"
    local lines; lines=$(recent_days "$days")
    echo ""
    echo "═══ 最近 ${days} 天每日总量 ═══"
    echo ""
    printf "%-12s  %15s  %s\n" "day" "total_tokens" "requests"
    printf "%-12s  %15s  %s\n" "----" "----" "----"
    echo "$lines" | tail -n +2 | while IFS='|' read -r day tok req; do
        [[ -z "$day" ]] && continue
        printf "%-12s  %15s  %s\n" "$day" "$(printf "%'d" "$tok")" "$req"
    done
}

main() {
    local cmd="${1:-menu}"
    case "$cmd" in
        today)
            render_recent_days 1
            return 0
            ;;
        model)
            shift
            local model="${1:-}"
            [[ -z "$model" ]] && { error "用法: bash init-llm-bill.sh model <name>"; return 1; }
            render_by_model | grep -F "$model" || warn "  无 $model 用量"
            return 0
            ;;
        menu|"")
            render_recent_days 7
            render_by_model
            echo ""
            echo "  ── 操作 ──"
            local items=("按 model 查" "今天用量" "返回上层")
            local c; c=$(menu_select "用量统计" "${items[@]}")
            case "$c" in
                1)
                    local -a items=() names=()
                    while IFS= read -r m; do
                        [[ -z "$m" ]] && continue
                        items+=("$m")
                        names+=("$m")
                    done < <(list_models)
                    [[ ${#items[@]} -eq 0 ]] && { warn "  无已知模型"; return 0; }
                    items+=("返回上层")
                    local sel; sel=$(menu_select "选 model" "${items[@]}")
                    [[ -z "$sel" || "$sel" == "0" ]] && return 0
                    (( sel == ${#items[@]} )) && return 0
                    render_by_model | grep -F "${names[$((sel-1))]}" || warn "  无用量"
                    ;;
                2) render_recent_days 1 ;;
                *) return 0 ;;
            esac
            ;;
        *)
            error "未知子命令: $cmd（用 menu/today/model）"
            return 1
            ;;
    esac
}

[[ "${TEST_MODE:-0}" == "1" ]] || main "$@"
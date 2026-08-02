#!/bin/bash
# token-usage.sh — Claude Code 本地会话 token 用量聚合
#
# 数据源: ~/.claude/projects/**/*.jsonl
# 字段: 每个 assistant message 的 usage.{input,output,cache_creation,cache_read}_tokens
# 输出: 默认 CSV 到 ~/.cache/token-usage/YYYY-MM-DD.csv；可选 --feishu <url> 推多维表格
#
# 用法：
#   bash lib/token-usage.sh                          # 全量扫，写 CSV
#   bash lib/token-usage.sh --since 2026-07-30       # 限定起始日
#   bash lib/token-usage.sh --until 2026-07-31       # 限定截止日（不含）
#   bash lib/token-usage.sh --project ccconfig       # 限定 projectPath
#   bash lib/token-usage.sh --incremental            # 只处理新 session（state 去重）
#   bash lib/token-usage.sh --json                   # 输出 JSON 行到 stdout
#   bash lib/token-usage.sh --feishu <url>           # 推送到飞书多维表格（需先访问授权）
#   bash lib/token-usage.sh --report                 # 按日聚合到 stdout
#   bash lib/token-usage.sh --stats                  # 统计覆盖天数/session 数
#
# 挂载：bash maintain.sh token [args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/path-helper.sh" 2>/dev/null || true
source "$SCRIPT_DIR/colors.sh" 2>/dev/null || {
    RED=''; GREEN=''; YELLOW=''; CYAN=''; GRAY=''; NC=''
    info()  { echo -e "  $1" >&2; }
    ok()    { echo -e "  ✓ $1" >&2; }
    warn()  { echo -e "  ⚠ $1" >&2; }
    err()   { echo -e "  ✗ $1" >&2; }
}

# 重定向日志函数到 stderr（保护 --json stdout 管道）
info()  { echo -e "  ${GRAY:-}$1${NC:-}" >&2; }
ok()    { echo -e "  ${GREEN:-}✅ $1${NC:-}" >&2; }
warn()  { echo -e "  ${YELLOW:-}⚠  $1${NC:-}" >&2; }
err()   { echo -e "  ${RED:-}❌ $1${NC:-}" >&2; }
section() { echo -e "\n${CYAN:-}━━━ $1 ━━━${NC:-}" >&2; }

CLAUDE_PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
OUTPUT_DIR="${TOKEN_USAGE_OUTPUT:-$HOME/.cache/token-usage}"
STATE_FILE="$OUTPUT_DIR/state.json"
LLM_CONF="$(resolve_conf llm.json 2>/dev/null || echo "")"

# ========== 解析 pricing ==========
# 从 llm.json 读 pricing map：{ "model_name": {"input": 3.0, "output": 15.0, "cache_read": 0.3} } (USD / 1M tokens)
load_pricing() {
    if [[ -z "$LLM_CONF" || ! -f "$LLM_CONF" ]]; then
        return 1
    fi
    python3 - "$LLM_CONF" << 'PYEOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(0)
pricing = cfg.get("pricing", {})
print(json.dumps(pricing, ensure_ascii=False))
PYEOF
}

calc_cost() {
    # $1: input $2: output $3: cache_creation $4: cache_read $5: model $6: pricing_json
    local in="${1:-0}" out="${2:-0}" cc="${3:-0}" cr="${4:-0}" model="${5:-}" pricing="$6"
    if [[ -z "$pricing" || -z "$model" ]]; then
        echo "0"
        return
    fi
    python3 - "$in" "$out" "$cc" "$cr" "$model" "$pricing" << 'PYEOF' 2>/dev/null
import json, sys
in_t, out_t, cc_t, cr_t, model, pricing = sys.argv[1:6]
p = json.loads(pricing)
m = p.get(model)
if not m:
    print("0")
    sys.exit(0)
cost = (int(in_t) * m.get("input", 0)
        + int(out_t) * m.get("output", 0)
        + int(cc_t) * m.get("cache_creation", m.get("input", 0))
        + int(cr_t) * m.get("cache_read", 0)) / 1_000_000
print(f"{cost:.6f}")
PYEOF
}

# ========== 聚合 ==========
# 从单个 jsonl 文件抽取每个 session 的 token 统计
# 输出: 每行一个 session（JSON）
extract_sessions() {
    local since="$1" until="$2" project_filter="$3"
    [[ -d "$CLAUDE_PROJECTS_DIR" ]] || return 0

    find "$CLAUDE_PROJECTS_DIR" -name "*.jsonl" -type f -print0 2>/dev/null | \
    while IFS= read -r -d '' f; do
        python3 - "$f" "$since" "$until" "$project_filter" << 'PYEOF'
import json, sys, os
from collections import defaultdict

path, since, until, project_filter = sys.argv[1:5]

# 顶层目录名即 projectPath
project_path = os.path.basename(os.path.dirname(path))

# 过滤 project：匹配 projectPath 顶层目录名 或 jsonl 文件名前缀
if project_filter:
    fname = os.path.basename(path).replace(".jsonl", "")
    if project_filter not in project_path and not fname.startswith(project_filter):
        sys.exit(0)

# 聚合: session_id -> { model: { in, out, cc, cr, count }, first, last }
sessions = defaultdict(lambda: {
    "input": 0, "output": 0, "cache_creation": 0, "cache_read": 0,
    "request_count": 0, "first": None, "last": None,
    "models": defaultdict(lambda: {"input": 0, "output": 0, "cache_creation": 0, "cache_read": 0, "count": 0})
})

with open(path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if rec.get("type") != "assistant":
            continue
        msg = rec.get("message") or {}
        usage = msg.get("usage") or {}
        in_t = usage.get("input_tokens", 0)
        out_t = usage.get("output_tokens", 0)
        cc_t = usage.get("cache_creation_input_tokens", 0)
        cr_t = usage.get("cache_read_input_tokens", 0)
        model = msg.get("model") or "unknown"
        sid = rec.get("sessionId") or rec.get("session_id")
        ts = rec.get("timestamp")
        if not sid:
            continue
        s = sessions[sid]
        s["input"] += in_t
        s["output"] += out_t
        s["cache_creation"] += cc_t
        s["cache_read"] += cr_t
        s["request_count"] += 1
        if ts:
            if not s["first"] or ts < s["first"]:
                s["first"] = ts
            if not s["last"] or ts > s["last"]:
                s["last"] = ts
        mb = s["models"][model]
        mb["input"] += in_t
        mb["output"] += out_t
        mb["cache_creation"] += cc_t
        mb["cache_read"] += cr_t
        mb["count"] += 1

# 输出 JSON 行
for sid, s in sessions.items():
    first = (s["first"] or "")[:10]
    last = (s["last"] or "")[:10]
    if since and first and first < since:
        continue
    if until and last and last >= until:
        continue
    out = {
        "sessionId": sid,
        "projectPath": project_path,
        "inputTokens": s["input"],
        "outputTokens": s["output"],
        "cacheCreationTokens": s["cache_creation"],
        "cacheReadTokens": s["cache_read"],
        "totalTokens": s["input"] + s["output"] + s["cache_creation"] + s["cache_read"],
        "requestCount": s["request_count"],
        "firstActivity": s["first"],
        "lastActivity": s["last"],
        "models": dict(s["models"]),
    }
    print(json.dumps(out, ensure_ascii=False))
PYEOF
    done
}

# ========== 输出 ==========
write_csv() {
    local date_stamp="$1" rows_file="$2"
    mkdir -p "$OUTPUT_DIR"
    local out="$OUTPUT_DIR/${date_stamp}.csv"
    {
        echo "session_id,project_path,model,input_tokens,output_tokens,cache_create_tokens,cache_read_tokens,total_tokens,request_count,first_activity,last_activity,cost_usd"
        while IFS= read -r row; do
            [[ -z "$row" ]] && continue
            python3 - "$row" "$pricing" << 'PYEOF' 2>/dev/null
import json, sys, csv, sys
row = json.loads(sys.argv[1])
pricing = json.loads(sys.argv[2]) if sys.argv[2] else {}
sid = row["sessionId"][:8]
project = row["projectPath"]
# 主模型 = 用量最大的模型
models = row.get("models", {})
if models:
    main_model = max(models.items(), key=lambda x: sum(x[1][k] for k in ("input","output","cache_creation","cache_read")))[0]
else:
    main_model = "unknown"
p = pricing.get(main_model, {})
cost = ((row["inputTokens"] * p.get("input", 0))
        + (row["outputTokens"] * p.get("output", 0))
        + (row["cacheCreationTokens"] * p.get("cache_creation", p.get("input", 0)))
        + (row["cacheReadTokens"] * p.get("cache_read", 0))) / 1_000_000
print(f'{sid},{project},{main_model},{row["inputTokens"]},{row["outputTokens"]},{row["cacheCreationTokens"]},{row["cacheReadTokens"]},{row["totalTokens"]},{row["requestCount"]},{row["firstActivity"]},{row["lastActivity"]},{cost:.6f}')
PYEOF
        done < "$rows_file"
    } > "$out"
    ok "CSV 写入 $out"
}

write_report() {
    local rows_file="$1"
    python3 - "$rows_file" << 'PYEOF' 2>/dev/null
import json, sys
from collections import defaultdict
days = defaultdict(lambda: {"input": 0, "output": 0, "cc": 0, "cr": 0, "count": 0, "sessions": 0})
for line in open(sys.argv[1]):
    if not line.strip(): continue
    r = json.loads(line)
    d = (r.get("firstActivity") or "")[:10]
    if not d: continue
    days[d]["input"] += r["inputTokens"]
    days[d]["output"] += r["outputTokens"]
    days[d]["cc"] += r["cacheCreationTokens"]
    days[d]["cr"] += r["cacheReadTokens"]
    days[d]["count"] += r["requestCount"]
    days[d]["sessions"] += 1
print(f"{'Date':<12} {'Sessions':>8} {'Requests':>9} {'Input':>12} {'Output':>10} {'CacheRead':>12} {'Total':>14}")
for d in sorted(days):
    v = days[d]
    tot = v["input"] + v["output"] + v["cc"] + v["cr"]
    print(f"{d:<12} {v['sessions']:>8} {v['count']:>9} {v['input']:>12,} {v['output']:>10,} {v['cr']:>12,} {tot:>14,}")
PYEOF
}

# ========== 飞书多维表格 ==========
parse_feishu_url() {
    # 飞书多维表格 URL 形如：
    # https://ailab.feishu.cn/base/<base_token>?table=<table_id>
    # 或 https://ailab.feishu.cn/base/<base_token>/<table_id>
    # 返回 "base_token table_id"
    local url="$1"
    python3 - "$url" << 'PYEOF'
import re, sys, urllib.parse
url = sys.argv[1]
m = re.search(r'/base/([A-Za-z0-9_-]+)', url)
if not m:
    sys.exit(0)
base_token = m.group(1)
parsed = urllib.parse.urlparse(url)
q = urllib.parse.parse_qs(parsed.query)
table_id = (q.get("table") or [None])[0]
if not table_id:
    m2 = re.search(r'/base/' + re.escape(base_token) + r'/([A-Za-z0-9_-]+)', url)
    if m2:
        table_id = m2.group(1)
if table_id:
    print(f"{base_token} {table_id}")
PYEOF
}

# 多维表格字段名约定（用户提前在 base 里建好同名列）：
#   session_id (text)
#   project (text)
#   model (text)
#   input_tokens (number)
#   output_tokens (number)
#   cache_create (number)
#   cache_read (number)
#   total_tokens (number)
#   request_count (number)
#   first_activity (datetime)
#   last_activity (datetime)
#   cost_usd (number)
push_feishu() {
    local url="$1" rows_file="$2"
    local parsed
    parsed=$(parse_feishu_url "$url")
    if [[ -z "$parsed" ]]; then
        err "无法解析飞书 URL: $url"
        err "期望格式: https://<tenant>.feishu.cn/base/<base_token>?table=<table_id>"
        return 1
    fi
    local base_token table_id
    base_token=$(echo "$parsed" | awk '{print $1}')
    table_id=$(echo "$parsed" | awk '{print $2}')
    info "推送目标: base=$base_token table=$table_id"

    # 选 lark-cli 账号配置（用 ailab 账号作为默认）
    local config_dir="${LARKSUITE_CLI_CONFIG_DIR:-$HOME/.lark-cli-ailab}"
    export LARKSUITE_CLI_CONFIG_DIR="$config_dir"

    # 把 JSON 行转成 base 字段 map（每行 1 个 record）
    local payload
    payload=$(python3 - "$rows_file" << 'PYEOF'
import json, sys
records = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    r = json.loads(line)
    models = r.get("models", {})
    main_model = max(models.items(), key=lambda x: sum(x[1].get(k, 0) for k in ("input","output","cache_creation","cache_read")))[0] if models else "unknown"
    records.append({
        "session_id": r["sessionId"][:8],
        "project": r["projectPath"],
        "model": main_model,
        "input_tokens": int(r["inputTokens"]),
        "output_tokens": int(r["outputTokens"]),
        "cache_create": int(r["cacheCreationTokens"]),
        "cache_read": int(r["cacheReadTokens"]),
        "total_tokens": int(r["totalTokens"]),
        "request_count": int(r["requestCount"]),
        "first_activity": (r["firstActivity"] or "").replace("T", " ").rstrip("Z")[:19],
        "last_activity": (r["lastActivity"] or "").replace("T", " ").rstrip("Z")[:19],
    })
print(json.dumps({"create_records": records}, ensure_ascii=False))
PYEOF
)

    # 分批（每批 ≤200）
    local total
    total=$(echo "$payload" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['create_records']))")
    info "共 $total 条记录，分批写入..."

    local batch_size=200
    python3 - "$payload" "$batch_size" << 'PYEOF' | while IFS= read -r batch_json; do
import json, sys
data = json.loads(sys.argv[1])
batch_size = int(sys.argv[2])
recs = data["create_records"]
for i in range(0, len(recs), batch_size):
    print(json.dumps({"create_records": recs[i:i+batch_size]}, ensure_ascii=False))
PYEOF
        lark-cli base +record-batch-create \
            --as user \
            --base-token "$base_token" \
            --table-id "$table_id" \
            --json "$batch_json" 2>&1 | grep -E '"ok"|"error"' | head -1
    done
}

# ========== 增量 state ==========
filter_incremental() {
    local rows_file="$1"
    [[ -f "$STATE_FILE" ]] || { cat "$rows_file"; return; }
    # 用 python 直接过滤（最可靠）
    python3 - "$STATE_FILE" "$rows_file" << 'PYEOF'
import json, sys
state = json.load(open(sys.argv[1]))
known = set(state.get("processed", []))
for line in open(sys.argv[2]):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
        if r["sessionId"] not in known:
            print(line)
    except Exception:
        continue
PYEOF
}

update_state() {
    local rows_file="$1"
    mkdir -p "$OUTPUT_DIR"
    {
        local existing
        if [[ -f "$STATE_FILE" ]]; then
            existing=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(json.dumps(d.get('processed',[])))")
        else
            existing='[]'
        fi
        python3 - "$existing" "$rows_file" << 'PYEOF'
import json, sys
existing = json.loads(sys.argv[1])
known = set(existing)
for ln in open(sys.argv[2]):
    ln = ln.strip()
    if not ln: continue
    r = json.loads(ln)
    known.add(r["sessionId"])
print(json.dumps({"processed": sorted(known), "version": 1}, ensure_ascii=False))
PYEOF
    } > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# ========== CLI ==========
main() {
    local since="" until="" project="" json_output=false incremental=false
    local feishu_url="" report=false stats=false
    # json 模式走 stdout，其他模式日志走 stderr
    if [[ "${QUIET:-0}" == "1" || -n "${JSON_OUTPUT_FORCE:-}" ]]; then
        : # 保留 ok/warn/err，info 也输出
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)    since="$2"; shift 2 ;;
            --until)    until="$2"; shift 2 ;;
            --project)  project="$2"; shift 2 ;;
            --json)     json_output=true; shift ;;
            --incremental) incremental=true; shift ;;
            --feishu)   feishu_url="$2"; shift 2 ;;
            --report)   report=true; shift ;;
            --stats)    stats=true; shift ;;
            -h|--help)
                sed -n '2,25p' "$0" | sed 's/^# *//'
                exit 0 ;;
            *) err "未知参数: $1"; exit 1 ;;
        esac
    done

    local pricing
    pricing=$(load_pricing) || pricing="{}"
    [[ "$pricing" != "{}" ]] && info "已加载 pricing 配置 ($(echo "$pricing" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null) 个模型)" || info "未配置 pricing，成本列将为 0"

    info "扫描 $CLAUDE_PROJECTS_DIR ..."
    local tmp
    tmp=$(mktemp)
    trap "rm -f $tmp" EXIT

    extract_sessions "$since" "$until" "$project" > "$tmp" || true

    if [[ "$incremental" == true ]]; then
        local filtered
        filtered=$(mktemp)
        filter_incremental "$tmp" > "$filtered"
        mv "$filtered" "$tmp"
        update_state "$tmp"
    fi

    local count
    count=$(wc -l < "$tmp")
    info "扫描完成: $count 个 session"

    if [[ "$stats" == true ]]; then
        python3 - "$tmp" << 'PYEOF'
import json, sys
total_in = total_out = total_cc = total_cr = total_req = 0
days = set()
for line in open(sys.argv[1]):
    if not line.strip(): continue
    r = json.loads(line)
    total_in += r["inputTokens"]
    total_out += r["outputTokens"]
    total_cc += r["cacheCreationTokens"]
    total_cr += r["cacheReadTokens"]
    total_req += r["requestCount"]
    if r.get("firstActivity"): days.add(r["firstActivity"][:10])
print(f"Sessions:        {len(open(sys.argv[1]).readlines())}")
print(f"覆盖天数:        {len(days)}")
print(f"Input tokens:    {total_in:,}")
print(f"Output tokens:   {total_out:,}")
print(f"Cache create:    {total_cc:,}")
print(f"Cache read:      {total_cr:,}")
print(f"Request count:   {total_req:,}")
PYEOF
        exit 0
    fi

    if [[ "$report" == true ]]; then
        write_report "$tmp"
        exit 0
    fi

    if [[ "$json_output" == true ]]; then
        cat "$tmp"
        exit 0
    fi

    local today
    today=$(date +%Y-%m-%d)
    write_csv "$today" "$tmp"

    if [[ -n "$feishu_url" ]]; then
        push_feishu "$feishu_url" "$tmp"
    fi
}

main "$@"
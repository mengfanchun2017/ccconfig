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
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_ROOT/lib/path-helper.sh" 2>/dev/null || true
source "$CCCONFIG_ROOT/lib/colors.sh" 2>/dev/null || {
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

# 归档根目录优先级：
#   1) TOKEN_USAGE_OUTPUT 环境变量（用户临时指定）
#   2) ccprivate/usage/（永久记录，跟随 ccprivate 同步）
#   3) ~/.cache/token-usage/（fallback，本地缓存）
if [[ -n "${TOKEN_USAGE_OUTPUT:-}" ]]; then
    OUTPUT_DIR="$TOKEN_USAGE_OUTPUT"
elif [[ -d "${CCPRIVATE_HOME:-$HOME/git/ccprivate}" ]]; then
    OUTPUT_DIR="${CCPRIVATE_HOME:-$HOME/git/ccprivate}/usage"
else
    OUTPUT_DIR="$HOME/.cache/token-usage"
fi
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
    local since="$1" until="$2" project_filter="$3" mode="${4:-session}"
    [[ -d "$CLAUDE_PROJECTS_DIR" ]] || return 0

    find "$CLAUDE_PROJECTS_DIR" -name "*.jsonl" -type f -print0 2>/dev/null | \
    while IFS= read -r -d '' f; do
        python3 - "$f" "$since" "$until" "$project_filter" "$mode" << 'PYEOF'
import json, sys, os
from collections import defaultdict

path, since, until, project_filter, mode = sys.argv[1:6]

# 顶层目录名即 projectPath
project_path = os.path.basename(os.path.dirname(path))

# 过滤 project：匹配 projectPath 顶层目录名 或 jsonl 文件名前缀
if project_filter:
    fname = os.path.basename(path).replace(".jsonl", "")
    if project_filter not in project_path and not fname.startswith(project_filter):
        sys.exit(0)

def detect_route(model, endpoint_id):
    """根据 model 名 + endpoint ID 格式判断 route"""
    if not endpoint_id or endpoint_id.startswith("<"):
        return "synthetic"
    if endpoint_id.startswith("chatcmpl-"):
        return "bridge-openaialt"  # OpenAI 协议（bridge 转）
    if endpoint_id.startswith("msg_") and len(endpoint_id) == 24:
        return "anthropic-direct"  # 标准 Anthropic 直连
    # 32 hex = MiniMax 兼容 / deepseek 直连（也走 anthropic 协议）
    if len(endpoint_id) == 32 and all(c in "0123456789abcdef" for c in endpoint_id):
        if "deepseek" in model:
            return "deepseek-direct"  # api.deepseek.com/anthropic
        if "MiniMax" in model or "minimax" in model:
            return "minimax-direct"  # api.minimaxi.com/anthropic
        return "anthropic-compatible"
    # 36 字符 UUID
    if len(endpoint_id) == 36 and endpoint_id.count("-") == 4:
        return "anthropic-direct"  # 标准 UUID（Anthropic 协议）
    return "unknown"

# 聚合: session_id -> { model: { in, out, cc, cr, count }, first, last }
sessions = defaultdict(lambda: {
    "input": 0, "output": 0, "cache_creation": 0, "cache_read": 0,
    "request_count": 0, "first": None, "last": None,
    "session_name": "", "route": "",
    "models": defaultdict(lambda: {"input": 0, "output": 0, "cache_creation": 0, "cache_read": 0, "count": 0}),
    # by-day 模式：按 (day, model) 聚合
    "days": defaultdict(lambda: defaultdict(lambda: {"input":0,"output":0,"cache_creation":0,"cache_read":0,"count":0,"route":"","first_ts":"","last_ts":""})),
})

# 先扫一遍找每 session 的首条 user 消息（用作 session_name）+ 首个 endpoint（route）
session_first_user = {}
session_route = {}
with open(path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try: rec = json.loads(line)
        except: continue
        sid = rec.get("sessionId") or rec.get("session_id")
        if not sid: continue
        if rec.get("type") == "user" and sid not in session_first_user:
            msg = rec.get("message") or {}
            content = msg.get("content", "")
            if isinstance(content, list):
                text_parts = []
                for blk in content:
                    if isinstance(blk, dict):
                        text_parts.append(blk.get("text", ""))
                    elif isinstance(blk, str):
                        text_parts.append(blk)
                content = " ".join(text_parts)
            if isinstance(content, str):
                # 过滤系统/工具消息
                content = content.strip()
                if content and not content.startswith("<") and "command-message" not in content[:30]:
                    session_first_user[sid] = content[:80].replace("\n", " ").replace(",", " ").strip()
        elif rec.get("type") == "assistant" and sid not in session_route:
            msg = rec.get("message") or {}
            model = msg.get("model", "")
            eid = msg.get("id", "")
            session_route[sid] = detect_route(model, eid)

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
        # 注入 session_name 和 route（首次设置）
        if not s["session_name"]:
            s["session_name"] = session_first_user.get(sid, "")
        if not s["route"]:
            s["route"] = session_route.get(sid, "unknown")
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
            # by-day 桶
            day = ts[:10]
            dm = s["days"][day][model]
            dm["input"] += in_t
            dm["output"] += out_t
            dm["cache_creation"] += cc_t
            dm["cache_read"] += cr_t
            dm["count"] += 1
            if not dm["route"]:
                eid = msg.get("id", "")
                dm["route"] = detect_route(model, eid)
            if not dm["first_ts"] or ts < dm["first_ts"]:
                dm["first_ts"] = ts
            if not dm["last_ts"] or ts > dm["last_ts"]:
                dm["last_ts"] = ts
        mb = s["models"][model]
        mb["input"] += in_t
        mb["output"] += out_t
        mb["cache_creation"] += cc_t
        mb["cache_read"] += cr_t
        mb["count"] += 1

if mode == "by-day":
    # 每条 = (session, day, model) 一个记录
    for sid, s in sessions.items():
        for day in sorted(s["days"]):
            if since and day < since:
                continue
            if until and day >= until:
                continue
            for model, dm in s["days"][day].items():
                row = {
                    "sessionId": sid,
                    "day": day,
                    "projectPath": project_path,
                    "model": model,
                    "route": dm["route"] or s["route"],
                    "sessionName": s["session_name"],
                    "inputTokens": dm["input"],
                    "outputTokens": dm["output"],
                    "cacheCreationTokens": dm["cache_creation"],
                    "cacheReadTokens": dm["cache_read"],
                    "totalTokens": dm["input"] + dm["output"] + dm["cache_creation"] + dm["cache_read"],
                    "requestCount": dm["count"],
                    "firstTs": dm["first_ts"],
                    "lastTs": dm["last_ts"],
                }
                print(json.dumps(row, ensure_ascii=False))
    sys.exit(0)

# 默认 mode: 按 session 聚合
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
        "route": s["route"],
        "sessionName": s["session_name"],
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
        echo "session_id,project_path,route,session_name,model,input_tokens,cache_read_tokens,output_tokens,total_tokens,request_count,first_activity,last_activity,cost_cny"
        while IFS= read -r row; do
            [[ -z "$row" ]] && continue
            python3 - "$row" "$pricing" << 'PYEOF' 2>/dev/null
import json, sys, csv, sys
row = json.loads(sys.argv[1])
pricing = json.loads(sys.argv[2]) if sys.argv[2] else {}
sid = row["sessionId"][:8]
project = row["projectPath"]
route = row.get("route", "unknown")
session_name = row.get("sessionName", "").replace(",", " ").replace("\n", " ")[:80]
models = row.get("models", {})
if models:
    main_model = max(models.items(), key=lambda x: sum(x[1][k] for k in ("input","output","cache_creation","cache_read")))[0]
else:
    main_model = "unknown"
p = pricing.get(main_model, {})
cost = ((row["inputTokens"] * p.get("input", 0))
        + (row["outputTokens"] * p.get("output", 0))
        + (row["cacheReadTokens"] * p.get("cache_read", 0))) / 1_000_000
print(f'{sid},{project},{route},{session_name},{main_model},{row["inputTokens"]},{row["cacheReadTokens"]},{row["outputTokens"]},{row["totalTokens"]},{row["requestCount"]},{row["firstActivity"]},{row["lastActivity"]},{cost:.6f}')
PYEOF
        done < "$rows_file"
    } > "$out"
    ok "CSV 写入 $out"
}

# by-day 归档：每行 = (session, day, model) → by-day/<day>.csv
# 增量：state 记录 (sessionId, day, model) 组合，重复跳过
write_by_day_csv() {
    local rows_file="$1"
    mkdir -p "$OUTPUT_DIR"
    local state_by_day="$OUTPUT_DIR/state.by-day.json"

    # 读现有 state
    local existing
    if [[ -f "$state_by_day" ]]; then
        existing=$(python3 -c "import json; print(json.dumps(json.load(open('$state_by_day')).get('keys',[])))")
    else
        existing='[]'
    fi

    # 一次性：按 day 分组新增行 + 写文件 + 更新 state
    local added
    added=$(python3 - "$existing" "$rows_file" "$state_by_day" "$OUTPUT_DIR" "$pricing" << 'PYEOF' 2>/dev/null
import json, sys, os
from collections import defaultdict

existing_json, rows_file, state_file, out_dir, pricing = sys.argv[1:6]
seen = set(tuple(k) for k in json.loads(existing_json))

# 按 day 分组新增行
new_by_day = defaultdict(list)
new_keys = []

for line in open(rows_file):
    line = line.strip()
    if not line: continue
    r = json.loads(line)
    key = (r["sessionId"][:8], r["day"], r["model"])
    if key in seen: continue
    seen.add(key)
    new_keys.append(list(key))
    new_by_day[r["day"]].append(r)

p = json.loads(pricing) if pricing else {}

# 直接平铺写到 OUTPUT_DIR/<day>.csv
for day, rows in new_by_day.items():
    path = os.path.join(out_dir, f"{day}.csv")
    is_new = not os.path.exists(path)
    with open(path, "a") as f:
        if is_new:
            f.write("session_id,day,project_path,route,session_name,model,input_tokens,cache_read_tokens,output_tokens,total_tokens,request_count,first_ts,last_ts,cost_cny\n")
        for r in rows:
            pm = p.get(r["model"], {})
            cost = ((r["inputTokens"] * pm.get("input", 0))
                    + (r["outputTokens"] * pm.get("output", 0))
                    + (r["cacheReadTokens"] * pm.get("cache_read", 0))) / 1_000_000
            sn = (r.get("sessionName","") or "").replace(",", " ").replace("\n", " ")[:80]
            route = r.get("route", "unknown")
            f.write(f'{r["sessionId"][:8]},{day},{r["projectPath"]},{route},{sn},{r["model"]},{r["inputTokens"]},{r["cacheReadTokens"]},{r["outputTokens"]},{r["totalTokens"]},{r["requestCount"]},{r["firstTs"]},{r["lastTs"]},{cost:.6f}\n')

# 更新 state
merged = sorted(seen)
with open(state_file, "w") as f:
    json.dump({"keys": merged, "version": 2}, f)

print(len(new_keys))
PYEOF
)
    if [[ "$added" == "0" || -z "$added" ]]; then
        ok "by-day 无新增（state 已覆盖）"
    else
        ok "by-day 写入 $added 条 → $OUTPUT_DIR/"
    fi
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
#   cache_read (number)
#   output_tokens (number)
#   total_tokens (number)
#   request_count (number)
#   first_activity (datetime)
#   last_activity (datetime)
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
        "cache_read": int(r["cacheReadTokens"]),
        "output_tokens": int(r["outputTokens"]),
        "total_tokens": int(r["totalTokens"]),
        "request_count": int(r["requestCount"]),
        "first_activity": (r.get("firstActivity") or r.get("firstTs") or "").replace("T", " ").rstrip("Z")[:19],
        "last_activity": (r.get("lastActivity") or r.get("lastTs") or "").replace("T", " ").rstrip("Z")[:19],
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
    local feishu_url="" report=false stats=false by_day=false
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
            --by-day)   by_day=true; shift ;;
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

    local mode="session"
    [[ "$by_day" == true ]] && mode="by-day"
    extract_sessions "$since" "$until" "$project" "$mode" > "$tmp" || true

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
print(f"Cache read:      {total_cr:,}  (命中)")
print(f"Output tokens:   {total_out:,}")
print(f"Request count:   {total_req:,}")
if total_cc > 0:
    print(f"Cache create:    {total_cc:,}  (异常，你的环境应为 0)")
PYEOF
        exit 0
    fi

    if [[ "$report" == true ]]; then
        write_report "$tmp"
        exit 0
    fi

    if [[ "$by_day" == true ]]; then
        if [[ "$json_output" == true ]]; then
            cat "$tmp"
            exit 0
        fi
        # 归档到 by-day/<day>.csv（增量去重）
        write_by_day_csv "$tmp"
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
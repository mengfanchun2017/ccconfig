#!/bin/bash
# token-usage.sh — Claude Code 本地会话 token 用量聚合
#
# 数据源: ~/.claude/projects/**/*.jsonl
# 字段: 每个 assistant message 的 usage.{input,output,cache_creation,cache_read}_tokens
# 输出: 默认 CSV 到 ccprivate/usage/YYYY-MM-DD.csv；可选 --feishu <url> 推多维表格
#
# 用法：
#   bash token-usage.sh                              # 全量扫，写 session CSV
#   bash token-usage.sh --by-day                      # 归档到 <day>.csv（写一次：历史 day 跳过）
#   bash token-usage.sh --by-day --force             # 全量重算覆盖（改 pricing/列后用）
#   bash token-usage.sh --by-day --include-today     # 含今天（进行中 session 漂移）
#   bash token-usage.sh --since 2026-07-30           # 限定起始日
#   bash token-usage.sh --until 2026-08-01           # 限定截止日（不含）
#   bash token-usage.sh --project ccconfig           # 限定 projectPath
#   bash token-usage.sh --json                       # 输出 JSON 行到 stdout
#   bash token-usage.sh --feishu <url>               # 推送到飞书多维表格（可选）
#   bash token-usage.sh --report                     # 按日聚合到 stdout
#   bash token-usage.sh --stats                       # 跨 LLM 总量汇总（模型/route/时间/成本）
#
# 挂载：bash maintain.sh token [args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCCONFIG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$CCCONFIG_ROOT/lib/dry-run.sh"
source "$CCCONFIG_ROOT/lib/path-helper.sh" 2>/dev/null || true
source "$CCCONFIG_ROOT/lib/colors.sh"

# 日志到 stderr（保护 --json 输出的 stdout 管道）
# colors.sh 函数走 stdout，这里重定向到 stderr
info()    { echo -e "  ${GRAY:-}$1${NC:-}" >&2; }
ok()      { echo -e "  ${GREEN:-}✅ $1${NC:-}" >&2; }
err()     { echo -e "  ${RED:-}❌ $1${NC:-}" >&2; }
warn()    { echo -e "  ${YELLOW:-}⚠  $1${NC:-}" >&2; }
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
import json, sys, os, datetime
from collections import defaultdict

path, since, until, project_filter, mode = sys.argv[1:6]
project_path = os.path.basename(os.path.dirname(path))

if project_filter:
    fname = os.path.basename(path).replace(".jsonl", "")
    if project_filter not in project_path and not fname.startswith(project_filter):
        sys.exit(0)

def detect_route(model, endpoint_id):
    if not endpoint_id or endpoint_id.startswith("<"):
        return "synthetic"
    if endpoint_id.startswith("chatcmpl-"):
        return "bridge-openaialt"
    if endpoint_id.startswith("msg_") and len(endpoint_id) == 24:
        return "anthropic-direct"
    if len(endpoint_id) == 32 and all(c in "0123456789abcdef" for c in endpoint_id):
        cur = os.environ.get("CCCURRENT_LLM", "")
        if cur == "openaialt":
            return "bridge-openaialt"
        if "deepseek" in model:
            return "deepseek-direct"
        if "MiniMax" in model or "minimax" in model:
            return "minimax-direct"
        return "anthropic-compatible"
    if len(endpoint_id) == 36 and endpoint_id.count("-") == 4:
        return "anthropic-direct"
    return "unknown"

def parse_ts(ts):
    if not ts: return None
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z","+00:00"))
    except Exception:
        return None

def is_tool_result(rec):
    if rec.get("type") != "user":
        return False
    msg = rec.get("message") or {}
    content = msg.get("content")
    if isinstance(content, list):
        for blk in content:
            if isinstance(blk, dict) and blk.get("type") == "tool_result":
                return True
    return False

def compute_times(timeline):
    # timeline = [(dt, is_assistant, is_tool_result, is_real_user, day), ...]
    # 返回 {day: (model_ms, tool_ms, wall_ms)}
    if not timeline:
        return {}
    timeline.sort(key=lambda x: x[0])
    by_day = defaultdict(lambda: [0, 0, 0])  # model_ms, tool_ms, _
    first_by_day = {}
    last_by_day = {}
    prev = None
    for (dt, is_a, tr, is_ur, day) in timeline:
        if day:
            if day not in first_by_day:
                first_by_day[day] = dt
            last_by_day[day] = dt
        if prev and day:
            delta = (dt - prev[0]).total_seconds() * 1000
            if delta > 0:
                if is_a:
                    by_day[day][0] += delta
                elif tr:
                    by_day[day][1] += delta
        if is_a or tr or is_ur:
            prev = (dt, is_a, tr, is_ur, day)
    result = {}
    for day in first_by_day:
        wall = (last_by_day[day] - first_by_day[day]).total_seconds() * 1000
        result[day] = (int(by_day[day][0]), int(by_day[day][1]), int(max(0, wall)))
    return result

sessions = defaultdict(lambda: {
    "input": 0, "output": 0, "cache_creation": 0, "cache_read": 0,
    "request_count": 0, "turn_count": 0,
    "first": None, "last": None,
    "session_name": "", "ai_title": "", "route": "",
    "models": defaultdict(lambda: {"input":0,"output":0,"cache_creation":0,"cache_read":0,"count":0}),
    "days": defaultdict(lambda: defaultdict(lambda: {"input":0,"output":0,"cache_creation":0,"cache_read":0,"count":0,"route":"","first_ts":"","last_ts":"","turn_count":0})),
    "timeline": [],
})
ai_titles = {}

with open(path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try: rec = json.loads(line)
        except: continue
        t = rec.get("type")
        sid = rec.get("sessionId") or rec.get("session_id")
        ts = rec.get("timestamp", "")
        day = ts[:10] if ts else ""

        # ai-title 记录：Claude 自动生成的 session 标题
        if t == "ai-title":
            title = rec.get("aiTitle") or ""
            if title and sid and sid not in ai_titles:
                ai_titles[sid] = title
            continue
        if not sid: continue

        s = sessions[sid]
        tr = is_tool_result(rec)
        is_a = (t == "assistant")
        is_ur = (t == "user" and not tr)
        dt = parse_ts(ts)

        # timeline（用于时间计算）
        if dt:
            s["timeline"].append((dt, is_a, tr, is_ur, day))

        # session_name: ai-title 优先（后续注入），否则首条真实 user 文本
        if is_ur and not s["session_name"]:
            msg = rec.get("message") or {}
            content = msg.get("content", "")
            if isinstance(content, list):
                parts = []
                for blk in content:
                    if isinstance(blk, dict): parts.append(blk.get("text",""))
                    elif isinstance(blk, str): parts.append(blk)
                content = " ".join(parts)
            if isinstance(content, str):
                content = content.strip()
                if content and not content.startswith("<") and "command-message" not in content[:30]:
                    s["session_name"] = content[:80].replace("\n"," ").replace(","," ").strip()

        # route（首个 assistant）
        if is_a and not s["route"]:
            msg = rec.get("message") or {}
            s["route"] = detect_route(msg.get("model",""), msg.get("id",""))

        # turn_count（真实 user 输入，排除 tool_result）
        if is_ur:
            s["turn_count"] += 1
            if day:
                s["days"][day]["_turn_count"] = s["days"][day].get("_turn_count", 0) + 1

        # token 聚合（assistant）
        if is_a:
            msg = rec.get("message") or {}
            usage = msg.get("usage") or {}
            in_t = usage.get("input_tokens", 0)
            out_t = usage.get("output_tokens", 0)
            cc_t = usage.get("cache_creation_input_tokens", 0)
            cr_t = usage.get("cache_read_input_tokens", 0)
            model = msg.get("model") or "unknown"
            s["input"] += in_t
            s["output"] += out_t
            s["cache_creation"] += cc_t
            s["cache_read"] += cr_t
            s["request_count"] += 1
            if ts:
                if not s["first"] or ts < s["first"]: s["first"] = ts
                if not s["last"] or ts > s["last"]: s["last"] = ts
            if day:
                dm = s["days"][day][model]
                dm["input"] += in_t
                dm["output"] += out_t
                dm["cache_creation"] += cc_t
                dm["cache_read"] += cr_t
                dm["count"] += 1
                if not dm["route"]:
                    dm["route"] = detect_route(model, msg.get("id",""))
                if not dm["first_ts"] or ts < dm["first_ts"]: dm["first_ts"] = ts
                if not dm["last_ts"] or ts > dm["last_ts"]: dm["last_ts"] = ts
            mb = s["models"][model]
            mb["input"] += in_t
            mb["output"] += out_t
            mb["cache_creation"] += cc_t
            mb["cache_read"] += cr_t
            mb["count"] += 1

# 注入 ai-title 作 session_name（优先于首条 user 文本）
for sid, title in ai_titles.items():
    if sid in sessions:
        sessions[sid]["ai_title"] = title
        sessions[sid]["session_name"] = title

if mode == "by-day":
    for sid, s in sessions.items():
        day_times = compute_times(s["timeline"])
        for day in sorted(s["days"]):
            if since and day < since:
                continue
            if until and day >= until:
                continue
            mt, tt, wt = day_times.get(day, (0, 0, 0))
            for model, dm in s["days"][day].items():
                if model == "_turn_count":
                    continue
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
                    "turnCount": s["days"][day].get("_turn_count", 0),
                    "modelTimeMs": mt,
                    "toolTimeMs": tt,
                    "wallMs": wt,
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
    all_times = compute_times(s["timeline"])
    total_mt = sum(v[0] for v in all_times.values())
    total_tt = sum(v[1] for v in all_times.values())
    total_wt = sum(v[2] for v in all_times.values())
    out = {
        "sessionId": sid,
        "projectPath": project_path,
        "route": s["route"],
        "sessionName": s["session_name"],
        "aiTitle": s["ai_title"],
        "inputTokens": s["input"],
        "outputTokens": s["output"],
        "cacheCreationTokens": s["cache_creation"],
        "cacheReadTokens": s["cache_read"],
        "totalTokens": s["input"] + s["output"] + s["cache_creation"] + s["cache_read"],
        "requestCount": s["request_count"],
        "turnCount": s["turn_count"],
        "modelTimeMs": total_mt,
        "toolTimeMs": total_tt,
        "wallMs": total_wt,
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
    local out="$OUTPUT_DIR/sessions-${date_stamp}.csv"
    {
        echo "session_id,project_path,route,session_name,model,input_tokens,cache_read_tokens,output_tokens,total_tokens,request_count,turn_count,model_time_ms,tool_time_ms,wall_ms,first_activity,last_activity,cost_cny"
        while IFS= read -r row; do
            [[ -z "$row" ]] && continue
            python3 - "$row" "$pricing" << 'PYEOF' 2>/dev/null
import json, sys
row = json.loads(sys.argv[1])
pricing = json.loads(sys.argv[2]) if sys.argv[2] else {}
p = pricing.get
sid = row["sessionId"][:8]
project = row["projectPath"]
route = row.get("route", "unknown")
session_name = (row.get("sessionName") or "").replace(",", " ").replace("\n", " ")[:80]
models = row.get("models", {})
if models:
    main_model = max(models.items(), key=lambda x: sum(x[1][k] for k in ("input","output","cache_creation","cache_read")))[0]
else:
    main_model = "unknown"
mt = row.get("modelTimeMs", 0)
tt = row.get("toolTimeMs", 0)
wt = row.get("wallMs", 0)
pm = pricing.get(main_model, {})
cost = ((row["inputTokens"] * pm.get("input", 0))
        + (row["outputTokens"] * pm.get("output", 0))
        + (row["cacheReadTokens"] * pm.get("cache_read", 0))) / 1_000_000
print(f'{sid},{project},{route},{session_name},{main_model},{row["inputTokens"]},{row["cacheReadTokens"]},{row["outputTokens"]},{row["totalTokens"]},{row["requestCount"]},{row.get("turnCount",0)},{mt},{tt},{wt},{row["firstActivity"]},{row["lastActivity"]},{cost:.6f}')
PYEOF
        done < "$rows_file"
    } > "$out"
    ok "CSV 写入 $out"
}

# by-day 归档：每行 = (session, day, model) → <day>.csv
# 写一次策略：历史 day（< today）已写过即跳过（jsonl append-only，数据冻结，
# 重算结果相同）；今天 always 覆盖（进行中 session 漂移）。--force 全量重算
# （改列结构/改 pricing 后用）。首次运行或补缺时，缺失 day 自动写。
write_by_day_csv() {
    local rows_file="$1" today="$2" force="${3:-false}"
    mkdir -p "$OUTPUT_DIR"
    local written skipped
    local res
    res=$(python3 - "$rows_file" "$OUTPUT_DIR" "$pricing" "$today" "$force" << 'PYEOF' 2>/dev/null
import json, sys, os
from collections import defaultdict

rows_file, out_dir, pricing, today, force = sys.argv[1:6]
p = json.loads(pricing) if pricing else {}
force = (force == "true")

by_day = defaultdict(list)
for line in open(rows_file):
    line = line.strip()
    if not line: continue
    r = json.loads(line)
    by_day[r["day"]].append(r)

header = ("session_id,day,project_path,route,session_name,model,"
         "input_tokens,cache_read_tokens,output_tokens,total_tokens,"
         "request_count,turn_count,model_time_ms,tool_time_ms,wall_ms,"
         "first_ts,last_ts,cost_cny\n")

written = 0
skipped = 0
for day, rows in sorted(by_day.items()):
    path = os.path.join(out_dir, f"{day}.csv")
    # 写一次：历史 day 已存在且非 force → 跳过（数据已冻结）
    if not force and day < today and os.path.exists(path):
        skipped += 1
        continue
    rows.sort(key=lambda r: (r.get("firstTs") or "", r["sessionId"]))
    with open(path, "w") as f:
        f.write(header)
        for r in rows:
            pm = p.get(r["model"], {})
            cost = ((r["inputTokens"] * pm.get("input", 0))
                    + (r["outputTokens"] * pm.get("output", 0))
                    + (r["cacheReadTokens"] * pm.get("cache_read", 0))) / 1_000_000
            sn = (r.get("sessionName","") or "").replace(",", " ").replace("\n", " ")[:80]
            route = r.get("route", "unknown")
            f.write(f'{r["sessionId"][:8]},{day},{r["projectPath"]},{route},{sn},{r["model"]},'
                    f'{r["inputTokens"]},{r["cacheReadTokens"]},{r["outputTokens"]},{r["totalTokens"]},'
                    f'{r["requestCount"]},{r.get("turnCount",0)},{r.get("modelTimeMs",0)},'
                    f'{r.get("toolTimeMs",0)},{r.get("wallMs",0)},'
                    f'{r["firstTs"]},{r["lastTs"]},{cost:.6f}\n')
    written += len(rows)

print(f"{written}\t{skipped}")
PYEOF
)
    written="${res%%$'\t'*}"
    skipped="${res##*$'\t'}"
    if [[ "$skipped" -gt 0 ]]; then
        ok "by-day 写入 $written 条，跳过 $skipped 个已冻结历史 day"
    elif [[ -z "$written" || "$written" == "0" ]]; then
        ok "by-day 无数据"
    else
        ok "by-day 写入 $written 条 → $OUTPUT_DIR/"
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
#   sessionid (text) — 主标识
#   session_day (date) — 日期（YYYY-MM-DD）
#   project (text)
#   route (text)
#   model (text)
#   session_name (text)
#   input_tokens (int)
#   cache_read_tokens (int) — 命中缓存
#   output_tokens (int)
#   total_tokens (int)
#   user_request (int) — turn 数
#   agent_request (int) — assistant 消息数
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
    # 过滤：交互 <=2 的测试 session 跳过；synthetic 跳过
    local payload
    payload=$(python3 - "$rows_file" << 'PYEOF'
import json, sys
records = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    r = json.loads(line)

    # 过滤：测试 session（请求 <= 2 或 model=<synthetic>）
    if r.get("requestCount", 0) <= 2 or r.get("model","") == "<synthetic>":
        continue

    models = r.get("models", {})
    main_model = max(models.items(), key=lambda x: sum(x[1].get(k, 0) for k in ("input","output","cache_creation","cache_read")))[0] if models else "unknown"

    sid = r["sessionId"][:8]
    # by-day 模式有 day 字段；session 模式没 day，用 firstActivity 日期
    day_str = r.get("day") or (r.get("firstActivity") or r.get("firstTs") or "")[:10]
    # 飞书 datetime 字段需毫秒时间戳
    import time
    day_ms = int(time.mktime(time.strptime(day_str, "%Y-%m-%d")) * 1000) if day_str else 0

    # by-day 模式 row 直接有 model 字段（按天按 model 聚合）；
    # session 模式用 models 里用量最大的 model
    row_model = r.get("model") or main_model

    records.append({
        "sessionid": sid,
        "session_day": day_ms,
        "project": r["projectPath"],
        "route": r.get("route", "unknown"),
        "model": row_model,
        "session_name": (r.get("sessionName","") or "")[:80] or sid,
        "input_tokens": int(r["inputTokens"]),
        "cache_read_tokens": int(r["cacheReadTokens"]),
        "output_tokens": int(r["outputTokens"]),
        "total_tokens": int(r["totalTokens"]),
        "user_request": int(r.get("userRequestCount", 0)),
        "agent_request": int(r.get("requestCount", 0)),
    })
print(json.dumps({"create_records": records}, ensure_ascii=False))
PYEOF
)

    # 分批（每批 ≤200）
    local total
    total=$(echo "$payload" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['create_records']))" 2>/dev/null || echo "0")
    if [[ "$total" == "0" || -z "$total" ]]; then
        warn "没有符合条件的记录（过滤测试 session 后为空）"
        return 1
    fi
    info "共 $total 条记录（已过滤测试 session），分批写入..."

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

# ========== Backfill 补跑 ==========
# 自动检测归档缺失的日期，补跑（不含今天）
# 找 csv 文件：从 $OUTPUT_DIR 找所有 YYYY-MM-DD.csv，按日期排序
# 输出缺失日期列表到 stdout
backfill_missing_days() {
    local today
    today=$(date +%Y-%m-%d)
    local existing_days
    existing_days=$(ls "$OUTPUT_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].csv 2>/dev/null | sed 's/.*\///;s/\.csv$//' | sort -u)
    local all_days
    # 最早日期 = state.by-day.json 第一条记录的 day；最晚 = 昨天
    local first_day
    first_day=$(ls ~/.claude/projects/*/*.jsonl 2>/dev/null | head -1)
    if [[ -z "$first_day" ]]; then
        echo "$(date +%Y-%m-%d)"
        return
    fi
    # 用最早 session 的 firstTs 当起始日期
    first_day=$(python3 -c "
import json, os, glob
files = glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl'))
files.sort(key=lambda f: os.path.getmtime(f))
for f in files:
    for line in open(f):
        try: r = json.loads(line)
        except: continue
        if r.get('type') == 'assistant':
            ts = r.get('timestamp', '')
            if ts: print(ts[:10])
            break
    else: continue
    break
" 2>/dev/null)
    if [[ -z "$first_day" ]]; then first_day=$(date +%Y-%m-%d); fi

    # 生成 [first_day, today) 范围
    python3 - "$first_day" "$today" "$existing_days" << 'PYEOF'
import sys, datetime
start, end, existing_str = sys.argv[1:4]
existing = set(existing_str.split()) if existing_str.strip() else set()
start_d = datetime.date.fromisoformat(start)
end_d = datetime.date.fromisoformat(end)
missing = []
d = start_d
while d < end_d:
    ds = d.isoformat()
    if ds not in existing:
        missing.append(ds)
    d += datetime.timedelta(days=1)
print(" ".join(missing))
PYEOF
}

# ========== CLI ==========
main() {
    local since="" until="" project="" json_output=false incremental=false
    local feishu_url="" report=false stats=false by_day=false include_today=false auto_backfill=false force=false
    # json 模式走 stdout，其他模式日志走 stderr
    if [[ "${QUIET:-0}" == "1" || -n "${JSON_OUTPUT_FORCE:-}" ]]; then
        : # 保留 ok/warn/err，info 也输出
    fi

    # 默认从 ccprivate/conf/token-usage.json 读 feishu_url
    if [[ -z "${TOKEN_USAGE_CONFIG:-}" && -n "$CCPRIVATE_HOME" && -f "$CCPRIVATE_HOME/conf/token-usage.json" ]]; then
        TOKEN_USAGE_CONFIG="$CCPRIVATE_HOME/conf/token-usage.json"
    fi
    if [[ -z "${TOKEN_USAGE_CONFIG:-}" && -f "$HOME/git/ccprivate/conf/token-usage.json" ]]; then
        TOKEN_USAGE_CONFIG="$HOME/git/ccprivate/conf/token-usage.json"
    fi
    if [[ -n "${TOKEN_USAGE_CONFIG:-}" && -f "$TOKEN_USAGE_CONFIG" ]]; then
        local cfg_url cfg_today
        cfg_url=$(python3 -c "import json;d=json.load(open('$TOKEN_USAGE_CONFIG'));print(d.get('feishu_url',''))" 2>/dev/null)
        cfg_today=$(python3 -c "import json;d=json.load(open('$TOKEN_USAGE_CONFIG'));print(d.get('include_today',False))" 2>/dev/null)
        [[ -n "$cfg_url" && -z "$feishu_url" ]] && feishu_url="$cfg_url"
        [[ "$cfg_today" == "True" ]] && include_today=true
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --since)    since="$2"; shift 2 ;;
            --until)    until="$2"; shift 2 ;;
            --project)  project="$2"; shift 2 ;;
            --json)     json_output=true; shift ;;
            --incremental) incremental=true; shift ;;
            --feishu)   feishu_url="$2"; shift 2 ;;
            --config)   TOKEN_USAGE_CONFIG="$2"; shift 2 ;;
            --report)   report=true; shift ;;
            --by-day)   by_day=true; shift ;;
            --include-today) include_today=true; shift ;;
            --auto-backfill) auto_backfill=true; shift ;;
            --force)    force=true; shift ;;
            --stats)    stats=true; shift ;;
            -h|--help)
                sed -n '2,25p' "$0" | sed 's/^# *//'
                exit 0 ;;
            *) err "未知参数: $1"; exit 1 ;;
        esac
    done

    # 传当前 LLM 名给 detect_route（区分 deepseek-direct 和 bridge-openaialt）
    local cur_llm
    cur_llm=$(python3 -c "import json; d=json.load(open('$LLM_CONF')); print(d.get('current',''))" 2>/dev/null || echo "")
    export CCCURRENT_LLM="$cur_llm"

    local pricing
    pricing=$(load_pricing) || pricing="{}"
    [[ "$pricing" != "{}" ]] && info "已加载 pricing 配置 ($(echo "$pricing" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null) 个模型)" || info "未配置 pricing，成本列将为 0"

    info "扫描 $CLAUDE_PROJECTS_DIR ..."
    local tmp
    tmp=$(mktemp)
    trap "rm -f $tmp" EXIT

    local mode="session"
    [[ "$by_day" == true ]] && mode="by-day"

    # 默认截止到昨天（避免当天的进行中 session 数据不稳定）
    # until=today 作为排他上界：day >= today 被跳过，含昨天
    if [[ -z "$until" && "$include_today" != true ]]; then
        until=$(date +%Y-%m-%d)
        info "默认截止到昨天（今天 $until 不写入），加 --include-today 包含今日"
    fi

    # --auto-backfill 已废弃：全量覆盖写天然补全所有缺失 day（见 write_by_day_csv）
    [[ "$auto_backfill" == true ]] && info "auto-backfill 已内置于全量覆盖写，无需单独补跑"

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
        python3 - "$tmp" "$pricing" << 'PYEOF'
import json, sys
from collections import defaultdict
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
p = json.loads(sys.argv[2]) if sys.argv[2] else {}
if not rows:
    print("无数据"); sys.exit(0)
total_in = total_out = total_cc = total_cr = total_req = total_turn = 0
total_mt = total_tt = total_wt = total_cost = 0
days = set()
by_model = defaultdict(lambda: {"in":0,"cr":0,"out":0,"total":0,"req":0,"sessions":0,"cost":0.0})
by_route = defaultdict(lambda: {"total":0,"sessions":0})
for r in rows:
    total_in += r["inputTokens"]; total_out += r["outputTokens"]
    total_cc += r["cacheCreationTokens"]; total_cr += r["cacheReadTokens"]
    total_req += r["requestCount"]; total_turn += r.get("turnCount", 0)
    total_mt += r.get("modelTimeMs", 0)
    total_tt += r.get("toolTimeMs", 0)
    total_wt += r.get("wallMs", 0)
    if r.get("firstActivity"): days.add(r["firstActivity"][:10])
    models = r.get("models", {})
    for m, v in models.items():
        mi = v.get("input",0); mo = v.get("output",0)
        mcc = v.get("cache_creation",0); mcr = v.get("cache_read",0)
        mt = mi+mo+mcc+mcr
        pm = p.get(m, {})
        c = ((mi*pm.get("input",0)) + (mo*pm.get("output",0)) + (mcr*pm.get("cache_read",0))) / 1_000_000
        d = by_model[m]
        d["in"] += mi; d["cr"] += mcr; d["out"] += mo
        d["total"] += mt; d["req"] += v.get("count",0); d["cost"] += c
    # 主模型用于 route 维度
    if models:
        mm = max(models.items(), key=lambda x: sum(x[1][k] for k in ("input","output","cache_creation","cache_read")))[0]
    else:
        mm = "unknown"
    by_route[r.get("route","unknown")]["total"] += r["totalTokens"]
    by_route[r.get("route","unknown")]["sessions"] += 1
    by_model[mm]["sessions"] += 1 if mm != "unknown" else 0
def h(ms):
    s = ms/1000
    if s < 60: return f"{s:.0f}s"
    if s < 3600: return f"{s/60:.1f}m"
    return f"{s/3600:.2f}h"
print(f"=== 总览 ===")
print(f"Sessions:     {len(rows)}")
print(f"覆盖天数:     {len(days)}")
print(f"Turns:        {total_turn}  (真实用户输入数)")
print(f"Requests:     {total_req}  (assistant 消息数)")
print()
print(f"=== Token 总量 ===")
print(f"Input:        {total_in:,}")
print(f"Cache read:   {total_cr:,}  (命中缓存)")
if total_cc > 0:
    print(f"Cache create: {total_cc:,}  (异常，应为 0)")
print(f"Output:       {total_out:,}")
print(f"Total:        {total_in+total_out+total_cc+total_cr:,}")
print()
print(f"=== 时间（复杂度指标）===")
print(f"Model time:   {h(total_mt)}  (LLM 推理挂钟，跨所有 LLM)")
print(f"Tool time:    {h(total_tt)}  (工具执行挂钟)")
print(f"Wall time:    {h(total_wt)}  (挂钟跨度，含发呆)")
print()
print(f"=== 按模型 ===")
print(f"{'Model':<24} {'Sessions':>8} {'Input':>12} {'CacheRead':>12} {'Output':>10} {'Total':>14} {'Cost':>9}")
for m in sorted(by_model, key=lambda x: -by_model[x]["total"]):
    d = by_model[m]
    if d["total"] == 0: continue
    print(f"{m[:24]:<24} {d['sessions']:>8} {d['in']:>12,} {d['cr']:>12,} {d['out']:>10,} {d['total']:>14,} {d['cost']:>8.2f}$")
print()
print(f"=== 按 Route ===")
print(f"{'Route':<22} {'Sessions':>8} {'Total tokens':>14}")
for r in sorted(by_route, key=lambda x: -by_route[x]["total"]):
    d = by_route[r]
    print(f"{r[:22]:<22} {d['sessions']:>8} {d['total']:>14,}")
print()
print(f"=== 总成本 ===")
tot_cost = sum(by_model[m]["cost"] for m in by_model)
print(f"估算总成本: {tot_cost:.2f} USD")
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
        # 归档到 <day>.csv（写一次：历史 day 跳过，今天覆盖，--force 全量重算）
        local today_str
        today_str=$(date +%Y-%m-%d)
        write_by_day_csv "$tmp" "$today_str" "$force"
        # 顺便推飞书（如果有 URL）
        if [[ -n "$feishu_url" ]]; then
            push_feishu "$feishu_url" "$tmp"
        fi
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
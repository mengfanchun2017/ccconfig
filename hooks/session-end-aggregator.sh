#!/usr/bin/env bash
# SessionEnd hook: 从 transcript 聚合 token + 事件 + 用户需求 → 写飞书 worklog
# 设计：自动写飞书，说明栏用结构化数据（commits/edits/prompts/notes/tokens），
#      不用 "auto-aggregated" 这种占位符。
# Agent 可在工作中往 /tmp/claude_session_<sid>_notes.md 追加 1 行总结。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -uo pipefail

INPUT=$(cat)

SID=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
TPATH=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('transcript_path',''))" 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null)
REASON=$(printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('reason',''))" 2>/dev/null)

if [ -z "$TPATH" ] || [ ! -f "$TPATH" ]; then
  echo "session-end-aggregator: no transcript ($TPATH), skip" >&2
  exit 0
fi
if [ -z "$SID" ]; then
  SID=$(basename "$TPATH" .jsonl)
fi

OUT="/tmp/claude_session_${SID}.json"
NOTES="/tmp/claude_session_${SID}_notes.md"

python3 "$SCRIPT_DIR/session_end_aggregator.py" "$TPATH" "$SID" "$CWD" "$REASON" "$OUT" "$NOTES"

# === 定时整合：日合并 / 周总结 / 月提醒 ===
MERGE_MARKER="/tmp/f-logme_last_merge"
WEEKLY_MARKER="/tmp/f-logme_last_weekly"
MONTHLY_MARKER="/tmp/f-logme_last_monthly"
CONSOLIDATE_SCRIPT="$HOME/.claude/skills/f-logme/worklog_consolidate.py"
NOW=$(date +%s)
DAY=86400
WEEK=604800   # 7 天
MONTH=2592000 # 30 天

# 每日自动去重合并
if [ -f "$MERGE_MARKER" ]; then
    LAST=$(cat "$MERGE_MARKER")
else
    LAST=0
fi
if [ $((NOW - LAST)) -ge $DAY ] && [ -f "$CONSOLIDATE_SCRIPT" ]; then
    echo "session-end-aggregator: daily merge triggered" >&2
    python3 "$CONSOLIDATE_SCRIPT" --mode merge --write >/dev/null 2>&1 && date +%s > "$MERGE_MARKER"
fi

# 每周自动生成周总结
if [ -f "$WEEKLY_MARKER" ]; then
    LAST_W=$(cat "$WEEKLY_MARKER")
else
    LAST_W=0
fi
if [ $((NOW - LAST_W)) -ge $WEEK ]; then
    NOTES="/tmp/claude_session_${SID}_notes.md"
    echo "[f-logme] 本周工作总结待生成，请调用 f-logme skill 做周总结（做周反思）。" >> "$NOTES"
    date +%s > "$WEEKLY_MARKER"
fi

# 阶段提醒（距上次 > 30 天）
if [ -f "$MONTHLY_MARKER" ]; then
    LAST_M=$(cat "$MONTHLY_MARKER")
else
    LAST_M=0
fi
if [ $((NOW - LAST_M)) -ge $MONTH ]; then
    NOTES="/tmp/claude_session_${SID}_notes.md"
    echo "[f-logme] 距上次阶段总结已超过 30 天，建议运行: python3 worklog_consolidate.py --mode monthly" >> "$NOTES"
    date +%s > "$MONTHLY_MARKER"
fi

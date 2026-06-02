#!/usr/bin/env bash
# SessionEnd hook: 从 transcript 聚合 token + 自动写 worklog Base
# 失败兜底：写 /tmp/claude_session_<sid>.json 等手动补记

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

python3 - "$TPATH" "$SID" "$CWD" "$REASON" "$OUT" <<'PY'
import json, sys, os, datetime, subprocess

transcript, sid, cwd, reason, out_path = sys.argv[1:6]

agg = {
    "input_tokens": 0,
    "output_tokens": 0,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 0,
}
model, models = None, set()
commits, edits, user_msgs, asst_msgs = [], [], 0, 0

with open(transcript) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except Exception:
            continue
        t = o.get("type", "")
        if t == "assistant":
            asst_msgs += 1
            m = o.get("message", {})
            if m.get("model"):
                models.add(m["model"])
                model = m["model"]
            usage = m.get("usage", {})
            for k in agg:
                if k in usage:
                    agg[k] += usage[k]
            content = m.get("content", [])
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        n, inp = c.get("name", ""), c.get("input", {})
                        if n == "Bash":
                            cmd = inp.get("command", "")
                            if "git commit" in cmd:
                                commits.append(cmd[:200])
                        elif n in ("Write", "Edit", "MultiEdit"):
                            fp = inp.get("file_path", "")
                            if fp:
                                edits.append({"tool": n, "file": fp})
        elif t == "user":
            user_msgs += 1

result = {
    "session_id": sid,
    "cwd": cwd,
    "reason": reason,
    "transcript_path": transcript,
    "ended_at": datetime.datetime.now().isoformat(),
    "tokens": agg,
    "model": model,
    "models_used": sorted(models),
    "stats": {"assistant_message_count": asst_msgs, "user_message_count": user_msgs},
    "events": {"git_commits": commits, "file_edits": edits},
}

tmp = out_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
os.replace(tmp, out_path)
with open("/tmp/claude_last_session.json", "w") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)

# 自动写 worklog Base
T = "LX5lb6VfdaJHWrsRbTgc8Y50nmj"
TBL = "tblVsC0L7QFzMeYM"
date_str = datetime.date.today().isoformat()
sid_short = sid[:8]
title = f"[auto] {date_str} session {sid_short} ({reason or 'end'})"
desc = (
    f"{asst_msgs} asst / {user_msgs} user msgs, "
    f"{len(edits)} edits, {len(commits)} commits. "
    f"cwd={cwd}"
)
wl_payload = {
    "fields": [
        "标题", "成果类型", "量化结果", "说明", "日期",
        "input_tokens", "output_tokens",
        "cache_creation_input_tokens", "cache_read_input_tokens", "model",
    ],
    "rows": [[
        title, "", desc,
        f"auto-aggregated by SessionEnd hook",
        date_str,
        agg["input_tokens"], agg["output_tokens"],
        agg["cache_creation_input_tokens"], agg["cache_read_input_tokens"],
        model or "",
    ]],
}

wl_tmp = f"/tmp/wl_{sid}.json"
with open(wl_tmp, "w") as f:
    json.dump(wl_payload, f, ensure_ascii=False)

env = os.environ.copy()
env["LARKSUITE_CLI_CONFIG_DIR"] = os.path.expanduser("~/.lark-cli-<account>")
env["PATH"] = os.path.expanduser("~/.local/bin:") + env.get("PATH", "")

try:
    proc = subprocess.run(
        ["lark-cli", "base", "+record-batch-create",
         "--base-token", T, "--table-id", TBL,
         "--as", "user", "--json", f"@{os.path.basename(wl_tmp)}"],
        capture_output=True, text=True, cwd="/tmp", env=env, timeout=20,
    )
    stdout_clean = "\n".join(
        l for l in proc.stdout.splitlines() if not l.startswith("[lark-cli]")
    )
    if proc.returncode == 0 and '"ok": true' in stdout_clean:
        print(f"session-end-aggregator: worklog written → {title}", file=sys.stderr)
        try:
            os.remove(wl_tmp)
        except OSError:
            pass
    else:
        print(
            f"session-end-aggregator: lark-cli failed, kept in {out_path}. "
            f"rc={proc.returncode} stderr={proc.stderr[:200]}",
            file=sys.stderr,
        )
except Exception as e:
    print(f"session-end-aggregator: lark-cli exception {e}, kept in {out_path}", file=sys.stderr)
PY

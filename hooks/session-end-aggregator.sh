#!/usr/bin/env bash
# SessionEnd hook: 从 transcript 聚合 token + 事件 + 用户需求 → 写飞书 worklog
# 设计：自动写飞书，说明栏用结构化数据（commits/edits/prompts/notes/tokens），
#      不用 "auto-aggregated" 这种占位符。
# Agent 可在工作中往 /tmp/claude_session_<sid>_notes.md 追加 1 行总结。

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

python3 - "$TPATH" "$SID" "$CWD" "$REASON" "$OUT" "$NOTES" <<'PY'
import json, sys, os, datetime, re, subprocess

transcript, sid, cwd, reason, out_path, notes_path = sys.argv[1:7]

agg = {"input_tokens": 0, "output_tokens": 0,
       "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
model, models = None, set()
commits, edits, user_prompts, asst_msgs = [], [], [], 0


def extract_commit_msg(cmd):
    m = re.search(r"<<-?['\"]?EOF['\"]?\s*\n(.+?)\n\s*EOF", cmd, re.DOTALL)
    if m:
        return m.group(1).strip().split("\n")[0][:200]
    m = re.search(r'git commit[^|]*-m\s+["\']([^"\']+)["\']', cmd)
    if m:
        return m.group(1)[:200]
    return None


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
                                msg = extract_commit_msg(cmd)
                                if msg:
                                    commits.append(msg)
                        elif n in ("Write", "Edit", "MultiEdit"):
                            fp = inp.get("file_path", "")
                            if fp:
                                edits.append({"tool": n, "file": fp})
        elif t == "user":
            m = o.get("message", {})
            c = m.get("content", "")
            if isinstance(c, str) and c.strip():
                # 过滤系统消息（local-command-caveat, /command 等）
                if c.startswith("<") or "Caveat:" in c[:20]:
                    continue
                txt = c.strip().replace("\n", " ")
                user_prompts.append(txt[:120] + ("..." if len(txt) > 120 else ""))

# 去重 + 截断
edits = list({e["file"]: e for e in edits}.values())
commits = list(dict.fromkeys(commits))[:20]
user_prompts = user_prompts[:15]
total_user_msgs = len(user_prompts)

# 读 agent 写的 notes
agent_notes = ""
if os.path.exists(notes_path):
    with open(notes_path) as f:
        agent_notes = f.read().strip()

# 编辑按目录分组
edits_by_dir = {}
for e in edits:
    d = os.path.dirname(e["file"])
    edits_by_dir.setdefault(d, []).append(os.path.basename(e["file"]))

sid_short = sid[:8]


def clean_commit_msg(msg):
    m = re.sub(r"\s*Co-Authored-By:.*$", "", msg, flags=re.DOTALL).strip()
    return m[:60]


# === LLM 总结 ===（调 minimax M2.7 走 anthropic 协议，结构化 JSON 输出）
def llm_summarize():
    try:
        import urllib.request
        prompt_parts = []
        if commits:
            prompt_parts.append("commits:\n" + "\n".join(f"- {c[:100]}" for c in commits[:5]))
        if user_prompts:
            prompt_parts.append("\nuser_prompts:\n" + "\n".join(f"- {p[:200]}" for p in user_prompts[:5]))
        if edits:
            files = sorted({e['file'] for e in edits})[:10]
            prompt_parts.append("\nedited_files:\n" + "\n".join(f"- {f[:100]}" for f in files))
        if not prompt_parts:
            return None
        data = {
            "model": "MiniMax-M2.7",
            "max_tokens": 600,
            "system": ("你是 worklog 总结助手。给定用户诉求+commit+改动文件，"
                       "输出严格 JSON（无思考过程、无 markdown 包裹）："
                       "{\"title\": \"<≤20 字工作主题>\", "
                       "\"summary\": \"<2-3 句自然语言概述，做了什么、结果如何>\"}"),
            "messages": [{"role": "user", "content": "\n".join(prompt_parts)}],
        }
        req = urllib.request.Request(
            "https://api.minimaxi.com/anthropic/v1/messages",
            data=json.dumps(data).encode(),
            headers={
                "x-api-key": os.environ.get("ANTHROPIC_AUTH_TOKEN", ""),
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=12) as resp:
            result = json.loads(resp.read())
        text = ""
        for c in result.get("content", []):
            if c.get("type") == "text":
                text += c.get("text", "")
        m = re.search(r'\{[^{}]*"title"[^{}]*"summary"[^{}]*\}', text, re.DOTALL)
        if m:
            return json.loads(m.group(0))
    except Exception as e:
        print(f"llm_summarize failed: {e}", file=sys.stderr)
    return None


llm = llm_summarize()

# === 标题 ===（LLM 优先，fallback 到结构化推断）
if llm and llm.get("title"):
    title = llm["title"].replace("\n", " ").strip()[:60]
elif commits:
    title = clean_commit_msg(commits[0])[:60]
elif user_prompts:
    # 跳过 status-like 行（✅❌⚠ 占多）找第一条"问题/需求"行
    for p in user_prompts:
        if not re.search(r'[✅❌⚠]', p) and len(p.strip()) > 8:
            title = p.replace("\n", " ")[:40]
            break
    else:
        title = f"session 工作: {user_prompts[0].replace(chr(10), ' ')[:40]}"
else:
    title = f"session 工作: {sid_short} ({total_user_msgs} user msgs)"

# === 说明（自然语言段落，LLM 总结开头 + 元数据简化放最下面） ===
if llm and llm.get("summary"):
    body = llm["summary"].strip()
else:
    body = f"本次 session（{sid_short}）进行了 {asst_msgs} 轮对话。"

parts = [body]

if commits:
    commits_brief = "；".join(commits[:3])
    if len(commits) > 3:
        commits_brief += f"（+{len(commits)-3} more）"
    parts.append(f"主要动作：{commits_brief}。")

if edits_by_dir:
    top_dirs = sorted(edits_by_dir.keys())[:3]
    parts.append(f"改动 {len(edits)} 个文件，主要在：{' / '.join(top_dirs)}。")

# 剩余用户问题（agent 未通过 commits 回答的），跳过 status 输出
unanswered = []
for p in user_prompts[1:]:
    p_clean = p.replace("\n", " ").strip()
    if not p_clean:
        continue
    # 跳过纯 status 输出（✅❌⚠━ℹ 等占多 / 升级状态行）
    if re.search(r'[✅❌⚠━ℹ]{2,}', p_clean):
        continue
    if "Claude Code" in p_clean and ("版本" in p_clean or "升级" in p_clean):
        continue
    unanswered.append(p_clean[:100])
if unanswered:
    brief = "；".join(unanswered[:5])
    if len(brief) > 200:
        brief = brief[:200] + "…"
    parts.append("其余用户问题：" + brief + "。")

if agent_notes:
    parts.append(f"\n备注：\n{agent_notes}")

# 元数据简化放最下面（破折号分隔，参考手写工作日志风格）
parts.append(
    f"\n— token in {agg['input_tokens']:,} / out {agg['output_tokens']:,} / "
    f"cache_read {agg['cache_read_input_tokens']:,} / "
    f"cache_creation {agg['cache_creation_input_tokens']:,} / "
    f"{model or ''} / {asst_msgs} asst / {total_user_msgs} user"
)
description = "\n".join(parts)

quant = (f"{asst_msgs} asst / {total_user_msgs} user msgs, model={model}, "
         f"in={agg['input_tokens']:,} out={agg['output_tokens']:,}")

# === 来源映射 ===（reason → select option）
REASON_MAP = {
    "clear": "auto-clear",
    "new": "auto-new",
    "exit": "auto-exit",
    "prompt_input_exit": "auto-exit",
    "interrupt": "auto-ctrl_c",
    "ctrl_c": "auto-ctrl_c",
    "resume": "auto-resume",
}
source_val = REASON_MAP.get(reason, "auto-other" if reason else "auto-other")

# 写 /tmp
result = {
    "session_id": sid,
    "cwd": cwd,
    "reason": reason,
    "transcript_path": transcript,
    "ended_at": datetime.datetime.now().isoformat(),
    "tokens": agg,
    "model": model,
    "models_used": sorted(models),
    "stats": {"assistant_message_count": asst_msgs, "user_message_count": total_user_msgs},
    "events": {"git_commits": commits, "file_edits": edits},
    "user_prompts": user_prompts,
    "agent_notes": agent_notes,
    "description": description,
    "quant": quant,
}

tmp = out_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)
os.replace(tmp, out_path)
with open("/tmp/claude_last_session.json", "w") as f:
    json.dump(result, f, indent=2, ensure_ascii=False)

# 写飞书 worklog
T = "LX5lb6VfdaJHWrsRbTgc8Y50nmj"
TBL = "tblVsC0L7QFzMeYM"
KR_AUTO = "recvl7jffWBL34"

date_str = datetime.date.today().isoformat()

wl_payload = {
    "fields": ["标题", "关联KR", "成果类型", "量化结果", "说明", "日期",
               "input_tokens", "output_tokens",
               "cache_creation_input_tokens", "cache_read_input_tokens", "model",
               "asst_msgs", "user_msgs", "来源"],
    "rows": [[
        title, [{"id": KR_AUTO}], "工具开发", quant, description, date_str,
        agg["input_tokens"], agg["output_tokens"],
        agg["cache_creation_input_tokens"], agg["cache_read_input_tokens"],
        model or "",
        asst_msgs, total_user_msgs,
        source_val,
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

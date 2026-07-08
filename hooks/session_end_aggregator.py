#!/usr/bin/env python3
"""SessionEnd aggregator — parse Claude transcript, summarize via LLM, write to Feishu Base."""
import json, sys, os, datetime, re, subprocess


# ── transcript parsing ──────────────────────────────────────────────

def parse_transcript(path):
    """Read JSONL transcript → structured dict."""
    agg = {"input_tokens": 0, "output_tokens": 0,
           "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}
    model, models = None, set()
    commits, edits, user_prompts, asst_msgs = [], [], [], 0

    with open(path) as f:
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
                                    msg = _extract_commit_msg(cmd)
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
                    if c.startswith("<") or "Caveat:" in c[:20]:
                        continue
                    txt = c.strip().replace("\n", " ")
                    user_prompts.append(txt[:120] + ("..." if len(txt) > 120 else ""))

    edits = list({e["file"]: e for e in edits}.values())
    commits = list(dict.fromkeys(commits))[:20]
    user_prompts = user_prompts[:15]

    edits_by_dir = {}
    for e in edits:
        d = os.path.dirname(e["file"])
        edits_by_dir.setdefault(d, []).append(os.path.basename(e["file"]))

    return {
        "tokens": agg, "model": model, "models": sorted(models),
        "commits": commits, "edits": edits, "edits_by_dir": edits_by_dir,
        "user_prompts": user_prompts, "asst_msgs": asst_msgs,
        "total_user_msgs": len(user_prompts),
    }


def _extract_commit_msg(cmd):
    m = re.search(r"<<-?['\"]?EOF['\"]?\s*\n(.+?)\n\s*EOF", cmd, re.DOTALL)
    if m:
        return m.group(1).strip().split("\n")[0][:200]
    m = re.search(r'git commit[^|]*-m\s+["\']([^"\']+)["\']', cmd)
    if m:
        return m.group(1)[:200]
    return None


def is_empty_session(parsed):
    return (parsed["total_user_msgs"] == 0 and
            len(parsed["commits"]) == 0 and
            len(parsed["edits"]) == 0)


# ── LLM summarization ────────────────────────────────────────────────

def llm_summarize(commits, user_prompts, edits):
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
            "max_tokens": 600,
            "system": ("你是 worklog 总结助手。给定用户诉求+commit+改动文件，"
                       "输出严格 JSON（无思考过程、无 markdown 包裹）。\n"
                       "字段：\n"
                       "  title: ≤20 字工作主题\n"
                       "  type: 成果类型，必选下面一个：工具开发/技术方案/文档输出/学习笔记/问题排查/项目交付\n"
                       "  summary: 2-3 句自然语言概述\n"
                       "标题规则（强约束，违反复查再输出）：\n"
                       "  - 唯一合法格式：<项目前缀> <动词+对象>，如 claudecode 修复 hook 标题格式\n"
                       "  - 项目前缀从文件路径/commit 推断：cconfig claudecode project feishu minimax docs 等，小写英文\n"
                       "  - 禁止冒号：不写 claudecode: xxx 或 sfia 技能画像构建：xxx\n"
                       "  - 禁止下划线：不写 update_claude\n"
                       "  - 禁止括号：【】[]（）\n"
                       "  - 禁止标题以\"session 工作\"开头\n"
                       "成果类型选择规则：\n"
                       "  - 工具开发：写/改代码、脚本、hook、CLI 工具\n"
                       "  - 技术方案：架构设计、技术选型、方案对比\n"
                       "  - 文档输出：写文档、知识库、研究报告、画图\n"
                       "  - 学习笔记：探索新技术、阅读文档、动手实验\n"
                       "  - 问题排查：debug、故障修复、根因分析\n"
                       "  - 项目交付：完整功能上线、里程碑交付"),
            "messages": [{"role": "user", "content": "\n".join(prompt_parts)}],
        }
        base_url = os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com/v1")
        api_url = base_url.rstrip("/") + "/messages"
        req = urllib.request.Request(
            api_url,
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
        m = re.search(r'\{[^{}]*"title"[^{}]*"type"[^{}]*"summary"[^{}]*\}', text, re.DOTALL)
        if m:
            return json.loads(m.group(0))
        m = re.search(r'\{[^{}]*"title"[^{}]*"summary"[^{}]*\}', text, re.DOTALL)
        if m:
            return json.loads(m.group(0))
    except Exception as e:
        print(f"llm_summarize failed: {e}", file=sys.stderr)
    return None


# ── title / type / description ───────────────────────────────────────

KNOWN_PREFIXES = {"ccconfig", "claudecode", "project", "feishu", "minimax",
                  "sfia", "coze", "doubao", "trae", "robot", "docs", "agent"}
VALID_TYPES = {"工具开发", "技术方案", "文档输出", "学习笔记", "问题排查", "项目交付"}


def generate_title(llm, commits, user_prompts, sid_short):
    if llm and llm.get("title") and len(llm["title"].strip()) >= 6:
        return llm["title"].replace("\n", " ").strip()[:60]
    if commits:
        for c in commits:
            cleaned = _clean_commit_msg(c)
            if len(cleaned) >= 6 and not cleaned.startswith("session"):
                return cleaned[:60]
    if user_prompts:
        for p in user_prompts:
            p_clean = p.replace("\n", " ").strip()
            if not re.search(r'[✅❌⚠]', p_clean) and len(p_clean) > 8:
                prefix = _guess_prefix_from_prompts(user_prompts)
                title = p_clean[:40]
                if prefix and not title.lower().startswith(prefix.lower()):
                    title = prefix + " " + title
                return title[:60]
    if commits:
        return _clean_commit_msg(commits[0])[:60]
    return f"session 工作 ({sid_short} user msgs)"


def _guess_prefix_from_prompts(prompts):
    for p in prompts:
        p_lower = p.lower()
        for prefix in KNOWN_PREFIXES:
            if prefix.lower() in p_lower:
                return prefix
    return None


def postprocess_title(title, cwd):
    cwd_prefix = ""
    if cwd:
        parts = cwd.strip("/").split("/")
        for known in KNOWN_PREFIXES:
            if known in cwd.lower():
                cwd_prefix = known
                break
        if not cwd_prefix and len(parts) >= 3 and parts[1] == "git":
            cwd_prefix = parts[2].split("/")[0]

    title_has_prefix = any(
        title.lower().startswith(p.lower() + " ") for p in KNOWN_PREFIXES
    )
    if not title_has_prefix and cwd_prefix and not title.startswith("session 工作"):
        title = cwd_prefix + " " + title

    title = re.sub(r'\s*[：:]\s*', ' ', title)
    title = re.sub(r'_+', ' ', title)
    title = re.sub(r'[【】\[\]]', '', title)
    return title.strip()[:60]


def _clean_commit_msg(msg):
    m = re.sub(r"\s*Co-Authored-By:.*$", "", msg, flags=re.DOTALL).strip()
    return m[:60]


def determine_work_type(llm, commits, edits):
    if llm and llm.get("type") and llm["type"] in VALID_TYPES:
        return llm["type"]
    if commits:
        return "工具开发"
    if edits:
        return "文档输出"
    return "学习笔记"


def assemble_description(llm, commits, edits_by_dir, user_prompts, agent_notes,
                         source_val, date_str, sid_short, asst_msgs):
    if llm and llm.get("summary"):
        body = llm["summary"].strip()
    else:
        body = f"本次 session（{sid_short}）进行了 {asst_msgs} 轮对话。"

    parts = [body]

    if commits:
        brief = "；".join(commits[:3])
        if len(commits) > 3:
            brief += f"（+{len(commits)-3} more）"
        parts.append(f"主要动作：{brief}。")

    if edits_by_dir:
        top_dirs = sorted(edits_by_dir.keys())[:3]
        parts.append(f"改动 {sum(len(v) for v in edits_by_dir.values())} 个文件，主要在：{' / '.join(top_dirs)}。")

    unanswered = []
    for p in user_prompts[1:]:
        p_clean = p.replace("\n", " ").strip()
        if not p_clean:
            continue
        if re.search(r'[✅❌⚠━ℹ▌▎]', p_clean):
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

    return "\n".join(parts)


REASON_MAP = {
    "clear": "auto-clear", "new": "auto-new", "exit": "auto-exit",
    "prompt_input_exit": "auto-exit", "interrupt": "auto-ctrl_c",
    "ctrl_c": "auto-ctrl_c", "resume": "auto-resume",
}


def get_source_val(reason):
    return REASON_MAP.get(reason, "auto-other" if reason else "auto-other")


# ── Feishu Base sync ─────────────────────────────────────────────────

def _call_lark_cli(args, env, cwd="/tmp", timeout=20):
    """Run lark-cli, return (ok: bool, parsed_json | None)."""
    try:
        proc = subprocess.run(
            args, capture_output=True, text=True, cwd=cwd, env=env, timeout=timeout,
        )
    except Exception as e:
        print(f"session-end-aggregator: lark-cli exception {e}", file=sys.stderr)
        return False, None

    stdout_clean = "\n".join(
        l for l in proc.stdout.splitlines() if not l.startswith("[lark-cli]")
    )
    if proc.returncode != 0 or '"ok": true' not in stdout_clean:
        print(f"session-end-aggregator: lark-cli failed rc={proc.returncode}", file=sys.stderr)
        return False, None

    try:
        return True, json.loads(stdout_clean)
    except json.JSONDecodeError:
        return True, None


def _read_conf(ccconfig_home):
    conf_path = os.path.join(ccconfig_home, "conf/f-logme.json")
    try:
        with open(conf_path) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        print("[session-end] f-logme.json 不可用，跳过 Base 写入", file=sys.stderr)
        return None


def _get_kr_id(conf, cwd):
    kr_route = conf.get("kr_route", {})
    home = os.path.expanduser("~")
    kr_map = {os.path.join(home, "git", k): v for k, v in kr_route.items() if k != "_default"}
    for prefix, kid in kr_map.items():
        if cwd and cwd.startswith(prefix) and kid:
            return kid
    return kr_route.get("_default", "")


def _build_lark_env():
    env = os.environ.copy()
    acct_marker = os.path.expanduser("~/.lark-cli-account")
    acct_dir = os.path.expanduser("~/.lark-cli-ailab")
    if os.path.exists(acct_marker):
        with open(acct_marker) as f:
            for line in f:
                if line.startswith("configDir="):
                    acct_dir = line.strip().split("=", 1)[1]
                    break
    env["LARKSUITE_CLI_CONFIG_DIR"] = acct_dir
    env["PATH"] = os.path.expanduser("~/.local/bin:") + env.get("PATH", "")
    return env


def _write_wl_cache(cache_path, data):
    with open(cache_path, "w") as f:
        json.dump(data, f, ensure_ascii=False)


def _read_wl_cache(cache_path):
    if os.path.exists(cache_path):
        with open(cache_path) as f:
            return json.load(f)
    return None


def sync_to_feishu(parsed, title, work_type, description, sid, cwd,
                   source_val, date_str, agent_notes):
    home = os.path.expanduser("~")
    ccconfig_home = os.environ.get("CCCONFIG_HOME", os.path.join(home, "git/ccconfig"))
    conf = _read_conf(ccconfig_home)
    if conf is None:
        return

    feme = conf["bases"]["okr_v2"]
    base_token = feme["token"]
    table_id = feme["tables"]["Worklog"]
    kr_id = _get_kr_id(conf, cwd)
    env = _build_lark_env()
    wl_cache_path = f"/tmp/claude_session_{sid}_wl.json"

    agg = parsed["tokens"]
    asst_msgs = parsed["asst_msgs"]
    total_user_msgs = parsed["total_user_msgs"]
    prev = _read_wl_cache(wl_cache_path)

    if prev is not None:
        # ── merge existing record ──
        merged_title = title if len(title) > len(prev.get("title", "")) else prev["title"]
        merged_desc = prev.get("description", "") + f"\n\n---\n{source_val} 更新 ({date_str}):\n{description}"

        payload = {
            "record_id_list": [prev["record_id"]],
            "patch": {
                "标题": merged_title,
                "说明": merged_desc,
                "input_tokens": agg["input_tokens"] + prev.get("input_tokens", 0),
                "output_tokens": agg["output_tokens"] + prev.get("output_tokens", 0),
                "asst_msgs": asst_msgs + prev.get("asst_msgs", 0),
                "user_msgs": total_user_msgs + prev.get("user_msgs", 0),
                "来源": source_val,
                "成果类型": work_type,
            },
        }
        tmp_path = f"/tmp/wl_update_{sid}.json"
        with open(tmp_path, "w") as f:
            json.dump(payload, f, ensure_ascii=False)

        ok, _ = _call_lark_cli(
            ["lark-cli", "base", "+record-batch-update",
             "--base-token", base_token, "--table-id", table_id,
             "--as", "user", "--json", f"@{os.path.basename(tmp_path)}"],
            env,
        )
        try:
            os.remove(tmp_path)
        except OSError:
            pass

        if ok:
            _write_wl_cache(wl_cache_path, {
                "record_id": prev["record_id"],
                "title": merged_title,
                "work_type": work_type,
                "description": merged_desc,
                "asst_msgs": asst_msgs + prev.get("asst_msgs", 0),
                "user_msgs": total_user_msgs + prev.get("user_msgs", 0),
                "input_tokens": agg["input_tokens"] + prev.get("input_tokens", 0),
                "output_tokens": agg["output_tokens"] + prev.get("output_tokens", 0),
            })
            print(f"session-end-aggregator: worklog merged → {merged_title}", file=sys.stderr)
    else:
        # ── create new record ──
        payload = {
            "fields": ["标题", "成果类型", "说明", "日期",
                       "input_tokens", "output_tokens", "model",
                       "asst_msgs", "user_msgs", "关联KR", "来源"],
            "rows": [[
                title, work_type, description, date_str,
                agg["input_tokens"], agg["output_tokens"],
                parsed["model"] or "",
                asst_msgs, total_user_msgs,
                [{"id": kr_id}],
                source_val,
            ]],
        }
        tmp_path = f"/tmp/wl_{sid}.json"
        with open(tmp_path, "w") as f:
            json.dump(payload, f, ensure_ascii=False)

        ok, rdata = _call_lark_cli(
            ["lark-cli", "base", "+record-batch-create",
             "--base-token", base_token, "--table-id", table_id,
             "--as", "user", "--json", f"@{os.path.basename(tmp_path)}"],
            env,
        )
        try:
            os.remove(tmp_path)
        except OSError:
            pass

        if ok and rdata:
            try:
                wl_id = rdata["data"]["record_id_list"][0]
                _write_wl_cache(wl_cache_path, {
                    "record_id": wl_id, "title": title, "work_type": work_type,
                    "description": description, "asst_msgs": asst_msgs,
                    "user_msgs": total_user_msgs,
                    "input_tokens": agg["input_tokens"],
                    "output_tokens": agg["output_tokens"],
                })
                print(f"session-end-aggregator: worklog created → {title} ({wl_id})", file=sys.stderr)
            except Exception as e:
                print(f"session-end-aggregator: created but cache failed {e}", file=sys.stderr)


# ── main ─────────────────────────────────────────────────────────────

def aggregate(transcript, sid, cwd, reason, notes_path):
    parsed = parse_transcript(transcript)

    if is_empty_session(parsed):
        print(f"session-end-aggregator: empty session {sid[:8]}, skip", file=sys.stderr)
        return

    agent_notes = ""
    if os.path.exists(notes_path):
        with open(notes_path) as f:
            agent_notes = f.read().strip()

    llm = llm_summarize(parsed["commits"], parsed["user_prompts"], parsed["edits"])

    title = generate_title(llm, parsed["commits"], parsed["user_prompts"], sid[:8])
    title = postprocess_title(title, cwd)

    work_type = determine_work_type(llm, parsed["commits"], parsed["edits"])
    source_val = get_source_val(reason)
    date_str = datetime.date.today().isoformat()

    description = assemble_description(
        llm, parsed["commits"], parsed["edits_by_dir"], parsed["user_prompts"],
        agent_notes, source_val, date_str, sid[:8], parsed["asst_msgs"],
    )

    sync_to_feishu(parsed, title, work_type, description, sid, cwd,
                   source_val, date_str, agent_notes)


def main():
    if len(sys.argv) < 7:
        print(f"Usage: {sys.argv[0]} <transcript> <sid> <cwd> <reason> <out> <notes>", file=sys.stderr)
        sys.exit(1)
    transcript, sid, cwd, reason, _out_path, notes_path = sys.argv[1:7]
    aggregate(transcript, sid, cwd, reason, notes_path)


if __name__ == '__main__':
    main()

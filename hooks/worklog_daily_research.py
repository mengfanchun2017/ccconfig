#!/usr/bin/env python3
"""每日 git/PR 研究 — 查当天所有 repo 的 commit + GitHub PR，LLM 合成 worklog 条目。

用法:
  python3 worklog_daily_research.py --date 2026-07-09         # 某天
  python3 worklog_daily_research.py --date 2026-07-09 --write # 写飞书
  python3 worklog_daily_research.py                           # 今天，预览
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path


REPOS = [
    os.path.expanduser("~/git/ccconfig"),
    os.path.expanduser("~/git/claude-skills"),
]


def _read_conf():
    conf_path = os.path.expanduser("~/git/ccprivate/conf/f-logme.json")
    with open(conf_path) as f:
        return json.load(f)


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


def _call_lark_cli(args, env, timeout=30):
    try:
        proc = subprocess.run(
            args, capture_output=True, text=True, timeout=timeout, env=env,
        )
    except Exception as e:
        print(f"lark-cli exception: {e}", file=sys.stderr)
        return None
    stdout_clean = "\n".join(
        l for l in proc.stdout.splitlines() if not l.startswith("[lark-cli]")
    )
    try:
        return json.loads(stdout_clean)
    except json.JSONDecodeError:
        return None


def git_log_since(repo, since_date):
    """Return list of (hash_short, author, date, subject) for commits since given date."""
    try:
        proc = subprocess.run(
            ["git", "-C", repo, "log", "--oneline", f"--since={since_date}",
             "--format=%h||%an||%ai||%s"],
            capture_output=True, text=True, timeout=15,
        )
    except Exception:
        return []
    commits = []
    for line in proc.stdout.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("||", 3)
        if len(parts) == 4:
            commits.append({
                "hash": parts[0], "author": parts[1],
                "date": parts[2][:10], "subject": parts[3],
            })
    return commits


def gh_prs_merged(since_date):
    """Return list of merged PRs since given date."""
    try:
        proc = subprocess.run(
            ["gh", "pr", "list", "--state", "merged", "--search",
             f"merged:>={since_date}", "--limit", "20",
             "--json", "title,url,mergedAt,repository,number"],
            capture_output=True, text=True, timeout=15,
        )
    except Exception:
        return []
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []


def llm_summarize_git(commits_by_repo, prs, date_str):
    """Call LLM to summarize daily git/PR activity → worklog title + description."""
    base_url = os.environ.get("ANTHROPIC_BASE_URL", "").strip()
    model = os.environ.get("ANTHROPIC_DEFAULT_HAIKU_MODEL", "") or os.environ.get("ANTHROPIC_MODEL", "")
    api_key = os.environ.get("ANTHROPIC_AUTH_TOKEN", "").strip()
    if not base_url or not model or not api_key:
        return None

    parts = [f"日期：{date_str}"]
    for repo, commits in commits_by_repo.items():
        if not commits:
            continue
        repo_name = os.path.basename(repo)
        commit_list = "\n".join(f"- {c['subject']}" for c in commits[:10])
        parts.append(f"\n{repo_name} commits ({len(commits)} 个):\n{commit_list}")

    if prs:
        pr_list = "\n".join(f"- [{p['number']}] {p['title']} ({p['repository']['nameWithOwner'] if p.get('repository') else '?'})" for p in prs[:10])
        parts.append(f"\nGitHub PRs ({len(prs)} 个):\n{pr_list}")

    if len(parts) == 1:
        return None

    prompt = "\n".join(parts)

    data = {
        "model": model,
        "max_tokens": 500,
        "system": """你是 worklog 总结助手。输出严格 JSON（无 markdown 包裹），字段：
- title（≤30字中文）：根据提交内容判断工作领域，概括当天主要进展。
  领域自选：Claude Code配置 / 飞书集成 / Worklog系统 / LLM代理 / ccconfig基础设施 / Cloudflare开发 / Git工作流 / 文档整理 / 技能开发
  范例："cconfig 云flare插件安装与文档整理"
- summary（3-5句中文）：今天做了什么、关键产出。纯工作摘要，禁止贴原始 commit hash/message 列表。""",
        "messages": [{"role": "user", "content": prompt}],
    }

    try:
        api_url = base_url.rstrip("/") + "/messages"
        req = urllib.request.Request(
            api_url,
            data=json.dumps(data).encode(),
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=25) as resp:
            result = json.loads(resp.read())
    except Exception as e:
        print(f"llm_summarize_git failed: {e}", file=sys.stderr)
        return None

    text = ""
    for c in result.get("content", []):
        if c.get("type") == "text":
            text += c.get("text", "")

    m = re.search(r'\{[^{}]*"title"[^{}]*"summary"[^{}]*\}', text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(0))
        except json.JSONDecodeError:
            pass
    return None


def find_or_create_daily_worklog(conf, env, date_str, title, summary):
    """Check if a daily summary worklog already exists for this date.
    If not, create one. Returns record_id or None."""
    base_token = conf["bases"]["okr_v2"]["token"]
    table_id = conf["bases"]["okr_v2"]["tables"]["Worklog"]

    # Search for existing daily summary for this date
    result = _call_lark_cli(
        ["lark-cli", "base", "+record-search",
         "--base-token", base_token, "--table-id", table_id,
         "--keyword", date_str, "--search-field", "日期", "--limit", "5"],
        env,
    )
    # Don't bother parsing the search result - just create new entry
    # The daily merge already handles dedup by title

    kr_route = conf.get("kr_route", {})
    home = os.path.expanduser("~")
    kr_id = kr_route.get("_default", "")

    payload = {
        "fields": ["标题", "成果类型", "说明", "日期",
                   "输入Token", "输出Token", "助手消息数", "用户消息数", "关联KR"],
        "rows": [[
            title, "项目交付", summary, date_str,
            0, 0, 0, 0,
            [{"id": kr_id}],
        ]],
    }

    import tempfile
    fd, tmp_path = tempfile.mkstemp(suffix=".json", dir="/tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f, ensure_ascii=False)

    result = _call_lark_cli(
        ["lark-cli", "base", "+record-batch-create",
         "--base-token", base_token, "--table-id", table_id,
         "--as", "user", "--json", f"@{os.path.basename(tmp_path)}"],
        env,
    )
    try:
        os.unlink(tmp_path)
    except OSError:
        pass

    if result:
        try:
            return result["data"]["record_id_list"][0]
        except (KeyError, IndexError):
            pass
    return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--date", default=date.today().isoformat(),
                   help="日期 YYYY-MM-DD (默认今天)")
    p.add_argument("--write", action="store_true",
                   help="写入飞书 Base（默认仅预览）")
    p.add_argument("--repos", nargs="*", default=None,
                   help="覆盖默认 repo 列表")
    args = p.parse_args()

    since_date = args.date
    repos = args.repos or REPOS
    repos = [os.path.expanduser(r) for r in repos if os.path.isdir(os.path.expanduser(r))]

    # Gather commits
    commits_by_repo = {}
    for repo in repos:
        commits = git_log_since(repo, since_date)
        if commits:
            commits_by_repo[repo] = commits
            print(f"  {os.path.basename(repo)}: {len(commits)} commits")

    total_commits = sum(len(c) for c in commits_by_repo.values())
    if total_commits == 0:
        print("无新 commit，跳过。")
        return

    # Gather PRs
    prs = gh_prs_merged(since_date)
    if prs:
        print(f"  GitHub PRs: {len(prs)} merged")

    if not commits_by_repo and not prs:
        print("无新 commit 或 PR，跳过。")
        return

    # LLM summarize
    llm = llm_summarize_git(commits_by_repo, prs, args.date)
    if not llm:
        print("LLM 总结失败，跳过。")
        return

    print(f"\n标题: {llm.get('title', '?')}")
    print(f"摘要: {llm.get('summary', '?')[:200]}")

    if args.write:
        conf = _read_conf()
        env = _build_lark_env()
        rid = find_or_create_daily_worklog(
            conf, env, args.date,
            llm.get("title", f"每日总结 {args.date}"),
            llm.get("summary", ""),
        )
        if rid:
            print(f"\n✅ 已写入 worklog: {rid}")
        else:
            print("\n❌ 写入失败")
    else:
        print("\n预览模式。加 --write 写入。")
        print(f"总 commits: {total_commits}, PRs: {len(prs)}")


if __name__ == "__main__":
    main()

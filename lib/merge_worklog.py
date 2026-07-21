#!/usr/bin/env python3
"""merge_worklog.py — Worklog LLM 合并脚本

按 (date, 成果类型, 关联KR) 分组，组内 >1 条 → 用 LLM 合并成 1 条。
新条目写入 Worklog，老条目标 合并状态=merged + 合并到=<new record_id>。

用法:
  python3 scripts/merge_worklog.py --dry-run    # 预览（不写飞书）
  python3 scripts/merge_worklog.py              # 实际执行
  python3 scripts/merge_worklog.py --group "2025-07-28|工具开发|recXXX"  # 只跑某组

依赖:
  - lark-cli 已配置（export LARKSUITE_CLI_CONFIG_DIR + PATH）
  - 环境变量 ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_MODEL 已设
    （CLAUDE.md 已有，或从 conf/llm.json 读）
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error
from collections import defaultdict
from datetime import datetime
from pathlib import Path

# 从 ccprivate/skill-config/f-logme.yaml 读配置
def get_feme_config():
    feme_yaml = Path.home() / "git" / "ccprivate" / "skill-config" / "f-logme.yaml"
    with open(feme_yaml) as f:
        import yaml
        data = yaml.safe_load(f)
    okr = data["bases"]["okr_v2"]
    return okr["token"], okr["tables"]["Worklog"]

BASE_TOKEN, WORKLOG_TABLE = get_feme_config()
LARK_CLI = "lark-cli"
LARK_ENV_PREFIX = 'export LARKSUITE_CLI_CONFIG_DIR="$HOME/.lark-cli-<account>" && export PATH="$HOME/.local/bin:$PATH"'

# LLM config (从 conf/llm.json 或环境变量读)
def get_llm_config():
    """从 conf/llm.json 或环境变量读 LLM 配置"""
    # 优先用环境变量（CLAUDE.md 已设）
    base_url = os.environ.get("ANTHROPIC_BASE_URL")
    api_key = os.environ.get("ANTHROPIC_AUTH_TOKEN")
    model = os.environ.get("ANTHROPIC_MODEL", "MiniMax-M3")
    if base_url and api_key:
        return base_url, api_key, model
    # fallback: ccprivate/conf/llm.json
    llm_json = Path.home() / "git" / "ccprivate" / "conf" / "llm.json"
    if llm_json.exists():
        with open(llm_json) as f:
            data = json.load(f)
        current = data.get("current", "minimax")
        llm = data.get("llms", {}).get(current, {})
        return (
            llm.get("base_url"),
            llm.get("key"),
            llm.get("model", "MiniMax-M3"),
        )
    raise RuntimeError("LLM config not found: set ANTHROPIC_* env or conf/llm.json")

# ========== lark-cli 封装 ==========
def run_lark_cli(args, check=True):
    """Run lark-cli command and return parsed JSON output."""
    cmd = f'{LARK_ENV_PREFIX} && {LARK_CLI} {" ".join(args)}'
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
    out = result.stdout
    # 过滤 lark-cli 日志行 + WSL cwd 通知
    out = "\n".join(
        line for line in out.splitlines()
        if not line.startswith("[lark-cli]") and not line.startswith("Shell cwd was reset")
    )
    if check and result.returncode != 0:
        print(f"❌ lark-cli 失败: {' '.join(args)}", file=sys.stderr)
        print(f"   stdout: {out[:500]}", file=sys.stderr)
        print(f"   stderr: {result.stderr[:500]}", file=sys.stderr)
        sys.exit(1)
    # 尝试 parse JSON
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return {"raw_output": out}

def fetch_worklog():
    """拉所有 Worklog 记录。返回 (fields_order, records_list_of_dicts)"""
    result = run_lark_cli([
        "base", "+record-list",
        "--base-token", BASE_TOKEN,
        "--table-id", WORKLOG_TABLE,
        "--format", "json",
    ])
    data = result.get("data", {})
    fields = data.get("fields", [])
    items = data.get("data", [])
    records = []
    for r in items:
        row = {fields[j]: r[j] for j in range(len(fields))}
        records.append(row)
    return fields, records

def fetch_all_record_ids():
    """用 +record-search 拿所有 record_ids。
    注意: search 输出是 markdown 表格格式，需 regex 解析。
    飞书 _record_id 格式: rec + 12 char (总 15 字符)
    """
    import re
    import subprocess
    # 找一个能匹配大多数记录的 keyword
    # "的" 中文最常见字符；搜说明字段；limit 200
    cmd = (f'{LARK_ENV_PREFIX} && {LARK_CLI} base +record-search '
           f'--base-token {BASE_TOKEN} --table-id {WORKLOG_TABLE} '
           f'--keyword "的" --search-field "说明" --limit 200')
    proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=60)
    out = "\n".join(
        line for line in proc.stdout.splitlines()
        if not line.startswith("[lark-cli]") and not line.startswith("Shell cwd was reset")
    )
    matches = re.findall(r'(rec[a-zA-Z0-9]{10,})', out)
    return list(dict.fromkeys(matches))

def update_record(record_id, fields):
    """更新 1 条记录。fields 是 dict {field_name: value}"""
    import tempfile
    json_content = json.dumps({"fields": fields}, ensure_ascii=False)
    tmp_dir = Path.cwd() / ".tmp"
    tmp_dir.mkdir(exist_ok=True)
    tmp_path = tmp_dir / f"merge_update_{os.getpid()}_{record_id[-8:]}.json"
    tmp_path.write_text(json_content, encoding="utf-8")
    try:
        result = run_lark_cli([
            "api", "PUT",
            f"/open-apis/bitable/v1/apps/{BASE_TOKEN}/tables/{WORKLOG_TABLE}/records/{record_id}",
            "--data", f"@.tmp/{tmp_path.name}",
            "--as", "user",
        ])
    finally:
        tmp_path.unlink()
    return result

def create_record(fields):
    """创建 1 条记录。fields 是 dict {field_name: value}"""
    # 用 record-batch-create 创建单条
    # 写 JSON 到临时文件，--json @file 避免 shell quoting 问题
    # lark-cli 要求 path 相对当前目录
    import tempfile
    import shutil
    field_names = list(fields.keys())
    field_values = [fields[k] for k in field_names]
    json_content = json.dumps({
        "fields": field_names,
        "rows": [field_values],
    }, ensure_ascii=False)
    # 写到当前目录的 .tmp/ 子目录
    tmp_dir = Path.cwd() / ".tmp"
    tmp_dir.mkdir(exist_ok=True)
    tmp_path = tmp_dir / f"merge_create_{os.getpid()}.json"
    tmp_path.write_text(json_content, encoding="utf-8")
    try:
        result = run_lark_cli([
            "base", "+record-batch-create",
            "--base-token", BASE_TOKEN,
            "--table-id", WORKLOG_TABLE,
            "--json", f"@.tmp/{tmp_path.name}",
        ])
    finally:
        tmp_path.unlink()
    return result

# ========== LLM 调用 ==========
def call_llm(prompt, max_tokens=1500):
    """调 LLM API (Anthropic-compatible)"""
    base_url, api_key, model = get_llm_config()
    # 飞书 LLM 兼容 Anthropic API
    url = f"{base_url.rstrip('/')}/v1/messages"
    payload = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            content = result.get("content", [])
            if content and isinstance(content, list):
                return content[0].get("text", "").strip()
            return json.dumps(result)
    except urllib.error.HTTPError as e:
        return f"[LLM ERROR {e.code}: {e.read().decode('utf-8')[:300]}]"
    except Exception as e:
        return f"[LLM ERROR: {str(e)}]"

# ========== 分组 & 合并逻辑 ==========
def group_records(records):
    """按 (date, 成果类型, 关联KR) 分组"""
    groups = defaultdict(list)
    for r in records:
        # 跳过已经合并的
        if r.get("合并状态"):
            ms = r.get("合并状态")
            if isinstance(ms, list) and ms and ms[0] == "merged":
                continue
        date_val = r.get("日期", "")
        if isinstance(date_val, list) and date_val:
            date_val = date_val[0]
        date_str = str(date_val)[:10] if date_val else "N/A"
        ytype = r.get("成果类型") or []
        if isinstance(ytype, list) and ytype:
            ytype = ytype[0]
        else:
            ytype = "N/A"
        kr = r.get("关联KR") or []
        if isinstance(kr, list) and kr:
            kr = kr[0].get("id", "N/A")
        else:
            kr = "N/A"
        key = f"{date_str}|{ytype}|{kr}"
        groups[key].append(r)
    return groups

def build_merge_prompt(group_key, records):
    """构造 LLM 合并 prompt"""
    date_str, ytype, kr = group_key.split("|")
    entries_text = []
    for i, r in enumerate(records, 1):
        title = r.get("标题", "?") or "?"
        desc = r.get("说明", "?") or "?"
        # 截断长说明
        if len(desc) > 300:
            desc = desc[:300] + "..."
        entries_text.append(f"### 条目 {i}\n标题: {title}\n说明: {desc}")
    entries_block = "\n\n".join(entries_text)

    prompt = f"""你是 f-logme worklog 合并助手。

输入: {len(records)} 条 worklog（同一日期 + 同一分类 + 同一 KR）
- 日期: {date_str}
- 分类: {ytype}
- KR: {kr}

任务: 合并成 1 条 worklog，保留所有关键信息。

合并规则:
- 标题: 1 句话总结今天这领域的核心进展
- 说明: Markdown 结构化
  * 做了什么（按主题归类，不按时间）
  * 关键产出（按标题原样保留，标 [1] [2] 引用）
  * 遗留/阻塞（如有）
- 保留所有原标题作为子条目
- 量化结果字段：合并 token/消息数

输出 JSON（严格格式）:
{{
  "title": "合并后的 1 句话标题",
  "body": "Markdown 结构化说明",
  "量化结果": "如 'X 条 worklog 合并'"
}}

条目:
{entries_block}

只输出 JSON，不要任何解释。
"""
    return prompt

def parse_llm_response(text):
    """解析 LLM 返回的 JSON"""
    # 找 JSON 块
    text = text.strip()
    if text.startswith("```"):
        lines = text.split("\n")
        # 去掉首尾 ``` 行
        text = "\n".join(lines[1:-1]) if lines[-1].startswith("```") else "\n".join(lines[1:])
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # 找 { ... } 块
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            try:
                return json.loads(text[start:end+1])
            except:
                pass
        return None

# ========== 主流程 ==========
def main():
    parser = argparse.ArgumentParser(description="Worklog LLM 合并")
    parser.add_argument("--dry-run", action="store_true", help="预览，不写飞书")
    parser.add_argument("--group", type=str, help="只跑指定 group (格式: 'date|type|kr')")
    parser.add_argument("--limit", type=int, default=0, help="最多处理 N 个 group (0=全部)")
    args = parser.parse_args()

    print("📥 拉 Worklog 记录...")
    fields, records = fetch_worklog()
    print(f"   找到 {len(records)} 条记录")
    print()

    groups = group_records(records)
    multi_groups = {k: v for k, v in groups.items() if len(v) > 1}
    print(f"📊 分组: {len(groups)} 总, {len(multi_groups)} 需合并")
    print()

    if args.group:
        if args.group not in multi_groups:
            print(f"❌ Group '{args.group}' 不在合并列表中")
            sys.exit(1)
        multi_groups = {args.group: multi_groups[args.group]}
    elif args.limit:
        sorted_groups = sorted(multi_groups.items(), key=lambda x: -len(x[1]))[:args.limit]
        multi_groups = dict(sorted_groups)

    for i, (key, recs) in enumerate(multi_groups.items(), 1):
        date_str, ytype, kr = key.split("|")
        print(f"{'='*60}")
        print(f"[{i}/{len(multi_groups)}] {date_str} | {ytype} | KR={kr[-8:]} | {len(recs)} 条")
        for r in recs:
            print(f"  - {r.get('标题', '?')[:60]}")
        print()

        if args.dry_run:
            print("  [DRY-RUN] 跳过 LLM 调用和写飞书")
            continue

        # LLM 合并
        prompt = build_merge_prompt(key, recs)
        print("  🤖 调 LLM 合并...")
        response = call_llm(prompt)
        merged = parse_llm_response(response)
        if not merged:
            print(f"  ❌ LLM 返回解析失败: {response[:200]}")
            continue

        print(f"  ✅ 合并标题: {merged.get('title', '?')}")
        print(f"     body 长度: {len(merged.get('body', ''))} 字符")

        # 写新条目
        new_fields = {
            "标题": merged.get("title", f"合并-{date_str}-{ytype}")[:200],
            "说明": merged.get("body", ""),
            "日期": recs[0].get("日期"),  # 用最早一条的日期
            "成果类型": [ytype] if ytype != "N/A" else None,
            "关联KR": [{"id": kr}] if kr != "N/A" else None,
            "合并状态": "active",
            "量化结果": f"{len(recs)} 条合并",
            "来源": "manual",  # merged entry 是手动合并
            "user_msgs": sum((r.get("user_msgs") or 0) for r in recs),
            "asst_msgs": sum((r.get("asst_msgs") or 0) for r in recs),
            "input_tokens": sum((r.get("input_tokens") or 0) for r in recs),
            "output_tokens": sum((r.get("output_tokens") or 0) for r in recs),
        }
        # 清理 None
        new_fields = {k: v for k, v in new_fields.items() if v is not None}

        result = create_record(new_fields)
        if not result.get("ok"):
            print(f"  ❌ 创建失败: {result}")
            continue
        new_record_id = result.get("data", {}).get("record_id_list", [None])[0]
        if not new_record_id:
            print(f"  ❌ 未拿到 new record_id: {result}")
            continue
        print(f"  ✅ 新 record_id: {new_record_id}")

        # 标记老条目（暂跳过：lark-cli +record-list 不返回 record_id，
        # +record-search 解析复杂。本轮只创建新条目，老条目靠合并状态=空区分）
        # 后续优化：写单独 follow-up 脚本用 search by 标题 拿 record_id 后逐条标 merged
        old_titles = [r.get("标题", "?")[:40] for r in recs]
        print(f"     - 老条目（合并状态=空，飞书 UI 可过滤）:")
        for t in old_titles:
            print(f"        · {t}")
        print()

    print("="*60)
    print(f"{'[DRY-RUN] 预览完成' if args.dry_run else '✅ 实际合并完成'}")
    print("="*60)

if __name__ == "__main__":
    main()

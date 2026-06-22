#!/usr/bin/env python3
"""
Worklog 整合脚本 — 定期扫描重复/低质量记录，输出合并/删除候选。

模式:
  merge   — 完全同标题自动合并 + 高度相似(>85%)候选清单（每周执行）
  weekly  — 删空记录 + 同日期相似标题候选（每周辅助）
  monthly — 全量扫描：低质量标题 + 跨日期同主题 + 无效 KR 关联
  dry-run — 仅统计输出

合并规则（merge 模式）:
  1. 完全同标题 → 保留说明最长记录，合并其余说明，删除重复
  2. 标题相似 > 85% 且同日期 → 候选合并（人工确认）
  3. 标题相似 > 85% 跨日期 → 递进更新类自动合并，其他候选

用法:
  python3 worklog_consolidate.py --mode merge       # 预览去重
  python3 worklog_consolidate.py --mode merge --write  # 执行合并
  python3 worklog_consolidate.py --mode weekly      # 每周清理
  python3 worklog_consolidate.py --mode dry-run     # 统计总览

依赖: conf/f-logme.json 中的 Base token/表 ID
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import date, timedelta
from difflib import SequenceMatcher
from pathlib import Path


def _find_conf():
    for anchor in [Path(__file__).resolve().parent.parent.parent.parent,
                   Path.home() / "git" / "ccconfig"]:
        candidate = anchor / "conf" / "f-logme.json"
        if candidate.exists():
            return candidate
    sys.exit("conf/f-logme.json not found")


CONF = json.loads(_find_conf().read_text())
BASE = CONF["bases"]["okr_v2"]["token"]
TBL = CONF["bases"]["okr_v2"]["tables"]["Worklog"]
ENV = {
    **os.environ,
    "LARKSUITE_CLI_CONFIG_DIR": os.path.expanduser(CONF["lark_cli"]["config_dir"]),
    "PATH": os.path.expanduser("~/.local/bin") + ":" + os.environ.get("PATH", ""),
    "HOME": os.environ.get("HOME", os.path.expanduser("~")),
}


def lark(*args):
    r = subprocess.run(["lark-cli", *args], capture_output=True, text=True, env=ENV)
    lines = [l for l in r.stdout.splitlines()
             if not l.startswith("[lark-cli]") and "Shell cwd" not in l]
    return json.loads("\n".join(lines))


def fetch_all_worklogs():
    """分页拉取全部 worklog 记录"""
    records = []
    offset = 0
    while True:
        data = lark("base", "+record-list", "--base-token", BASE,
                    "--table-id", TBL, "--format", "json",
                    "--limit", "200", "--offset", str(offset))
        chunk = data["data"]["data"]
        if not chunk:
            break
        fields = data["data"]["fields"]
        rec_ids = data["data"]["record_id_list"]
        for i, row in enumerate(chunk):
            d = dict(zip(fields, row))
            rid = rec_ids[i] if i < len(rec_ids) else "?"
            d["_record_id"] = rid
            d["_rid"] = rid
            records.append(d)
        has_more = data["data"].get("has_more", False)
        if not has_more:
            break
        offset += len(chunk)
    return records


def title_similarity(a, b):
    """标题相似度 (0-1)"""
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()


def is_low_quality(rec):
    """判断是否为低质量记录"""
    t = rec.get("标题", "") or ""
    if t.startswith("session 工作"):
        return True
    if t.startswith("## Context Usage"):
        return True
    if len(t) < 5:
        return True
    return False


def is_empty_session(rec):
    """判断是否为空 session"""
    t = rec.get("标题", "") or ""
    if "0 user msgs" in t:
        return True
    if rec.get("user_msgs", 0) == 0 and rec.get("asst_msgs", 0) == 0:
        return True
    return False


def has_broken_kr(rec, valid_kr_ids):
    """判断关联 KR 是否已失效"""
    kr = rec.get("关联KR")
    if not kr:
        return False
    for k in kr:
        if isinstance(k, dict) and k.get("id") not in valid_kr_ids:
            return True
    return False


def delete_record(record_id):
    """删除单条 worklog"""
    return lark("api", "DELETE",
                f"/open-apis/bitable/v1/apps/{BASE}/tables/{TBL}/records/{record_id}",
                "--as", "user")


def update_record_title(record_id, new_title):
    """更新标题"""
    return lark("api", "PUT",
                f"/open-apis/bitable/v1/apps/{BASE}/tables/{TBL}/records/{record_id}",
                "--data", json.dumps({"fields": {"标题": new_title}}),
                "--as", "user")


def update_record(rid, fields):
    """更新记录字段"""
    lark("api", "PUT",
         f"/open-apis/bitable/v1/apps/{BASE}/tables/{TBL}/records/{rid}",
         "--data", json.dumps({"fields": fields}),
         "--as", "user")


def cmd_merge(records, do_write):
    """全量去重合并：完全同标题 → 自动合并；高相似 → 候选清单

    合并规则：
    1. 完全同标题 → 保留说明最长的那条，合并其余说明，删除重复
    2. 标题相似 > 85% 且同日期 → 候选合并（人工确认）
    3. 标题相似 > 85% 跨日期 → 如果是递进更新（如采购推进），合并；否则候选
    """
    from collections import defaultdict

    # 1. 完全同标题
    by_title = defaultdict(list)
    for r in records:
        t = (r.get("标题") or "").strip()
        if t:
            by_title[t].append(r)

    exact_groups = {t: recs for t, recs in by_title.items() if len(recs) > 1}
    if exact_groups:
        print(f"\n=== 完全同标题 ({len(exact_groups)} 组) ===")
        for title, recs in sorted(exact_groups.items(), key=lambda x: -len(x[1])):
            recs.sort(key=lambda r: len(r.get("说明") or ""), reverse=True)
            keep = recs[0]
            rest = recs[1:]

            all_notes = []
            for r in recs:
                note = (r.get("说明") or "").strip()
                if note and note not in all_notes:
                    all_notes.append(note)

            dates = sorted(set(r.get("日期", "?")[:10] for r in recs))
            print(f"  [{len(recs)}x] {title[:70]}")
            print(f"       dates: {', '.join(dates)}")

            if do_write:
                if len(all_notes) > 1:
                    update_record(keep["_rid"], {"说明": "\n\n---\n".join(all_notes)})
                for r in rest:
                    delete_record(r["_rid"])
                print(f"       → merged, kept {keep['_rid'][-8:]}, deleted {len(rest)}")

    # 2. 高度相似（> 85%）→ 候选
    titles_list = [(r["_rid"], r.get("标题", ""), r.get("日期", "")[:10],
                    (r.get("说明") or "")[:100])
                   for r in records if r.get("标题")]
    high_sim = []
    for i in range(len(titles_list)):
        for j in range(i + 1, len(titles_list)):
            sim = title_similarity(titles_list[i][1], titles_list[j][1])
            if sim > 0.85 and sim < 1.0:
                high_sim.append((sim, titles_list[i], titles_list[j]))

    if high_sim:
        high_sim.sort(key=lambda x: -x[0])
        print(f"\n=== 高度相似候选 ({len(high_sim)} 对，Top 20) ===")
        for sim, a, b in high_sim[:20]:
            same_day = a[2] == b[2]
            tag = "[同日]" if same_day else "[跨日]"
            print(f"  {sim:.0%} {tag} [{a[2]}] {a[1][:50]}")
            print(f"         [{b[2]}] {b[1][:50]}")
        if not do_write:
            print("  人工确认后: --mode merge --write")


def cmd_weekly(records, do_write):
    """每周清理：删空记录 + 找同日期合并候选"""
    today = date.today()
    week_ago = today - timedelta(days=7)


def cmd_weekly(records, do_write):
    """每周清理：删空记录 + 找同日期合并候选"""
    today = date.today()
    week_ago = today - timedelta(days=7)

    # 1. 空 session → 自动删除
    empty = [r for r in records if is_empty_session(r)]
    if empty:
        print(f"\n=== 空 session 记录 ({len(empty)} 条) ===")
        for r in empty:
            d = r.get("日期", "?")[:10]
            print(f"  [{d}] {r.get('标题','')[:60]}")
        if do_write:
            for r in empty:
                delete_record(r["_record_id"])
            print(f"  已删除 {len(empty)} 条")

    # 2. 同日期 + 相似标题 → 合并候选
    by_date = defaultdict(list)
    for r in records:
        d = r.get("日期", "")[:10] if r.get("日期") else ""
        if d and d >= str(week_ago):
            by_date[d].append(r)

    print(f"\n=== 最近 7 天相似标题 ({len(by_date)} 天有记录) ===")
    merge_found = 0
    for d, day_recs in sorted(by_date.items()):
        if len(day_recs) < 2:
            continue
        for i in range(len(day_recs)):
            for j in range(i + 1, len(day_recs)):
                sim = title_similarity(day_recs[i].get("标题", ""),
                                       day_recs[j].get("标题", ""))
                if sim > 0.7:
                    merge_found += 1
                    if merge_found <= 15:
                        print(f"  [{d}] {sim:.0%} | {day_recs[i].get('标题','')[:50]}")
                        print(f"         | {day_recs[j].get('标题','')[:50]}")
    if merge_found == 0:
        print("  无合并候选")
    else:
        print(f"\n  共 {merge_found} 对候选。人工确认后执行: --mode weekly --write")


def cmd_monthly(records, do_write):
    """每月清理：低质量标题 + 无效 KR + 跨日期同主题合并"""
    # 1. 低质量标题
    low_q = [r for r in records if is_low_quality(r)]
    if low_q:
        print(f"\n=== 低质量标题 ({len(low_q)} 条) ===")
        for r in low_q:
            d = r.get("日期", "?")[:10]
            note = (r.get("说明", "") or "")[:80].replace("\n", " ")
            print(f"  [{d}] {r.get('标题','')[:60]}")
            if note:
                print(f"       说明: {note}")
        print("  建议: 手动修正标题或删除")

    # 2. 跨日期同主题合并候选
    titles = [(r["_record_id"], r.get("标题", ""), r.get("日期", "")[:10])
              for r in records if r.get("标题")]
    merge_pairs = []
    for i in range(len(titles)):
        for j in range(i + 1, len(titles)):
            sim = title_similarity(titles[i][1], titles[j][1])
            if sim > 0.75 and titles[i][2] != titles[j][2]:
                merge_pairs.append((sim, titles[i], titles[j]))

    if merge_pairs:
        merge_pairs.sort(reverse=True)
        print(f"\n=== 跨日期同主题合并候选 (Top 15/{len(merge_pairs)}) ===")
        for sim, a, b in merge_pairs[:15]:
            print(f"  {sim:.0%} | [{a[2]}] {a[1][:50]}")
            print(f"         | [{b[2]}] {b[1][:50]}")
        print("  建议: 人工确认后合并为一条综合记录")

    # 3. 无效 KR 关联
    valid_kr = _get_valid_kr_ids()
    broken = [r for r in records if has_broken_kr(r, valid_kr)]
    if broken:
        print(f"\n=== 无效 KR 关联 ({len(broken)} 条) ===")
        print(f"  有效 KR ID: {len(valid_kr)} 个")
        for r in broken[:10]:
            d = r.get("日期", "?")[:10]
            kr_ids = [k.get("id", "?")[-8:] for k in r.get("关联KR", [])] if r.get("关联KR") else "?"
            print(f"  [{d}] {r.get('标题','')[:50]} | KR=...{kr_ids}")
        print("  建议: 重新映射到当前有效 KR")


def _get_valid_kr_ids():
    """获取当前有效的 KR record_id 列表"""
    TBL_KR = CONF["bases"]["okr_v2"]["tables"]["KR"]
    data = lark("base", "+record-list", "--base-token", BASE,
                "--table-id", TBL_KR, "--format", "json", "--limit", "200")
    return set(data["data"]["record_id_list"])


def cmd_dry_run(records):
    """仅输出统计"""
    today = date.today()
    print(f"总条数: {len(records)}")
    print(f"空 session: {sum(1 for r in records if is_empty_session(r))}")
    print(f"低质量标题: {sum(1 for r in records if is_low_quality(r))}")
    print(f"关联 KR 为空: {sum(1 for r in records if not r.get('关联KR'))}")

    dates = [r.get("日期", "")[:7] for r in records if r.get("日期")]
    monthly = Counter(dates)
    print(f"\n月度分布:")
    for m in sorted(monthly.keys())[-6:]:
        print(f"  {m}: {monthly[m]:>4}")

    now = str(today)
    recent = [r for r in records if r.get("日期", "").startswith(now[:4])]
    print(f"\n{now[:4]} 年至今: {len(recent)} 条")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["weekly", "monthly", "merge", "dry-run"],
                   default="dry-run")
    p.add_argument("--write", action="store_true",
                   help="执行修改（默认仅预览）")
    args = p.parse_args()

    records = fetch_all_worklogs()
    print(f"扫描 {len(records)} 条 worklog...")

    if args.mode == "weekly":
        cmd_weekly(records, args.write)
    elif args.mode == "monthly":
        cmd_monthly(records, args.write)
    elif args.mode == "merge":
        cmd_merge(records, args.write)
    else:
        cmd_dry_run(records)

    if not args.write and args.mode != "dry-run":
        print("\n⚠ 预览模式。加 --write 执行修改。")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""SUM 总结生成 — 从飞书 Base 数据聚合生成 Markdown 模板，交给 f-doc 创建文档。

用法:
  python3 sum_generate.py \\
    --okr-o /tmp/okr_o.json --okr-kr /tmp/okr_kr.json \\
    --worklog /tmp/worklog.json --reflect /tmp/reflect.json \\
    --period 2026Q2 --category work --type period

  python3 sum_generate.py --help
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


def load_json(path: str) -> dict:
    raw = Path(path).read_text()
    return json.loads(raw)


def parse_records(data: dict) -> tuple[list[str], list[list]]:
    """Return (field_names, records) from lark-cli JSON output."""
    return data["data"]["fields"], data["data"]["data"]


def build_index(records: list[list], key_idx: int = 0) -> dict:
    """Index records by _record_id (first element after fields mapping)."""
    idx = {}
    for rec in records:
        # lark-cli format: records are arrays matching field order
        # _record_id is NOT in fields but can be extracted from record_id_list
        # For now, index by the first field value (ID column)
        pass
    return idx


def extract_link_id(val) -> str | None:
    """Extract record ID from linked field value like [{'id': 'recXXXX'}]."""
    if isinstance(val, list) and len(val) > 0 and isinstance(val[0], dict):
        return val[0].get("id")
    return None


def period_match(record_period: str | list | None, target: str) -> bool:
    """Check if record period matches target.

    target: 2026Q1, 2026Q2, 2026H1, 2026H2, 2026, 2026 Full Year
    """
    if not record_period:
        return False
    if isinstance(record_period, list):
        record_period = record_period[0] if record_period else None
    if not record_period:
        return False

    # Normalize
    rp = str(record_period).strip()

    if target == "2026" or target == "2026 Full Year":
        return rp.startswith("2026")
    if target == "2026H1":
        return rp in ("2026Q1", "2026Q2")
    if target == "2026H2":
        return rp in ("2026Q3", "2026Q4")
    return rp == target


def parse_date(date_val) -> datetime | None:
    """Parse a date value from Base."""
    if not date_val:
        return None
    if isinstance(date_val, list):
        date_val = date_val[0] if date_val else None
    if not date_val:
        return None
    try:
        return datetime.strptime(str(date_val)[:10], "%Y-%m-%d")
    except ValueError:
        return None


def category_for_worklog(wl_rec, kr_map: dict, o_map: dict) -> str:
    """Walk Worklog → KR → O to get category."""
    kr_id = extract_link_id(wl_rec[5])  # 关联KR field
    if kr_id and kr_id in kr_map:
        o_id = extract_link_id(kr_map[kr_id][6])  # 关联O field
        if o_id and o_id in o_map:
            cat = o_map[o_id][5]  # 分类 field
            if isinstance(cat, list):
                return cat[0] if cat else "unknown"
            return str(cat) if cat else "unknown"
    return "unknown"


def load_all(okr_o_path, okr_kr_path, worklog_path, reflect_path):
    """Load and index all 4 tables."""
    o_fields, o_records = parse_records(load_json(okr_o_path))
    kr_fields, kr_records = parse_records(load_json(okr_kr_path))
    wl_fields, wl_records = parse_records(load_json(worklog_path))
    rf_fields, rf_records = parse_records(load_json(reflect_path))

    # Index by record_id (first element of each record array IS the ID, not _record_id)
    # We need _record_id for cross-table linking. lark-cli JSON includes record_id_list
    # in the same order as data. Let's re-parse to pair them.
    o_data = load_json(okr_o_path)
    kr_data = load_json(okr_kr_path)
    wl_data = load_json(worklog_path)
    rf_data = load_json(reflect_path)

    o_ids = o_data["data"]["record_id_list"]
    kr_ids = kr_data["data"]["record_id_list"]
    wl_ids = wl_data["data"]["record_id_list"]
    rf_ids = rf_data["data"]["record_id_list"]

    o_map = {rid: rec for rid, rec in zip(o_ids, o_records)}
    kr_map = {rid: rec for rid, rec in zip(kr_ids, kr_records)}
    wl_map = {rid: rec for rid, rec in zip(wl_ids, wl_records)}
    rf_map = {rid: rec for rid, rec in zip(rf_ids, rf_records)}

    return {
        "o": {"fields": o_fields, "records": o_records, "map": o_map, "ids": o_ids},
        "kr": {"fields": kr_fields, "records": kr_records, "map": kr_map, "ids": kr_ids},
        "wl": {"fields": wl_fields, "records": wl_records, "map": wl_map, "ids": wl_ids},
        "rf": {"fields": rf_fields, "records": rf_records, "map": rf_map, "ids": rf_ids},
    }


def filter_by_period(data: dict, period: str, category: str | None = None):
    """Filter all tables by period and optionally category.

    Returns filtered data dict with same structure.
    """
    o_map = data["o"]["map"]
    kr_map = data["kr"]["map"]
    wl_map = data["wl"]["map"]
    rf_map = data["rf"]["map"]

    # Filter O by period + category
    matched_o_ids = set()
    for rid, rec in o_map.items():
        rec_period = rec[6]  # 周期 field
        rec_cat = rec[5]  # 分类 field
        if isinstance(rec_cat, list):
            rec_cat = rec_cat[0] if rec_cat else None

        if period_match(rec_period, period):
            if category is None or rec_cat == category:
                matched_o_ids.add(rid)

    # If no O matches, return empty
    if not matched_o_ids:
        return None

    # Filter KR by matched O
    matched_kr_ids = set()
    kr_by_o = {}
    for rid, rec in kr_map.items():
        o_id = extract_link_id(rec[6])  # 关联O
        if o_id in matched_o_ids:
            matched_kr_ids.add(rid)
            kr_by_o.setdefault(o_id, []).append(rid)

    # Filter Worklog by matched KR
    matched_wl_ids = set()
    wl_by_kr = {}
    for rid, rec in wl_map.items():
        kr_id = extract_link_id(rec[5])  # 关联KR
        if kr_id in matched_kr_ids:
            matched_wl_ids.add(rid)
            wl_by_kr.setdefault(kr_id, []).append(rid)

    # Filter Reflect by matched O (or period match on date)
    matched_rf_ids = set()
    rf_by_o = {}
    for rid, rec in rf_map.items():
        o_id = extract_link_id(rec[3])  # 关联O
        if o_id in matched_o_ids:
            matched_rf_ids.add(rid)
            rf_by_o.setdefault(o_id, []).append(rid)

    return {
        "period": period,
        "category": category,
        "o_ids": matched_o_ids,
        "kr_ids": matched_kr_ids,
        "wl_ids": matched_wl_ids,
        "rf_ids": matched_rf_ids,
        "kr_by_o": kr_by_o,
        "wl_by_kr": wl_by_kr,
        "rf_by_o": rf_by_o,
    }


def cell(val) -> str:
    """Format a value for markdown table cell."""
    if val is None:
        return ""
    if isinstance(val, list):
        return ", ".join(str(v) for v in val)
    return str(val)


def generate_period_summary(data: dict, filtered: dict) -> str:
    """Generate 周期总结 markdown."""
    o_map = data["o"]["map"]
    kr_map = data["kr"]["map"]
    wl_map = data["wl"]["map"]
    rf_map = data["rf"]["map"]

    period = filtered["period"]
    cat = filtered["category"] or "全部"

    cat_label = {"work": "工作", "learn": "学习", "project": "项目"}.get(cat, cat)
    period_label = period

    lines = []
    lines.append(f"# {period_label} {cat_label}总结")
    lines.append("")

    # OKR 达成表
    lines.append("## OKR 达成")
    lines.append("")
    lines.append("| 目标 (O) | 关键结果 (KR) | 类型 | 进度 | 评分 |")
    lines.append("|-----------|---------------|------|------|------|")

    for o_id in filtered["o_ids"]:
        o_rec = o_map[o_id]
        o_title = o_rec[4]
        kr_ids = filtered["kr_by_o"].get(o_id, [])
        if not kr_ids:
            lines.append(f"| {o_title} | — | — | — | — |")
        for i, kr_id in enumerate(kr_ids):
            kr_rec = kr_map[kr_id]
            kr_title = kr_rec[7]
            kr_type = cell(kr_rec[2])
            kr_progress = f"{kr_rec[8]}%"
            kr_score = cell(kr_rec[3]) if kr_rec[3] else "—"
            o_display = o_title if i == 0 else ""
            lines.append(f"| {o_display} | {kr_title} | {kr_type} | {kr_progress} | {kr_score} |")

    lines.append("")

    # 核心成果
    lines.append("## 核心成果")
    lines.append("")

    # Group worklog by 成果类型
    by_type = {}
    for wl_id in filtered["wl_ids"]:
        wl_rec = wl_map[wl_id]
        wl_type = cell(wl_rec[3])
        by_type.setdefault(wl_type, []).append(wl_rec)

    type_order = ["项目交付", "技术调研", "学习输入", "故障应急", "团队建设", "其他"]
    for t in type_order:
        if t in by_type:
            count = len(by_type[t])
            lines.append(f"- {t}：{count} 项")

    lines.append("")

    # 详细成果列表
    lines.append("### 关键事项")
    lines.append("")
    for wl_id in list(filtered["wl_ids"])[:10]:
        wl_rec = wl_map[wl_id]
        wl_title = wl_rec[1]
        wl_desc = wl_rec[2] if wl_rec[2] else ""
        wl_quant = wl_rec[4] if wl_rec[4] else ""
        quant_str = f"（{wl_quant}）" if wl_quant else ""
        lines.append(f"- **{wl_title}**{quant_str}：{wl_desc}")

    lines.append("")

    # 量化总览
    lines.append("## 量化总览")
    lines.append("")
    lines.append(f"- 总记录数：{len(filtered['wl_ids'])}")
    lines.append(f"- 涉及 KR：{len(filtered['kr_ids'])} 个")
    lines.append(f"- 涉及 O：{len(filtered['o_ids'])} 个")

    # 计算完成率
    total_kr = len(filtered["kr_ids"])
    if total_kr > 0:
        done_kr = sum(1 for kid in filtered["kr_ids"] if kr_map[kid][8] == 100)
        lines.append(f"- KR 完成率：{done_kr}/{total_kr}（{done_kr*100//total_kr}%）")
    lines.append("")

    # 反思
    if filtered["rf_ids"]:
        lines.append("## 反思与洞察")
        lines.append("")
        for rf_id in list(filtered["rf_ids"])[:5]:
            rf_rec = rf_map[rf_id]
            rf_title = rf_rec[1]
            rf_good = rf_rec[4] if rf_rec[4] else ""
            rf_bad = rf_rec[6] if rf_rec[6] else ""
            rf_learn = rf_rec[5] if rf_rec[5] else ""
            lines.append(f"**{rf_title}**")
            if rf_good:
                lines.append(f"- 做得好：{rf_good}")
            if rf_bad:
                lines.append(f"- 待改进：{rf_bad}")
            if rf_learn:
                lines.append(f"- 学到：{rf_learn}")
            lines.append("")

    # 下阶段计划
    lines.append("## 下阶段计划")
    lines.append("")
    for rf_id in list(filtered["rf_ids"])[:3]:
        rf_rec = rf_map[rf_id]
        rf_next = rf_rec[7] if rf_rec[7] else ""
        if rf_next:
            lines.append(f"- {rf_next}")
    lines.append("")

    return "\n".join(lines)


def generate_domain_summary(data: dict, domain: str, year: str = "2026") -> str:
    """Generate 领域总结 markdown."""
    o_map = data["o"]["map"]
    kr_map = data["kr"]["map"]
    wl_map = data["wl"]["map"]
    rf_map = data["rf"]["map"]

    lines = []
    lines.append(f"# {year} {domain} 专项总结")
    lines.append("")

    # Find O with matching category
    matched_o = {}
    for rid, rec in o_map.items():
        cat = rec[5]
        if isinstance(cat, list):
            cat = cat[0] if cat else None
        if cat == domain and period_match(rec[6], year):
            matched_o[rid] = rec

    # Collect all linked KRs and worklogs
    matched_kr = {}
    matched_wl = {}
    for o_id in matched_o:
        for kr_id, kr_rec in kr_map.items():
            linked_o = extract_link_id(kr_rec[6])
            if linked_o == o_id:
                matched_kr[kr_id] = kr_rec
                for wl_id, wl_rec in wl_map.items():
                    linked_kr = extract_link_id(wl_rec[5])
                    if linked_kr == kr_id:
                        matched_wl[wl_id] = wl_rec

    # Collect reflect
    matched_rf = {}
    for rf_id, rf_rec in rf_map.items():
        linked_o = extract_link_id(rf_rec[3])
        if linked_o in matched_o:
            matched_rf[rf_id] = rf_rec

    lines.append("## 概述")
    lines.append("")
    lines.append(f"- 关联目标：{len(matched_o)} 个")
    lines.append(f"- 关键结果：{len(matched_kr)} 个")
    lines.append(f"- 工作记录：{len(matched_wl)} 条")
    lines.append(f"- 反思记录：{len(matched_rf)} 条")
    lines.append("")

    # Key milestones
    lines.append("## 关键里程碑")
    lines.append("")

    # Sort worklog by date
    wl_sorted = sorted(matched_wl.items(), key=lambda x: str(x[1][6]) if x[1][6] else "")
    for wl_id, wl_rec in wl_sorted[:8]:
        wl_date = str(wl_rec[6])[:10] if wl_rec[6] else ""
        wl_title = wl_rec[1]
        wl_desc = wl_rec[2] if wl_rec[2] else ""
        lines.append(f"- {wl_date} — **{wl_title}**：{wl_desc}")

    lines.append("")

    # Capability accumulation
    lines.append("## 能力积累")
    lines.append("")
    if matched_rf:
        for rf_id, rf_rec in list(matched_rf.items())[:5]:
            rf_learn = rf_rec[5] if rf_rec[5] else ""
            if rf_learn:
                lines.append(f"- {rf_learn}")
    lines.append("")

    # Next year planning
    lines.append("## 来年规划")
    lines.append("")
    for rf_id, rf_rec in list(matched_rf.items())[:3]:
        rf_next = rf_rec[7] if rf_rec[7] else ""
        if rf_next:
            lines.append(f"- {rf_next}")
    lines.append("")

    return "\n".join(lines)


def generate_okr_review(data: dict, period: str) -> str:
    """Generate OKR 复盘 markdown."""
    o_map = data["o"]["map"]
    kr_map = data["kr"]["map"]
    rf_map = data["rf"]["map"]

    # Filter O by period
    matched_o = {}
    for rid, rec in o_map.items():
        if period_match(rec[6], period):
            matched_o[rid] = rec

    lines = []
    lines.append(f"# {period} OKR 复盘")
    lines.append("")

    total_score = 0
    total_kr = 0
    committed_done = 0
    committed_total = 0
    aspirational_done = 0
    aspirational_total = 0

    for o_id, o_rec in matched_o.items():
        o_title = o_rec[4]
        o_status = cell(o_rec[2])
        o_cat = cell(o_rec[5])
        lines.append(f"## O: {o_title}")
        lines.append(f"状态：{o_status} | 分类：{o_cat}")
        lines.append("")
        lines.append("| KR | 类型 | 信心 | 进度 | 评分 |")
        lines.append("|----|------|------|------|------|")

        for kr_id, kr_rec in kr_map.items():
            linked_o = extract_link_id(kr_rec[6])
            if linked_o != o_id:
                continue
            kr_title = kr_rec[7]
            kr_type = cell(kr_rec[2])
            kr_confidence = cell(kr_rec[5])
            kr_progress = f"{kr_rec[8]}%"
            kr_score = kr_rec[3] if kr_rec[3] else 0

            lines.append(f"| {kr_title} | {kr_type} | {kr_confidence} | {kr_progress} | {kr_score} |")

            total_kr += 1
            total_score += float(kr_score)
            if kr_type == "Committed":
                committed_total += 1
                if kr_rec[8] == 100:
                    committed_done += 1
            elif kr_type == "Aspirational":
                aspirational_total += 1
                if kr_rec[8] >= 70:
                    aspirational_done += 1

        lines.append("")

    # Overall assessment
    avg_score = total_score / total_kr if total_kr > 0 else 0
    lines.append("## 总体评估")
    lines.append("")
    lines.append(f"- 平均评分：{avg_score:.1f}")
    if committed_total > 0:
        lines.append(f"- Committed 达成率：{committed_done}/{committed_total}（{committed_done*100//committed_total}%）")
    if aspirational_total > 0:
        lines.append(f"- Aspirational 达成率：{aspirational_done}/{aspirational_total}（{aspirational_done*100//aspirational_total}%）")
    lines.append("")

    # What went well / needs improvement
    matched_rf = {}
    for rf_id, rf_rec in rf_map.items():
        linked_o = extract_link_id(rf_rec[3])
        if linked_o in matched_o:
            matched_rf[rf_id] = rf_rec

    lines.append("## 做得好的")
    for rf_id, rf_rec in matched_rf.items():
        rf_good = rf_rec[4] if rf_rec[4] else ""
        if rf_good:
            lines.append(f"- {rf_good}")
    lines.append("")

    lines.append("## 待改进的")
    for rf_id, rf_rec in matched_rf.items():
        rf_bad = rf_rec[6] if rf_rec[6] else ""
        if rf_bad:
            lines.append(f"- {rf_bad}")
    lines.append("")

    lines.append("## 下周期调整")
    for rf_id, rf_rec in matched_rf.items():
        rf_next = rf_rec[7] if rf_rec[7] else ""
        if rf_next:
            lines.append(f"- {rf_next}")
    lines.append("")

    return "\n".join(lines)


def generate_annual_report(data: dict, year: str = "2026") -> str:
    """Generate 年度综合报告 markdown."""
    o_map = data["o"]["map"]
    kr_map = data["kr"]["map"]
    wl_map = data["wl"]["map"]
    rf_map = data["rf"]["map"]

    lines = []
    lines.append(f"# {year} 年度个人报告")
    lines.append("")

    # Per-category stats
    categories = ["work", "learn", "project"]
    cat_labels = {"work": "工作", "learn": "学习", "project": "项目"}

    lines.append("## 总览")
    lines.append("")
    lines.append("| 分类 | O 数量 | KR 数量 | Worklog 数量 | Reflect 数量 |")
    lines.append("|------|--------|---------|-------------|-------------|")

    all_wl_ids = set()
    all_rf_ids = set()

    for cat in categories:
        cat_o = {rid: rec for rid, rec in o_map.items()
                 if (rec[5][0] if isinstance(rec[5], list) else rec[5]) == cat
                 and period_match(rec[6], year)}
        cat_o_ids = set(cat_o.keys())

        cat_kr_count = sum(1 for rid, rec in kr_map.items()
                          if extract_link_id(rec[6]) in cat_o_ids)
        cat_wl_count = sum(1 for rid, rec in wl_map.items()
                          if extract_link_id(rec[5]) in
                          {krid for krid, krec in kr_map.items()
                           if extract_link_id(krec[6]) in cat_o_ids})
        cat_rf_count = sum(1 for rid, rec in rf_map.items()
                          if extract_link_id(rec[3]) in cat_o_ids)

        all_wl_ids.update(rid for rid, rec in wl_map.items()
                         if extract_link_id(rec[5]) in
                         {krid for krid, krec in kr_map.items()
                          if extract_link_id(krec[6]) in cat_o_ids})
        all_rf_ids.update(rid for rid, rec in rf_map.items()
                         if extract_link_id(rec[3]) in cat_o_ids)

        lines.append(f"| {cat_labels[cat]} | {len(cat_o)} | {cat_kr_count} | {cat_wl_count} | {cat_rf_count} |")

    lines.append(f"| **合计** | **{sum(1 for rid, rec in o_map.items() if period_match(rec[6], year))}** | **{sum(1 for rid, rec in kr_map.items() if period_match(rec[1], year))}** | **{len(all_wl_ids)}** | **{len(all_rf_ids)}** |")
    lines.append("")

    # Category breakdowns
    for cat in categories:
        cat_o = {rid: rec for rid, rec in o_map.items()
                 if (rec[5][0] if isinstance(rec[5], list) else rec[5]) == cat
                 and period_match(rec[6], year)}
        if not cat_o:
            continue

        lines.append(f"## {cat_labels[cat]}领域")
        lines.append("")

        for o_id, o_rec in list(cat_o.items())[:3]:
            o_title = o_rec[4]
            o_status = cell(o_rec[2])
            lines.append(f"**{o_title}**（{o_status}）")
            lines.append("")

            for kr_id, kr_rec in kr_map.items():
                if extract_link_id(kr_rec[6]) == o_id:
                    kr_title = kr_rec[7]
                    kr_progress = kr_rec[8]
                    lines.append(f"- {kr_title}：{kr_progress}%")
            lines.append("")

    # Growth trajectory
    lines.append("## 成长轨迹")
    lines.append("")
    if all_rf_ids:
        for rf_id in list(all_rf_ids)[:5]:
            rf_rec = rf_map[rf_id]
            rf_title = rf_rec[1]
            rf_learn = rf_rec[5] if rf_rec[5] else ""
            if rf_learn:
                lines.append(f"- {rf_title} — {rf_learn}")
    lines.append("")

    # New year OKR preview
    lines.append("## 新年展望")
    lines.append("")
    for rf_id in list(all_rf_ids)[:3]:
        rf_rec = rf_map[rf_id]
        rf_next = rf_rec[7] if rf_rec[7] else ""
        if rf_next:
            lines.append(f"- {rf_next}")
    lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="SUM 总结生成器")
    parser.add_argument("--okr-o", required=True, help="OKR_O JSON 文件路径")
    parser.add_argument("--okr-kr", required=True, help="OKR_KR JSON 文件路径")
    parser.add_argument("--worklog", required=True, help="Worklog JSON 文件路径")
    parser.add_argument("--reflect", required=True, help="Reflect JSON 文件路径")
    parser.add_argument("--period", default="2026Q2", help="周期：2026Q1/2026Q2/2026H1/2026")
    parser.add_argument("--category", default=None, help="分类过滤：work/learn/project")
    parser.add_argument("--type", dest="summary_type", default="period",
                        choices=["period", "domain", "okr-review", "annual"],
                        help="总结类型")
    parser.add_argument("--domain", default=None, help="领域总结的领域名")
    parser.add_argument("--year", default="2026", help="年度报告的年份")
    parser.add_argument("--output", default=None, help="输出文件路径（默认 stdout）")
    args = parser.parse_args()

    data = load_all(args.okr_o, args.okr_kr, args.worklog, args.reflect)

    if args.summary_type == "period":
        filtered = filter_by_period(data, args.period, args.category)
        if filtered is None:
            print(f"# 无匹配数据：period={args.period} category={args.category}", file=sys.stderr)
            sys.exit(1)
        md = generate_period_summary(data, filtered)
    elif args.summary_type == "domain":
        md = generate_domain_summary(data, args.domain or "work", args.year)
    elif args.summary_type == "okr-review":
        md = generate_okr_review(data, args.period)
    elif args.summary_type == "annual":
        md = generate_annual_report(data, args.year)
    else:
        print(f"Unknown type: {args.summary_type}", file=sys.stderr)
        sys.exit(1)

    if args.output:
        Path(args.output).write_text(md)
    else:
        print(md)


if __name__ == "__main__":
    main()

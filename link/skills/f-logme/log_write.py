#!/usr/bin/env python3
"""
f-logme 数据写入助手

三个子命令:
- worklog: 写 worklog + 自动 KR_Progress(进度+5%) + 更新 KR.进度
- reflect: 写 reflect + 批量 KR_Progress(本周 worklog 涉及的每个 KR)
- progress: 直接更新 KR 进度 (留 history)

用法示例:
  python3 log_write.py worklog --title "X" --kr recXXX --type "项目交付" --date 2026-06-04
  python3 log_write.py reflect --title "Q2 W3" --o recYYY --date 2026-06-04 --good "A" --improve "B" --learned "C" --next "D"
  python3 log_write.py progress --kr recXXX --value 60 --confidence "On Track" --note "手动更新"
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import date

BASE = "LX5lb6VfdaJHWrsRbTgc8Y50nmj"
T = {
    "O": "tbli0erWbDwrfiEj",
    "KR": "tblZhpELO31mAkg6",
    "Worklog": "tblVsC0L7QFzMeYM",
    "Reflect": "tblNLcyrOHD3OU87",
    "KR_Progress": "tbljvET4DFtRomGi",
}

ENV = {
    **os.environ,
    "LARKSUITE_CLI_CONFIG_DIR": os.environ.get("LARKSUITE_CLI_CONFIG_DIR", os.path.expanduser("~/.lark-cli-<account>")),
    "PATH": os.path.expanduser("~/.local/bin") + ":" + os.environ.get("PATH", ""),
    "HOME": os.environ.get("HOME", os.path.expanduser("~")),
}


def lark(*args, cwd=None):
    """调 lark-cli, 过滤日志行, 返回解析后 JSON。cwd 默认 /tmp (lark-cli --json @file 需相对路径)"""
    r = subprocess.run(["lark-cli", *args], capture_output=True, text=True, env=ENV, cwd=cwd or "/tmp")
    # 过滤 lark-cli 日志行 + WSL 注入的 cwd 通知行
    lines = [l for l in r.stdout.splitlines() if not l.startswith("[lark-cli]") and not l.startswith("Shell cwd was reset")]
    return json.loads("\n".join(lines))


def write_json_file(payload):
    """写 JSON 到 /tmp, 返回相对路径 (供 --json @file 用)"""
    fd, path = tempfile.mkstemp(suffix=".json", dir="/tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f, ensure_ascii=False)
    return path


def get_kr(kr_id):
    """Get KR record fields as {field_name: value} dict"""
    out = lark("base", "+record-get", "--base-token", BASE, "--table-id", T["KR"],
               "--record-id", kr_id, "--as", "user", "--format", "json")
    d = out.get("data", {})
    names = d.get("fields", [])
    values = d.get("data", [[]])[0] if d.get("data") else []
    return dict(zip(names, values))


def update_kr_field(kr_id, fields_dict):
    """更新 KR 单字段 (raw API: PUT /records/{id})"""
    payload = {"fields": fields_dict}
    lark("api", "PUT", f"/open-apis/bitable/v1/apps/{BASE}/tables/{T['KR']}/records/{kr_id}",
         "--data", json.dumps(payload), "--as", "user")


def write_kr_progress(kr_id, value, confidence, source, date_str, note,
                      worklog_id=None, reflect_id=None):
    """写一条 KR_Progress 记录"""
    # KR.信心 (5 选项: On Track/At Risk/Done/Blocked/Committed) → KR_Progress.信心 (4 选项)
    # Committed/Aspirational 是 KR 类型分类，不是进度信心
    KR_TO_KP_CONFIDENCE = {
        "Committed": "On Track",
        "Aspirational": "On Track",
        "On Track": "On Track",
        "At Risk": "At Risk",
        "Blocked": "Blocked",
        "Done": "Done",
    }
    if isinstance(confidence, list):
        confidence = confidence[0] if confidence else "On Track"
    confidence = KR_TO_KP_CONFIDENCE.get(confidence, "On Track")

    fields = ["关联KR", "进度值", "信心", "来源"]
    if worklog_id:
        fields.append("关联Worklog")
    if reflect_id:
        fields.append("关联Reflect")
    fields.extend(["备注", "日期"])

    row = [
        [{"id": kr_id}],
        value,
        confidence,
        source,
    ]
    if worklog_id:
        row.append([{"id": worklog_id}])
    if reflect_id:
        row.append([{"id": reflect_id}])
    row.extend([note, date_str])

    payload = {"fields": fields, "rows": [row]}
    path = write_json_file(payload)
    try:
        out = lark("base", "+record-batch-create", "--base-token", BASE,
                   "--table-id", T["KR_Progress"], "--as", "user",
                   "--json", f"@{os.path.basename(path)}")
    finally:
        os.unlink(path)
    return out["data"]["record_id_list"][0]


def cmd_worklog(args):
    date_str = args.date or date.today().isoformat()

    fields = ["标题", "关联KR", "成果类型", "量化结果", "说明", "日期"]
    row = [
        args.title,
        [{"id": args.kr}] if args.kr else None,
        args.type or "项目交付",
        args.quant or "",
        args.note or "",
        date_str,
    ]
    payload = {"fields": fields, "rows": [row]}
    path = write_json_file(payload)
    try:
        out = lark("base", "+record-batch-create", "--base-token", BASE,
                   "--table-id", T["Worklog"], "--as", "user",
                   "--json", f"@{os.path.basename(path)}")
    finally:
        os.unlink(path)

    worklog_id = out["data"]["record_id_list"][0]

    result = {"worklog_id": worklog_id}

    if args.kr:
        kr = get_kr(args.kr)
        old_progress = kr.get("进度") or 0
        old_confidence = kr.get("信心") or "On Track"
        new_progress = min(100, old_progress + 5)
        new_confidence = old_confidence

        kp_id = write_kr_progress(
            kr_id=args.kr,
            value=new_progress,
            confidence=new_confidence,
            source="worklog",
            date_str=date_str,
            note=f"worklog 触发: {args.title[:50]}",
            worklog_id=worklog_id,
        )
        update_kr_field(args.kr, {"进度": new_progress})

        result["kr_progress_id"] = kp_id
        result["kr_progress"] = f"{old_progress} → {new_progress}"

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def cmd_progress(args):
    date_str = args.date or date.today().isoformat()
    kr = get_kr(args.kr)
    old_progress = kr.get("进度") or 0
    confidence = args.confidence or kr.get("信心") or "On Track"

    kp_id = write_kr_progress(
        kr_id=args.kr,
        value=args.value,
        confidence=confidence,
        source=args.source or "手动",
        date_str=date_str,
        note=args.note or f"手动更新: {old_progress} → {args.value}",
    )
    update_kr_field(args.kr, {"进度": args.value})

    print(json.dumps({
        "kr_progress_id": kp_id,
        "kr_progress": f"{old_progress} → {args.value}",
        "kr_id": args.kr,
    }, ensure_ascii=False, indent=2))
    return 0


def cmd_reflect(args):
    date_str = args.date or date.today().isoformat()

    fields = ["标题", "周期类型", "关联O", "做得好", "待改进", "学到", "下阶段", "日期"]
    row = [
        args.title,
        args.period or "周",
        [{"id": args.o}] if args.o else None,
        args.good or "",
        args.improve or "",
        args.learned or "",
        args.next or "",
        date_str,
    ]
    payload = {"fields": fields, "rows": [row]}
    path = write_json_file(payload)
    try:
        out = lark("base", "+record-batch-create", "--base-token", BASE,
                   "--table-id", T["Reflect"], "--as", "user",
                   "--json", f"@{os.path.basename(path)}")
    finally:
        os.unlink(path)

    reflect_id = out["data"]["record_id_list"][0]
    result = {"reflect_id": reflect_id, "kr_updates": []}

    if args.batch_kr:
        for kr_id in args.batch_kr:
            kr = get_kr(kr_id)
            old_progress = kr.get("进度") or 0
            new_progress = min(100, old_progress + 10)
            confidence = kr.get("信心") or "On Track"

            kp_id = write_kr_progress(
                kr_id=kr_id,
                value=new_progress,
                confidence=confidence,
                source="reflect",
                date_str=date_str,
                note=f"reflect 触发: {args.title[:50]}",
                reflect_id=reflect_id,
            )
            update_kr_field(kr_id, {"进度": new_progress})
            result["kr_updates"].append({
                "kr_id": kr_id,
                "kr_progress": f"{old_progress} → {new_progress}",
                "kr_progress_id": kp_id,
            })

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    w = sub.add_parser("worklog")
    w.add_argument("--title", required=True)
    w.add_argument("--kr", help="关联 KR record_id")
    w.add_argument("--type", help="成果类型")
    w.add_argument("--quant", help="量化结果")
    w.add_argument("--note", help="说明")
    w.add_argument("--date", help="日期 YYYY-MM-DD")
    w.set_defaults(func=cmd_worklog)

    r = sub.add_parser("reflect")
    r.add_argument("--title", required=True)
    r.add_argument("--period", choices=["周", "月", "季度", "年"])
    r.add_argument("--o", help="关联 O record_id")
    r.add_argument("--good", help="做得好")
    r.add_argument("--improve", help="待改进")
    r.add_argument("--learned", help="学到")
    r.add_argument("--next", help="下阶段")
    r.add_argument("--batch-kr", nargs="*", help="批量关联的 KR record_id (本周涉及的)")
    r.add_argument("--date", help="日期 YYYY-MM-DD")
    r.set_defaults(func=cmd_reflect)

    pr = sub.add_parser("progress")
    pr.add_argument("--kr", required=True)
    pr.add_argument("--value", type=float, required=True)
    pr.add_argument("--confidence", choices=["On Track", "At Risk", "Blocked", "Done"])
    pr.add_argument("--source", choices=["手动", "对话", "worklog", "reflect"])
    pr.add_argument("--note", help="备注")
    pr.add_argument("--date", help="日期 YYYY-MM-DD")
    pr.set_defaults(func=cmd_progress)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()

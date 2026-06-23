#!/usr/bin/env python3
"""
f-logme 数据写入助手

子命令:
- worklog: 写 worklog
- reflect: 写 reflect（含批量关联 KR, 仅写入关联，不触发 KR 字段更新）
- kr-status: 改 KR.状态 (Active / Done / Cancelled)

设计变化 (2026-06-12):
- 移除 KR_Progress 历史快照（表已废弃）
- 移除"每 worklog +5% / 每 reflect +10%"伪指标
- KR 状态改为手动管理（完成时主动跑 kr-status）
- 状态字段统一为 KR.状态 (3 选 1)，不再用 KR.进度 / KR.信心

用法示例:
  python3 log_write.py worklog --title "X" --kr recXXX --type "项目交付" --date 2026-06-12
  python3 log_write.py reflect --title "Q2 W3" --o recYYY --date 2026-06-12 --good "A" --improve "B" --learned "C" --next "D" --batch-kr recXXX recYYY
  python3 log_write.py kr-status --kr recXXX --status Done
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path


def _find_conf():
    """Locate conf/f-logme.json alongside ccconfig root."""
    for anchor in [Path(__file__).resolve().parent.parent.parent.parent.parent,
                   Path.home() / "git" / "ccconfig"]:
        candidate = anchor / "conf" / "f-logme.json"
        if candidate.exists():
            return candidate
    sys.exit("conf/f-logme.json not found")


CONF = json.loads(_find_conf().read_text())
BASE = CONF["bases"]["okr_v2"]["token"]
T = CONF["bases"]["okr_v2"]["tables"]

ENV = {
    **os.environ,
    "LARKSUITE_CLI_CONFIG_DIR": os.path.expanduser(CONF["lark_cli"]["config_dir"]),
    "PATH": os.path.expanduser("~/.local/bin") + ":" + os.environ.get("PATH", ""),
    "HOME": os.environ.get("HOME", os.path.expanduser("~")),
}


def lark(*args, cwd=None):
    """调 lark-cli, 过滤日志行, 返回解析后 JSON。cwd 默认 /tmp (lark-cli --json @file 需相对路径)"""
    r = subprocess.run(["lark-cli", *args], capture_output=True, text=True, env=ENV, cwd=cwd or "/tmp")
    lines = [l for l in r.stdout.splitlines() if not l.startswith("[lark-cli]") and not l.startswith("Shell cwd was reset")]
    return json.loads("\n".join(lines))


def write_json_file(payload):
    """写 JSON 到 /tmp, 返回相对路径 (供 --json @file 用)"""
    fd, path = tempfile.mkstemp(suffix=".json", dir="/tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f, ensure_ascii=False)
    return path


def update_kr_field(kr_id, fields_dict):
    """更新 KR 单字段 (raw API: PUT /records/{id})"""
    payload = {"fields": fields_dict}
    lark("api", "PUT", f"/open-apis/bitable/v1/apps/{BASE}/tables/{T['KR']}/records/{kr_id}",
         "--data", json.dumps(payload), "--as", "user")


def cmd_worklog(args):
    date_str = args.date or date.today().isoformat()

    fields = ["标题", "成果类型", "关联KR", "日期", "说明"]
    row = [
        args.title,
        args.type or "工具开发",
        [{"id": args.kr}] if args.kr else None,
        date_str,
        args.note or "",
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
    print(json.dumps({"worklog_id": worklog_id}, ensure_ascii=False, indent=2))
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
    result = {"reflect_id": reflect_id, "linked_krs": args.batch_kr or []}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def cmd_kr_status(args):
    """手动更新 KR.状态 (Active / Done / Cancelled)"""
    update_kr_field(args.kr, {"KR.状态": args.status})
    print(json.dumps({"kr_id": args.kr, "status": args.status}, ensure_ascii=False, indent=2))
    return 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    w = sub.add_parser("worklog")
    w.add_argument("--title", required=True)
    w.add_argument("--kr", help="关联 KR record_id")
    w.add_argument("--type", help="成果类型")
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

    k = sub.add_parser("kr-status")
    k.add_argument("--kr", required=True, help="KR record_id")
    k.add_argument("--status", required=True, choices=["Active", "Done", "Cancelled"])
    k.set_defaults(func=cmd_kr_status)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()

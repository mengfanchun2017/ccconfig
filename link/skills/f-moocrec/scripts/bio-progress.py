#!/usr/bin/env python3
"""bio-progress.py — 飞书 Base 学习进度读写工具

Usage:
  python3 bio-progress.py list                    # 列出所有进度记录
  python3 bio-progress.py add <json_payload>       # 添加一条进度记录
  python3 bio-progress.py stats                   # 统计概览
  python3 bio-progress.py completed <course_name> <date> [cert_url]  # 标记完成

仿 f-logme/log_write.py 模式。读取 conf/f-moocrec.json 获取 Base token。
"""

import json
import os
import subprocess
import sys
from pathlib import Path
from tempfile import mkstemp


def find_conf():
    d = Path(__file__).resolve().parent
    while d != d.parent:
        p = d / "conf" / "f-moocrec.json"
        if p.exists():
            return p
        d = d.parent
    raise FileNotFoundError("conf/f-moocrec.json not found")


CONF = json.loads(find_conf().read_text())
BASE = CONF["base"]["token"]
T = CONF["base"]["tables"]["progress"]

ENV = {
    **os.environ,
    "LARKSUITE_CLI_CONFIG_DIR": os.path.expanduser(CONF["lark_cli"]["config_dir"]),
    "PATH": os.path.expanduser("~/.local/bin") + ":" + os.environ.get("PATH", ""),
}


def lark(*args):
    r = subprocess.run(
        ["lark-cli", *args], capture_output=True, text=True, env=ENV, cwd="/tmp"
    )
    lines = [
        l
        for l in r.stdout.splitlines()
        if not l.startswith("[lark-cli]") and "Shell cwd" not in l
    ]
    if not lines:
        return None
    try:
        return json.loads("\n".join(lines))
    except json.JSONDecodeError:
        print("Failed to parse lark-cli output:", file=sys.stderr)
        print("\n".join(lines), file=sys.stderr)
        return None


def list_records():
    result = lark(
        "base", "+record-list",
        "--base-token", BASE,
        "--table-id", T,
        "--format", "json",
        "--limit", "200",
    )
    if not result or not result.get("data"):
        return []
    data = result["data"]
    fields = data.get("fields", [])
    records = data.get("data", [])
    record_ids = data.get("record_id_list", [])
    out = []
    for i, rec in enumerate(records):
        d = dict(zip(fields, rec))
        if record_ids:
            d["_record_id"] = record_ids[i] if i < len(record_ids) else None
        out.append(d)
    return out


def add_record(payload):
    fd, path = mkstemp(suffix=".json", dir="/tmp", text=True)
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f, ensure_ascii=False)
    result = lark(
        "base", "+record-batch-create",
        "--base-token", BASE,
        "--table-id", T,
        "--as", "user",
        "--json", f"@{os.path.basename(path)}",
    )
    os.unlink(path)
    return result


def stats():
    records = list_records()
    total = len(records)
    by_status = {}
    by_stage = {}
    cert_count = 0
    total_hours = 0
    for r in records:
        s = r.get("状态", "未知")
        by_status[s] = by_status.get(s, 0) + 1
        stage = r.get("阶段", "未知")
        by_stage[stage] = by_stage.get(stage, 0) + 1
        if r.get("轨道") == "付费证书":
            cert_count += 1
        hours = r.get("投入时间")
        if hours and isinstance(hours, (int, float)):
            total_hours += hours
    return {
        "total": total,
        "by_status": by_status,
        "by_stage": by_stage,
        "cert_count": cert_count,
        "total_hours": total_hours,
    }


def mark_completed(course_name, date, cert_url=None):
    records = list_records()
    target_idx = None
    for i, r in enumerate(records):
        if r.get("课程名称") == course_name:
            target_idx = i
            break
    if target_idx is None:
        print(f"Course not found: {course_name}")
        return None

    record_id = records[target_idx].get("_record_id")
    if not record_id:
        print(f"No record_id for: {course_name}")
        return None

    fields = {"状态": "✅已完成", "完成日期": date}
    if cert_url:
        fields["证书URL"] = cert_url
        fields["轨道"] = "付费证书"

    payload = {"fields": fields}
    fd, path = mkstemp(suffix=".json", dir="/tmp", text=True)
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f, ensure_ascii=False)

    result = lark(
        "api", "PUT",
        f"/open-apis/bitable/v1/apps/{BASE}/tables/{T}/records/{record_id}",
        "--data", f"@{os.path.basename(path)}",
        "--as", "user",
    )
    os.unlink(path)
    return result


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "list":
        records = list_records()
        print(json.dumps(records, ensure_ascii=False, indent=2))
    elif cmd == "stats":
        s = stats()
        print(json.dumps(s, ensure_ascii=False, indent=2))
    elif cmd == "add":
        if len(sys.argv) < 3:
            print("Usage: bio-progress.py add '<json_payload>'")
            sys.exit(1)
        payload = json.loads(sys.argv[2])
        result = add_record(payload)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif cmd == "completed":
        if len(sys.argv) < 4:
            print("Usage: bio-progress.py completed <course_name> <date> [cert_url]")
            sys.exit(1)
        cert_url = sys.argv[4] if len(sys.argv) > 4 else None
        result = mark_completed(sys.argv[2], sys.argv[3], cert_url)
        print(json.dumps(result, ensure_ascii=False, indent=2) if result else "Failed")
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)

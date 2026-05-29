#!/usr/bin/env python3
"""f-sync: 飞书云盘 ↔ 本地 双向同步"""
import json, os, subprocess, sys
from pathlib import Path

CONFIG = Path.home() / ".config" / "f-sync" / "config.json"
LARK_CLI = Path.home() / ".local" / "bin" / "lark-cli"


def info(msg: str) -> None:
    print(f"[f-sync] {msg}")


def die(msg: str) -> int:
    print(f"[f-sync] ERROR: {msg}", file=sys.stderr)
    return 1


def main() -> int:
    if not CONFIG.exists():
        return die(f"配置文件不存在: {CONFIG}。先运行 f-sync install 或手动创建。")
    if not LARK_CLI.exists():
        return die("lark-cli 未安装")

    cfg = json.loads(CONFIG.read_text())
    lark_config = os.path.expanduser(cfg.get("lark_config_dir", "~/.lark-cli-<account>"))
    env = {
        **os.environ,
        "LARKSUITE_CLI_CONFIG_DIR": lark_config,
        "PATH": f"{Path.home()}/.local/bin:{os.environ.get('PATH', '')}",
    }

    failed = 0
    for job in cfg.get("jobs", []):
        name = job["name"]
        local_dir = os.path.expanduser(job["local_dir"])
        folder_token = job["folder_token"]
        on_conflict = job.get("on_conflict", "local-wins")

        # lark-cli 要求 --local-dir 是相对路径 → cd 到父目录
        local_path = Path(local_dir).resolve()
        parent = str(local_path.parent)
        rel_dir = local_path.name

        info(f"同步 [{name}]: {local_dir} ↔ {folder_token}")
        result = subprocess.run(
            [str(LARK_CLI), "drive", "+sync",
             "--folder-token", folder_token,
             "--local-dir", rel_dir,
             "--on-conflict", on_conflict],
            env=env,
            cwd=parent,
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            info(f"[{name}] OK")
        else:
            info(f"[{name}] FAILED")
            print(result.stderr, file=sys.stderr)
            failed += 1

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

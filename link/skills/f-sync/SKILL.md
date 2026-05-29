---
name: f-sync
user-invocable: true
description: 飞书云盘 ↔ 本地目录双向同步。定时轮询（方案A），配置文件独立于 skill 代码便于分享。
allowed-tools: Bash
---

# f-sync — 飞书云盘双向同步

轮询模式（默认 30s 间隔），基于 `lark-cli drive +sync`（exact/SHA-256 模式，不用 quick）。

## 设计原则

| 层 | 位置 | 说明 |
|----|------|------|
| Skill 代码 | `skills/f-sync/` | 可分享，不含个人路径 |
| 用户配置 | `~/.config/f-sync/config.json` | 个人独有，不提交 git |

分享 skill 只需复制 `f-sync/` 目录，对方运行 `install.sh` 创建自己的配置。

## 安装

```bash
bash skills/f-sync/install.sh
```

交互式输入：飞书账号、本地目录、云盘文件夹 token、冲突策略、轮询间隔。

## 使用

| 命令 | 说明 |
|------|------|
| `bash skills/f-sync/sync.sh` | 手动执行一次同步 |
| `bash skills/f-sync/sync-loop.sh` | 前台轮询模式（调试用） |
| `bash skills/f-sync/uninstall.sh` | 卸载 systemd timer + 可选删配置 |
| `systemctl --user status f-sync.service` | 查看服务状态 |
| `journalctl --user -u f-sync.service -f` | 查看同步日志 |

## 配置格式

```json
{
  "jobs": [
    {
      "name": "work-docs",
      "local_dir": "/mnt/c/Users/franc/Documents/work",
      "folder_token": "NHjlfz0hflyQ2hdWi4RcRrQsnPd",
      "on_conflict": "local-wins",
      "interval_seconds": 30
    }
  ],
  "lark_config_dir": "~/.lark-cli-<account>"
}
```

支持多 job，每个 job 独立目录、独立 token、独立冲突策略。间隔取所有 job 最短值。

## 冲突策略

| 策略 | 行为 |
|------|------|
| `local-wins` | 本地版本覆盖远程 |
| `remote-wins` | 远程版本覆盖本地（默认） |
| `keep-both` | 双方都保留，重命名冲突文件 |

## 已知限制

- 只同步 type=file 的普通文件，在线文档（docx/sheet/bitable 等）跳过
- 空文件上传失败（飞书 API 拒收 0 字节文件）
- 空目录不会同步
- 不用 `--quick`（mtime 误报，已验证）
- WSL 监听 Windows 目录（/mnt/c/...）inotify 无效，只能用轮询
- 多机器同时跑：`--on-conflict` 决定冲突行为，无锁机制

## Windows 路径

WSL 中 Windows 目录: `/mnt/c/Users/用户名/...`

```bash
# 查看 Windows 用户名
ls /mnt/c/Users/
```

## 架构

```
systemd user service（loop 模式）
  └─ sync-loop.sh
       └─ sync.py
            └─ 逐 job 执行 lark-cli drive +sync (exact 模式)
            └─ sleep N 秒 → 重复
```

不使用 inotify/watchdog，因为 WSL2 的 9p 协议不传递 Windows 文件系统事件。

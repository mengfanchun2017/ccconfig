---
name: Claude Code 工作目录漂移问题
description: Claude Code session 的 cwd 会因 cd 命令漂移，导致相对路径失效。已确认：init-skill.sh 依赖 cd 切换，SCRIPT_DIR 也有问题。
type: feedback
originSessionId: archi
---

## 问题描述

Claude Code session 的工作目录（CWD）会因 Bash 命令中的 `cd` 而漂移，导致后续命令在错误目录执行。

## 已确认案例

1. **init-skill.sh**：脚本内 `cd "$SCRIPT_DIR"` 切换目录，Bash 工具执行后 session cwd 变为目标目录
2. **sync-pullff.sh**：执行 `cd "$REPO_DIR"` 后 session cwd 变为 ccconfig 目录

## 影响

- 后续 `git diff sync-pullff.sh` 报错 `Could not access 'sync-pullff.sh'`（因为 cwd 已变）
- 相对路径全部失效

## 解决方向

1. **避免 cd**：所有脚本不主动 cd，改用绝对路径或 `git -C <dir>`
2. **Bash 命令前重置 cwd**：在复杂命令前加 `cd /home/francis/git &&` 确保目录正确
3. **使用绝对路径引用脚本**：不用相对路径

## 已更新的脚本（2026-05-15）

- sync-pullff.sh：pullff 后同步 skills（已在末尾）
- sync-monitor.sh：auto-sync 后同步 skills（已在 pull 成功后）

## 待修复

- init-skill.sh：改用 `git -C` 或绝对路径，避免 cd
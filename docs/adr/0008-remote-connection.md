# 0008. Remote 远程连接方案

> **Status**: ✅ Accepted
> **日期**: 2026-07-31
> **关联**: `option-remote/`
> **模板**: MADR 4.0 极简版
> **备注**: 原 `adr/001-remote-connection.md`（3 位编号，误放仓库根 `adr/`），2026-08-02 迁回 `docs/adr/` 统一目录，编号改 4 位 0008。见 [[0010-adr-directory-location]](0010-adr-directory-location.md)。

## Context and Problem Statement

需要在笔记本/手机上远程连入台式机 WSL2 的 tmux `claude` 会话。台式机 Windows 已安装 Tailscale 并登录，WSL2 为 mirrored 网络模式。

## Decision

### 1. mirrord 网络模式自动检测

WSL2 `.wslconfig` 中 `networkingMode=mirrored` 下 WSL/Windows 共享网络栈。端口转发（portproxy）反而冲突。`init.sh` 检测 `.wslconfig` 自动跳过 `deploy.sh` 和 `tmux-portforward.ps1`。

### 2. SSH 预检跳过 sudo

`do_server()` / `do_all()` 先检查 `ssh.socket`/`ssh.service` 状态。已运行则跳过 `tmux-sshd.sh`，避免 clean 机器才有必要的 sudo 提示打断流程。

### 3. `--run` 一键入口

`init.sh --run` 为推荐用法：SSH 预检 → mirrored 检测 → Tailscale 检查 → 输出连接命令。无交互。

### 4. tmux auto-attach

`.bashrc` 判断 `SSH_TTY` + `!$TMUX`，SSH 登录自动 attach 或创建 `claude` 会话。

### 5. 客户端选择

| 客户端 | 验证 | 备注 |
|--------|------|------|
| Termius（手机） | ✅ 实测通过 | iOS/Android 均可用 |
| Windows Terminal | ✅ 理论上行 | 需装 Tailscale |
| 原生 SSH | ✅ 理论上行 | `ssh user@ts-ip -p 2222` |

## Consequences

### Positive

- ✅ 手机 Termius 实测直连 tmux claude 会话
- ✅ mirrored 模式自动跳过 portproxy 冲突
- ✅ 无交互一键入口

### Negative / Risks

- ❌ 非 mirrored 网络模式仍走 portproxy + 计划任务路径，`init.sh` 自动 fallback
- ⚠️ Tailscale 未登录时 SSH 就绪但远程不可达（status 显 ⚠）

## Implementation

- `option-remote/init.sh` — 入口重写，新增 --run + mirrored 检测 + SSH 预检
- `option-remote/server/tmux-sshd.sh` — SSH + tmux 安装（未改）
- `option-remote/server/tmux-portforward.ps1` — 端口转发（未改）
- `option-remote/server/ts-setup.ps1` — Tailscale 安装（未改）
- `option-remote/deploy.sh` — 部署脚本（未改）

## Related Decisions

- [[0010-adr-directory-location]](0010-adr-directory-location.md) — ADR 目录位置约定

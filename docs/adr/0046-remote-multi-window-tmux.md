# 0046. 远程多窗口连接方案 — Tailscale SSH + tmux（`new -A -s` 复用 session）+ Windows PowerShell 客户端封装

> **Status**: ✅ Accepted
> **日期**: 2026-10-14
> **关联**: Tailscale SSH；tmux；Windows PowerShell / Windows Terminal；远端 `~/git/ccconfig`
> **模板**: MADR 4.0 极简版

## Context and Problem Statement

从 B 机（Windows）通过 Tailscale SSH 连到 A 机（家庭主机）时，连接只有一个窗口，无法并行开多个终端干不同的活。起因是把「连接数受限」当成 ssh 的限制，实际 ssh/Tailscale SSH 不限连接数，是客户端只开了一个窗口。

两个诉求并存：

1. **多窗口并行**：A 机上一块屏跑 Claude Code、一块屏跑构建/日志，互不干扰。
2. **断线不丢**：网络抖动或合盖休眠后重连，希望回到原来的窗口布局，而不是从零重来。

B 机的连接入口是一个封装好的 PowerShell 命令（Windows Terminal 新建连接配置里粘贴），需要把「单窗口」替换为「tmux 复用」。

## Decision Drivers

- **D1 多窗口 + 分屏**：一个连接内既能开多窗口，也能左右/上下分屏
- **D2 断线可恢复**：客户端掉线，远端会话与进程继续跑，重连即回
- **D3 各连接独立**：多个连接配置互不看到对方的屏（避免「两个窗口显示相同」）
- **D4 零额外服务**：不引入 mosh/第三方多路复用，只用 ssh + tmux（A 机 apt 可得）
- **D5 一键直入**：连接配置里一条命令直落 tmux + 起始目录，不让用户每次手敲

## Considered Options

1. **方案 A: 多开终端窗口重连** — 每个 tab 各自 `ssh`。Pros: 零依赖。Cons: 掉线全丢；「两个窗口显示相同」在个别终端 profile 下会踩（同一 session 复用）；不满足 D2
2. **方案 B: tmux（选定）** — `tmux new -A -s <name> -c <dir>` 接入 A 机。Pros: 一个连接内窗口/分屏任意开；detach 后进程存活，重连回同一堆窗口（`-A` 有则接、无则建）；不同 `-s` 名 = 独立 session，天然满足 D3。Cons: 需 A 机装 tmux；`%`/`"` 分屏键受输入法影响（见 Notes）
3. **方案 C: mosh** — Pros: 抗高延迟/漫游。Cons: 额外装 mosh server、UDP 端口、与 Tailscale 叠加排查成本高，收益对本场景（同局域网/同 tailnet）不明显

## Decision

选 **方案 B：tmux**。B 机连接配置的 command 字段：

```
"C:\Users\<user>\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe" -NoExit -Command "& ssh -p <port> <user>@<A-host-tailscale-ip> -t ""tmux new -A -s main -c ~/git/ccconfig"""
```

关键参数：

- `ssh -p <port> <user>@<A-host> -t ...` — `-t` 强制分配 TTY，tmux 交互必需
- `tmux new -A -s main` — `new -A`：session 不存在则建、存在则接（重连回同一堆窗口）；`-s main`：session 名
- `-c ~/git/ccconfig` — **建 session 时的起始目录，仅新建生效**；重接沿用原目录

**多连接独立**：每个连接配置用**不同 session 名**，即得到互不可见的独立屏：

| 连接 | 远端命令 |
|------|---------|
| 配置 1 | `tmux new -A -s main -c ~/git/ccconfig` |
| 配置 2 | `tmux new -A -s main2 -c ~/git/ccconfig` |
| 配置 3 | `tmux new -A -s main3 -c ~/git/ccconfig` |

**连接内的窗口/分屏**（接上后在 tmux 内）：

```
Ctrl-b c    新窗口
Ctrl-b %    左右分屏
Ctrl-b "    上下分屏
Ctrl-b n/p  切窗口
Ctrl-b d    暂离（detach，进程继续跑）
tmux a -t <name>   重新接入指定 session
```

**推荐的分屏键重绑**（规避输入法吃 `%` `"`，写入 `~/.tmux.conf` 后 `tmux source-file ~/.tmux.conf`）：

```tmux
unbind '"'
unbind %
bind | split-window -h    # Ctrl-b 再按 |
bind - split-window -v    # Ctrl-b 再按 -
```

## Consequences

- ✅ 一个连接内窗口/分屏任意开；多连接用不同 `-s` 名即各自独立
- ✅ 掉线后远端 session 与进程存活，`tmux a -t <name>` 或重连配置直接回到原布局（满足 D2/D3）
- ✅ 纯 ssh + tmux，A 机 `sudo apt install tmux` 一步可得（满足 D4）
- ✅ 连接配置一条命令直入 tmux + 工作目录（满足 D5）
- ❌ 依赖 A 机装有 tmux（旧机器可能需补装）
- ⚠️ 分屏键 `%` `"` 在中文输入法下会被拦截——按前须先把 `Ctrl+b` 松开、切英文输入法；保底用命令模式 `Ctrl+b :` → `splitw -h` / `splitw -v`；或按上文重绑 `|` `-` 永久规避
- ⚠️ `-c <dir>` 只在新建 session 时生效，重接不回落到该目录（要改目录进去 `cd` 或用 tmux `default-path`）

## Implementation

- A 机：确认 `tmux -V` 存在，缺则 `sudo apt install tmux`（手动执行）
- B 机：Windows Terminal 新建连接配置，command 粘贴上文（把 `<user>` / `<port>` / `<A-host-tailscale-ip>` 替换为真实值，**真实值不入公开仓库**）
- 可选：写 `~/.tmux.conf` 重绑分屏键并 source

## Related Decisions

- `ADR-0014`（文件 `0014-tailscale-jump-server.md`）— Tailscale 跳板机部署，本 ADR 的 SSH 通路基础
- `ADR-0008`（文件 `0008-remote-connection.md`）— Remote 远程连接方案，同属远程接入域
- `ADR-0040`（文件 `0040-remote-file-transfer-channels.md`）/ `ADR-0044`（文件 `0044-agent-smb-file-bridge.md`）— 远程文件通道；本 ADR 管远程**交互终端**通道，互补

## Notes

- **`%` 分屏失败排查口诀**：① `Ctrl+b` 按完**松开**再单独按 `Shift+5`（不是三键同按）；② 中文输入法会吞掉 `%`，切英文；③ 保底 `Ctrl+b :` 看命令行能否弹出 → 弹出即 prefix 正常，问题在该键；④ 换 `"` 测上下分屏，能分则是 `%` 键坑；⑤ 一劳永逸重绑 `|` `-`
- 保底命令（绕开分屏键）：`Ctrl+b :` 输入 `splitw -h`（左右）/ `splitw -v`（上下）
- 连接命令含真实 IP/端口/用户名，属私有配置；公开仓库内一律用占位符，真实值存 `ccprivate/`

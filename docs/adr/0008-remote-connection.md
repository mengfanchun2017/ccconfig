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

### 5. 客户端选择（按设备拆分）

| 设备 | 客户端 | 验证 | 备注 |
|------|--------|------|------|
| 小米 Pad | Termius | ✅ 实测功能全 OK（2026-10-05） | 终端类型须设为 `xterm`，不要用 `linux`，否则按键/显示异常 |
| 小米 Pad | Termux | ✅ 使用中 | 备用方案 |
| 小米 14 / 其他手机 | Termius | ✅ 实测工作完美（2026-10-05） | iOS/Android 均可 |
| Windows | Windows Terminal | ✅ 理论上行 | 需装 Tailscale |
| 任意 | 原生 SSH | ✅ 理论上行 | `ssh user@ts-ip -p 2222` |

> 关键：Termius 终端类型（Terminal type）默认 `linux` 在小米 Pad 有兼容问题；改为 `xterm` 后所有功能正常。Pad 与手机可统一用 Termius。

### 6. 移动端进入指定 session：处理中退出用 `/exit` 回 fleet view + 手动点击；空框等待时 `←` 可切（实体键盘下处理中不可切）

实测（小米 Pad + Termius 设 `xterm`，2026-10-05）：方向键/`←` 均正常，所有功能 OK。此前（2026-10-04，Termius 默认 `linux` 终端类型）`←` 切 fleet/agent view 不可靠的根因是终端类型；处理中 `←` 不可切疑似与实体键盘相关：

- **D1** Termius 默认终端类型 `linux` 在小米 Pad 上按键序列不标准，`←` 无法稳定触发 view 切换；改为 `xterm` 后修复
- **D2** Claude Code 的 `←` 切 view 有前置门槛：仅空输入框触发；v2.1.218+ 防误触要求删除/历史操作后隔 2s 二次确认
- **D3** `←` 仅在等待输入时可切 fleet view；处理中（thinking/streaming）按 `←` 到不了 fleet view —— 疑似与 Pad **实体键盘**相关（外接/键盘保护套方向键触发，软键盘场景此 bug 不显）

统一路径（保持可用）：**处理中要退出用 `/exit`** 退出当前 session 回 fleet view → **手动点击屏幕上目标 session 位置**进入。全文本命令 + 点击，无方向键依赖，跨终端（含软键盘、含实体键盘）一致。等待输入且空框时 `←` 快捷可切，处理中不适用。

### 7. 多发行版多端口

Windows 同一宿主机可同时跑多个 WSL 发行版。tailscale 跑在 Windows 侧（mirrored 模式），所有发行版共享同一条 tailscale IP。给不同用户隔离环境 = 各发行版 sshd 绑**不同端口**，同一 `ts-ip` 按端口落不同发行版：

```
Pad ──ssh p=2222 ──▶ WSL claude（用户 A）
手机 ──ssh p=2223 ──▶ WSL dsh   （用户 B）
```

`tmux-sshd.sh` 端口参数化：`bash tmux-sshd.sh 2223` 或 `init.sh server --port 2223`。init.sh 的 `--port` 透传给 tmux-sshd.sh；`get_ssh_port()` 统一读端口（用户指定优先，否则 sshd_config）。status/提示均用实际端口。

### 8. 集成 maintain（查看/修改端口）

远程能力从「直接跑 option-remote 脚本」升级为「maintain 运维菜单 8 远程」：

- **8A 查看 SSH 状态/端口** → `init.sh --status`（status.sh 的 check_option_components 本已调它显示端口，菜单再给独立入口）
- **8B 设置 SSH 端口** → `init.sh set-port <N>`（落盘 sshd_config + `systemctl restart ssh`，幂等）。parse_port 支持 `--port`/`--set-port` 两种 flag + 位置式纯数字（`set-port 2223`），菜单 `ask_run` 追加为位置参数
- **tmux 覆盖**：在 `lib/deps-check.sh` 已含（`tmux|tmux -V`、`ssh|ssh -V`），`maintain.sh deps` 即覆盖。不在 `update.sh` 工具升级链——tmux 是 apt 系统包，不属版本化工具升级

## Consequences

### Positive

- ✅ Pad（Termius 设 `xterm`）与手机（Termius）统一客户端，均实测直连 tmux claude 会话，功能全 OK
- ✅ `xterm` 终端类型下方向键/`←` 正常（等待输入时空框可切；处理中 `←` 不可切疑似实体键盘所致）；处理中退出统一走 `/exit` + 点击
- ✅ mirrored 模式自动跳过 portproxy 冲突
- ✅ 无交互一键入口

### Negative / Risks

- ❌ 非 mirrored 网络模式仍走 portproxy + 计划任务路径，`init.sh` 自动 fallback
- ⚠️ Tailscale 未登录时 SSH 就绪但远程不可达（status 显 ⚠）

## Implementation

- `option-remote/init.sh` — 入口重写，新增 --run + mirrored 检测 + SSH 预检 + `--port N` 透传 + `set-port` 动作（落盘+重启）
- `option-remote/server/tmux-sshd.sh` — SSH + tmux 安装，端口参数化（`$1` 缺省 2222）
- `lib/menu-data-maintain.sh` — 新增分类 8 远程（8A 查看 / 8B 设置端口）
- `option-remote/server/tmux-portforward.ps1` — 端口转发（未改）
- `option-remote/server/ts-setup.ps1` — Tailscale 安装（未改）
- `option-remote/deploy.sh` — 部署脚本（未改）

## Related Decisions

- [[0010-adr-directory-location]](0010-adr-directory-location.md) — ADR 目录位置约定

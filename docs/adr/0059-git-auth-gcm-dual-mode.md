# 0059. GitHub 认证改为 Windows GCM 为主 + PAT 备选（双模式）

> **Status**: ✅ Accepted
> **日期**: 2026-11-17
> **关联**: `lib/git-auth.sh`、`maintain.sh`（菜单 2C）、`lib/status.sh`、`lib/monitor.sh`、`lib/init-ubuntu.sh`、`init-bootstrap.sh`
> **模板**: MADR 4.0 极简版
> **取代**: 扩展 [0011](0011-git-auth-fine-grained-pat.md) 的「统一走 fine-grained PAT」；与 [0023](0023-pat-expiry-on-failure-only.md) 的 on-failure-only 原则并存

## Context and Problem Statement

ccconfig 运行在 WSL2，git 认证此前统一走 fine-grained PAT（`gh auth login`，token 存 `~/.config/gh/hosts.yml`）。痛点：

1. **token 在 WSL 磁盘上是明文文件**，随 auto-sync/备份有泄漏面。
2. **PAT 有过期**，过期后 push 失败，需人工续期（`bin/refresh-gh-auth.sh`）。
3. **Windows 侧已装 Git for Windows（自带 GCM）**，凭据由 Windows 凭据管理器用 DPAPI 加密保管，WSL 磁盘零密钥 —— 这套能力一直没被用上。

2026-11 用户把认证统一改为「调用 Windows 自己的加密服务」= Windows GCM（`git-credential-manager.exe`），WSL 通过 interop 借用。

## Decision Drivers

- **D1 密钥落盘**：WSL 磁盘上的明文凭据越少越好。
- **D2 换机/多机一致**：仓库要能在任意 Windows 机上跑，路径不能写死。
- **D3 不过期**：认证方式尽量无 TTL，减少人工续期。
- **D4 状态可判**：`status`/`monitor` 能离线判断认证是否可用，不卡菜单。

## Considered Options

1. **纯 PAT（现状）** — 简单、跨平台的；但 token 明文落 WSL、有过期。
2. **纯 GCM** — 密钥只在 Windows、无过期；但仅限 WSL（依赖 `/mnt/c`），非 WSL 环境不可用。
3. **GCM 为主 + PAT 备选（选定）** — 任一可用即算认证通过；WSL 用 GCM，非 WSL/无 GCM 时回落 PAT。

## Decision

认证实现收口到 `lib/git-auth.sh` 单点：**GCM 优先，PAT 备选，任一可用即 OK**。

- GCM：`_find_gcm_path` 定位 `git-credential-manager.exe`（现有 gitconfig helper → 遍历 `/mnt/c/Users/*/` 排除模板目录 → `/mnt/c/Program Files/Git/...`），写 `credential.https://github.com.helper = !"<路径>"`。
- PAT：沿用 `gh auth login`，`bin/refresh-gh-auth.sh` 续期。
- 判定：`_gcm_status` 返回 `ok` / `not_configured` / `bad_path`（helper 配了但 exe 不可达）；`_pat_status` 返回 `logged_in` / `not_logged_in`。
- `status`/`monitor` 只报配置态（**刻意不联网**），联网实测只走 `verify`（直连 + 代理重试）。

为什么 GCM 是主：密钥由 Windows DPAPI 保管、WSL 零明文、无过期。为什么保留 PAT：非 WSL 环境（原生 Linux/macOS）与无 Git for Windows 的机器仍需可用。

## Consequences

- ✅ WSL 下凭据不再落 WSL 磁盘，且无过期。
- ✅ 认证判定单点（`git-auth.sh`），status/monitor/maintain 同源，不再各抄一份。
- ❌ GCM 仅限 WSL，`_find_gcm_path` 依赖 `/mnt/c` 挂载。
- ⚠️ `gh auth setup-git` 会把 GCM helper 覆盖回 gh —— 已在 `lib/init-ubuntu.sh` 加「GCM 已配则跳过」；认证配置只允许经 `git-auth.sh` 写入。
- ⚠️ gitconfig helper 值必须带引号 `!"<路径>"`：路径含空格（`/mnt/c/Program Files/...` 或用户名含空格）不引号会被 shell 拆词（实测 `fake: not found`）。

## Implementation

- `lib/git-auth.sh`：GCM/PAT 双模式实现 + 交互菜单 + `status`/`gcm`/`pat`/`verify`/`check` 子命令。
- `maintain.sh` 菜单 2C「GitHub 认证管理」、子命令 `git-auth`。
- `lib/status.sh` `check_git_auth`、`lib/monitor.sh` 认证状态段 source 其函数。
- `tests/test-git-auth.sh`：脱敏 / 路径发现 / 三态 / 入口守卫。

## Related Decisions

- [0011](0011-git-auth-fine-grained-pat.md) — 原 PAT 统一决策，本 ADR 扩展为双模式。
- [0023](0023-pat-expiry-on-failure-only.md) — on-failure-only 过期处理，仍适用于 PAT 模式。

## Notes

- `_gcm_status` 曾只看「helper 非空 + 系统找得到 gcm.exe」→ 指向已卸载 exe 的坏 helper 被误报 ok；已改为校验 helper 值本身可达。
- 代理探测复用 `lib/net.sh` 的 `net_gh_proxy`（env → 7897/7890），git-auth.sh 后续可统一走该入口。

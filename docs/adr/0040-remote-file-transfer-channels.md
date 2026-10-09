# 0040. 远程服务器文件传输通道选型

> **Status**: ✅ Accepted
> **日期**: 2026-10-07
> **关联**: `option-remote/`（[0008-remote-connection](0008-remote-connection.md)）
> **模板**: MADR 4.0 极简版
> **目的**: 确定手机/平板收到的文件（微信/邮件附件、大文件）如何进入远程 Claude Code 服务器 WSL 被 agent 处理

## Context and Problem Statement

家里高配台式机 24h 跑 Claude Code服务器（WSL2 + tmux + Tailscale，手机 Termius 接入，见 0008）。核心痛点：**手机收到的文件如何传进远程 agent 手里**，尤其是：

- 微信/邮件小文件（发票、PDF、图片）→ 需进飞书链路
- 手机/好友收到的大文件（>20MB，如视频、zip、安装包）→ 飞书 API 有上传上限
- 好友跨账号传文件（Taildrop 只限自己设备）→ 需另寻通道

要求：P2P 不碰云端、大小尽量无上限、手机操作简单（分享即传）、WSL agent 能直接读取处理。

## Decision Drivers

- 飞书已配好 lark-cli，文档链路成熟（下载/改名/上传/追加已验证）
- 但飞书 drive 上传大小**严格 20MB**（实测 lark-cli 19MB ✓ / 21MB ✗ code 1061043）
- Windows Tailscale 已装（非 WSL 内），WSL 为 mirrored 模式共享 host 网络栈
- 需求以手机为中心：微信/邮件收文件 → 分享到目标机器 → WSL 处理
- 避免新增基础设施（不引入网盘 daemon、不建 watcher 服务）

## Considered Options

### A — Taildrop 直落「下载」文件夹 + WSL 读 `/mnt`（选定）

手机 Tailscale app 分享文件 → Taildrop P2P 直传 → Windows **GUI 自动落「下载」已知文件夹** → WSL 经 `/mnt/<drive>/.../Downloads/` 读取处理。

**实测验证**（2026-10-06 ~ 2026-10-09）：
- WSL ↔ Windows `/mnt/c/Users/<win-user>/Downloads/`、`Desktop/` 双向读写 ✓
- Taildrop 无文件大小限制（free plan 官方确认，支持断点续传）
- 全链路 P2P 加密，不经云端

**关键事实**：
- Taildrop **仅在发送端选目标设备，没有目录选择器**——落点完全由接收端默认目录决定
- **Windows 默认落点 = 「下载」已知文件夹**（`C:\Users\<win-user>\Downloads`，本地可被重定向，见下）。此点已由官方 changelog 更正：Windows 收件目录**早前是桌面，后改为 Downloads**（issue #5934 已 Closed）
- **落点 = 注册表 known-folder「下载」指向的目录**，未必在 C 盘。若用户把「下载」重定向到别的盘（如 `D:\Downloads`），Taildrop 文件就落在那里——**找文件先查注册表 known-folder，别默认 `C:\...\Downloads`**
- **Windows GUI 自动收件**，无需手动 `tailscale file get`；`tailscale file get` 也能把 inbox 里滞留文件搬到任意目录
- **两个接收者会各存一份**：GUI 自动收件（→ Downloads 已知文件夹）与手动 `file get` 循环（→ 指定目录）若同时存在，同一封邮件各落一份，表现为「传一个出现两个」——**是接收端重复，不是手机发了两份**。默认只留 GUI 自动收件即可
- **Windows 无法改默认落点**：无 GUI 设置、无公开配置项（Linux 有 systemd 可改，Windows 无）
- 不建 Inbox/watcher：A 方案直接读「下载」目录，少一层搬运

**适用**：自己账号设备间传（手机→自己台式机）。**不适用**：好友（不同 Tailscale 账号）传——Taildrop 只限自己的设备。

### B — 飞书文件（20MB 内）

手机把文件发到自己飞书 → 远程 lark-cli 下载处理 → 结果回传追加。

**实测验证**（2026-10-06）：
- 下载：doc 内附件必须用 `drive +preview --type source_file`（`+download` 对附件 403）
- 改名、上传、`--command append` 追加 `<figure><source/></figure>` 到文档底部，全通过 ✓
- zip 等二进制同通道可用，字节完整

**限制**：>20MB 直接 1061043 失败；lark-cli 声称自动 multipart 实际不生效。**只适合小文件**。

### C — SSH/SCP 直推（好友/大文件）

- 自己/好友电脑：Termius / `scp file user@host:~/inbox/` 直推到 WSL
- 无大小限制，跨账号可用
- 缺点：手机端没有方便的「分享 → scp」UI，需手动敲命令；好友需有 SSH 访问权

### D — Tailscale Serve 上传页（已放弃）

在 Windows/WSL 开 HTTP 上传页让好友浏览器传。需额外维护服务、端口暴露面，复杂度高于收益，先不做。

## Decision

选 **A（Taildrop 直落「下载」文件夹）为主**，B（飞书）为小文件补充，C（SSH）为好友跨账号备用。

- 手机日常小文件 → **A 或 B**：A 更快（P2P 直落「下载」，WSL 直接读），B 适合已走飞书流程的文档
- 自己大文件 → **A**（Taildrop 无上限）
- 好友传文件 → **C**（scp 直推 / 授权 SSH）
- >20MB 一律**不走飞书**，走 A 或 C

**找文件固定动作**：用户说「通过 Tailscale 传了个文件，去找」时，**默认去「下载」已知文件夹**（先读注册表 known-folder `{374DE290-123F-4565-9164-39C4925E467B}` 拿真实路径，本机为 `D:\Downloads`）；**不要**默认 `C:\Users\<win-user>\Desktop`（旧版本行为）、也**不要**默认 `C:\Users\<win-user>\Downloads`（可能被重定向到别的盘）。只在 Downloads 找不到时再看桌面。

## Consequences

### Positive

- ✅ Taildrop P2P 加密直传，无云端、无大小限制、断点续传
- ✅ WSL 直接读「下载」目录（`/mnt/<drive>/.../Downloads`），agent 无需额外通道
- ✅ 手机操作 = 文件分享 → 选设备，两秒完成
- ✅ 飞书链路已跑通（20MB 内），作为文档工作流自然延伸

### Negative / Risks

- ❌ Taildrop 仅限自己账号设备，好友需要 C 通道
- ⚠️ Windows 落点固定在「下载」已知文件夹，无法配置；且该文件夹可能被重定向到非 C 盘，找文件需先解析 known-folder
- ⚠️ GUI 自动收件与手动 `file get` 并存会产生重复副本——只保留其一
- ⚠️ 手机 Taildrop 需与台式机同账号登录 Tailscale
- ⚠️ iOS 收件不支持断点续传（发送侧 OK）
- ⚠️ 移动网络下行时 P2P 走 NAT 穿透，极慢场景可能兜底 relay（Tailscale DERP）

## Security Considerations

- Taildrop 流量 WireGuard 加密，仅发送/接收两端可达
- 不暴露任何公网端口（P2P 出站）
- `~/inbox` 类共享目录未建——避免弱 ACL 目录
- 桌面目录对 WSL 只读即可满足处理需求，无需写权限

## Notes

- Taildrop 默认落点对照：Windows=「下载」已知文件夹、macOS=Downloads、Android=Downloads、iOS=App 沙盒（官方 changelog 明确 Windows 已由 Desktop 改为 Downloads）
- Windows GUI 客户端**自动收件**，写入「下载」known-folder（受注册表重定向影响）；`tailscale file get [--loop] [--wait] <dir>` 可手动/循环收件到指定目录（`<dir>` 需 Windows 路径，如 `C:\Users\<win-user>\Desktop`）
- 重复副本机制：GUI 自动收件 + 手动 `file get` 循环同时存在 → 同一文件各存一份
- Taildrop 是 alpha 功能，需在 Tailscale 管理台 Settings → General → **Send Files** 开启（一次性，全网络生效）
- 飞书上传 20MB 边界、附件下载 preview 通道、上传删除带 `--params '{"type":"file"}'` 等坑已固化进 ffeishu skill 的 `references/lark-cli-cheatsheet.md`
- 收件验证：Windows 系统托盘 Tailscale 收件提示；或 `tailscale file get` 手动收

## Related

- [0008-remote-connection](0008-remote-connection.md) — 远程连接方案（tmux + Termius + 多端口）
- [Taildrop | Tailscale Docs](https://tailscale.com/docs/features/taildrop)
- [Taildrop 默认落点 issue #5934](https://github.com/tailscale/tailscale/issues/5934)
- [ADG 0014/0016/0017 — Tailscale 基础设施](0014-tailscale-jump-server.md)
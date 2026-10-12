# 0044. agent 跨机取件通道 — SMB C$ + tsxfer 专用账户（反向拉取 + 回写）

> **Status**: ✅ Accepted
> **日期**: 2026-10-12
> **关联**: 补充 [0040-remote-file-transfer-channels](0040-remote-file-transfer-channels.md) 的 agent 主动方向；落地候选 `option-filepull/`（待定，见 Implementation）
> **模板**: MADR 4.0 极简版
> **目的**: agent（i7 WSL）如何**主动**从任意 ssh 来源机拉取文件并回写产物，实现用户一句话（「分析 redmipro 的 C:\x.zip」）全链路自动化

## Context and Problem Statement

0040 解决的是**被动收件**方向（手机 Taildrop → i7「下载」文件夹）。新痛点是反方向：**agent 在 i7 WSL 里，用户在任意机器 ssh 进来丢一句「分析 redmipro 的 C:\skill\x.zip」——agent 必须自己把文件拉过来、分析完再把产物写回去**，全程用户零操作。

2026-10-12 在 redmipro → i7 链路上实测硬约束：

- Taildrop **只有发送没有拉取 API**（`tailscale file cp` 只能 send，`file get` 只收本机 inbox）——通道死
- redmipro 22/2222/5985 全关（无 sshd、无 Tailscale SSH——且 Tailscale SSH 服务端本就不支持 Windows）——反向 ssh 死
- B（i7 WSL）`~/.ssh` 无密钥；B 的 sudo 要密码（apt 装包会卡交互）——现装依赖受限
- redmipro **445(SMB) 开**且经 tailnet 可达——唯一活口
- 用户只记得 4 位 Windows Hello PIN，不记得密码——**PIN 是 TPM 绑定的本机凭证，网络认证（SMB）不收**，无绕法
- 反向 scp push（A 端粘一条命令）可用但用户明确嫌麻烦，只作兜底

## Decision Drivers

- 目标 UX：用户一句话 → agent 自动 拉取 → 分析 → 回写，零手工命令
- A（来源机）侧配置尽量一次搞定、之后永久零操作
- B 侧零安装（sudo 有密码交互，apt 路不通）
- 密码不能依赖用户记忆（用户只有 PIN）
- 读写双向（回写分析产物到同目录）
- 凭据随 ccprivate 跨机同步，新机 bootstrap 即用

## Considered Options

### 1 — SMB `C$` + `tsxfer` 专用本地账户（选定）

A 侧一次性三命令（管理员 PowerShell）：建 `tsxfer` 本地账户（随机强密码）→ 加 Administrators 组 → 注册表开 `LocalAccountTokenFilterPolicy=1`（否则远程 UAC 把本地账户网络登录降权，`C$` 报拒绝访问）。
B 侧：WSL 直调 Windows 内置 SMB 客户端（`powershell.exe` 全路径），`cmdkey` 缓存凭据后走 `\\<ts-ip>\C$\<任意路径>` 读写。

**实测**（2026-10-12 redmipro↔i7 端到端）：拉 zip ✓ → 解压分析 ✓ → 分析 .md 写回同目录 ✓。

### 2 — A 装 OpenSSH Server + B 部署 key（备选，SMB 受阻时）

无密码落盘、更标准；但每台新客户端机都要装服务 + 贴公钥 + 修 administrators_authorized_keys ACL（Windows 坑多），A 侧摩擦高于方案 1。

### 3 — Taildrop / 反向 Tailscale SSH（否决）

Taildrop 无 pull API；Tailscale SSH 服务端不支持 Windows。

### 4 — 手动 scp push（兜底保留）

A 端粘一条 `scp -P 2222` 命令直推 `~/inbox/`。仅当某台机既没配 SMB 也没配 sshd 时由 agent 打印命令让用户粘。

## Decision

采用 **方案 1**。完整流程：

**A 侧一次性命令**（管理员 PowerShell，UAC 可用 PIN 过）：

```powershell
net user tsxfer <随机14位密码> /add
net localgroup administrators tsxfer /add
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LocalAccountTokenFilterPolicy /t REG_DWORD /d 1 /f
```

**凭据落盘**：`ccprivate/conf/smb.json`（`{主机名: {ip, user, pass, share}}`，私有仓随 git 同步各机）。

**B 侧操作路径**（agent 执行）：

- SMB 客户端 = `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`（Claude Bash 的 PATH 无 Windows interop，必须全路径）
- 首次：`cmdkey /add:<ip> /user:tsxfer /pass:<pw>` 缓存凭据
- 拉取：`Copy-Item '\\<ip>\C$\<src>' '\\wsl.localhost\<distro>\home\<user>\inbox\'`
- 回写：反向 `Copy-Item`；落点统一 `~/inbox/`（agent 侧中转目录）
- 脚本内先 `[Console]::OutputEncoding=[Text.Encoding]::UTF8`（PS 输出默认 GBK 乱码）

**一句话指令协议**（用户 → agent，写入 memory）：

| 用户说 | agent 理解 |
|---|---|
| `把 C:\x.zip tailscale 过来` | 文件在当前 ssh 来源机 → 拉到 `~/inbox/` → 后续处理 |
| `分析 redmipro 的 C:\x.zip` | 设备名指定来源 → 同上 |
| `分析 /home/...`、`/mnt/...` | B 本地文件 → 直接处理 |

来源机识别：指令带设备名 → `tailscale.exe status` 解析 IP；否则读进程父链 `SSH_CONNECTION` **且**与 `ss :2222 ESTAB` 实时对账（父链值会因 session resume 过期——实测曾指旧会话的 xiaomi-pad）；对不上反问。

## Consequences

### Positive

- ✅ 用户一句话全链路自动化，读写双向（拉文件 + 回写产物）
- ✅ A 侧一次 30 秒配置，永久零操作；B 侧零安装
- ✅ 密码随机生成、用户零记忆；凭据随 ccprivate 跨机同步
- ✅ 任意路径（`C$` 管理员共享覆盖全盘），不受共享目录粒度限制

### Negative / Risks

- ❌ tsxfer 是**管理员**账户且开了 `LocalAccountTokenFilterPolicy=1` —— 网络侧拿到该密码 = 远程完全控制
- ⚠️ 缓解：强随机密码（14 位）只存 ccprivate 私有仓；445 仅 tailnet 可达（Tailscale ACL + WireGuard 加密）；可选再把防火墙规则 scope 收窄到 `100.64.0.0/10`
- ⚠️ Windows 账户密码策略变更（域策略/复杂度要求）可能使 tsxfer 失效，表现为 `UnauthorizedAccessException`——先查账户存在性再查 token 过滤
- ⚠️ 多来源机并发 ssh 时来源识别可能歧义 → 协议要求带设备名最稳

## Security Considerations

- tsxfer 仅用于 SMB 文件通道，不交互登录；密码不进 ccconfig 公开仓
- `LocalAccountTokenFilterPolicy=1` 影响该机**所有**本地管理员的网络 token——属已知代价，环境为家庭 tailnet
- 传输本身经 WireGuard（tailnet P2P），无明文暴露

## Notes（实测坑清单）

1. **Windows Hello PIN 不能做网络认证**（SMB/网络登录只收密码）——这是建 tsxfer 的直接原因
2. **远程 UAC**：本地管理员网络登录默认拿过滤 token，`C$` 拒绝访问（连通但无权限，报 `UnauthorizedAccessException` 而非网络错误）——必须开 `LocalAccountTokenFilterPolicy`
3. Claude Bash **PATH 无 Windows interop**：`powershell.exe`/`reg.exe` 等用全路径 `/mnt/c/Windows/System32/...`
4. WSL distro 名 = `claude`（`wslpath -w` → `\\wsl.localhost\claude\...`）
5. PowerShell 输出 GBK 乱码 → 脚本首行转 UTF-8
6. Windows 下载的 zip 带 `Zone.Identifier` 伴随文件（MOTW 标记），无害
7. 本机取件落点 `~/inbox/`；Taildrop 落点仍是「下载」known-folder（0040，两层别混）

## Implementation

- [ ] `option-filepull/`（命名待定）：`init.sh` 提供 `--status`（探活 conf 中各主机 `C$`）+ `add` 交互（生成密码 → 打印 A 侧 PowerShell 块 → 探活确认）
- [ ] `init-option.sh` MENU_GROUPS 注册；`lib/status.sh` 自动发现即接入（`--quick` 跳过慢探活）
- [ ] ADR 0040 Related 互链（已做）

## Related

- [0040-remote-file-transfer-channels](0040-remote-file-transfer-channels.md) — 被动收件方向（Taildrop/飞书/scp push）
- [0008-remote-connection](0008-remote-connection.md) — 远程连接（tmux + Termius + 多端口）
- memory `remote-file-transfer-channels-20261007` — 运营细节与坑的速查版
- [Taildrop 文档](https://tailscale.com/docs/features/taildrop)（无 pull API 的依据）

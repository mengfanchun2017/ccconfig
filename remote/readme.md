# remote — 远程连接 Claude Code

> 从笔记本 SSH 连接到台式机 WSL2 中的 Claude Code tmux 会话。

## 架构

```
笔记本 ──SSH──▶ 台式机 Windows (端口转发 :2222) ──▶ WSL2 (SSH Server + tmux)
                │
                ├─ Tailscale（境外 DERP 中继，延迟高）
                └─ EasyTier（国内 P2P 中继，延迟低）
```

**两个连接方案都是 P2P 优先 + 中继兜底**：

| | Tailscale | EasyTier |
|---|---|---|
| 安装方式 | winget 自动安装 | 便携 zip 自动下载 |
| P2P 打洞 | WireGuard + STUN/ICE | WireGuard + 多协议 |
| 中继节点 | DERP（全在境外） | public.easytier.top（国内） |
| 加密 | WireGuard 端到端 | WireGuard / AES-GCM |
| 中继能否看数据 | 不能 | 不能 |
| 公共中继费用 | 免费 | 免费 |

## 目录

```
remote/
├── deploy.sh
├── readme.md
├── server/                    台式机
│   ├── tmux-sshd.sh           SSH Server + tmux（WSL）
│   ├── tmux-portforward.ps1   端口转发（管理员 PS）
│   ├── tmux.conf              tmux 配置（deploy 自动部署）
│   ├── ts-setup.ps1           Tailscale（管理员 PS）
│   └── et-setup.ps1           EasyTier（管理员 PS）
└── client/                    笔记本
    ├── terminaladd.ps1        Win Terminal 快捷入口（可选）
    ├── ts-setup.ps1           Tailscale（管理员 PS）
    └── et-setup.ps1           EasyTier（管理员 PS）
```

## 前提

两台机器的 Windows 侧 `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
```

配置后 `wsl --shutdown` 重启 WSL。

## 新服务器（台式机）操作

### 1. 拉取仓库

```bash
cd ~/git && git clone <repo-url>
# 或已有仓库: cd ~/git/ccconfig && git pull
```

### 2. 部署配置

```bash
bash ~/git/ccconfig/remote/deploy.sh server
```

自动完成：复制 .ps1 到 `C:\git\winremote\`、部署 `tmux.conf` 到 `~`。

### 3. 安装 SSH Server + tmux

```bash
bash ~/git/ccconfig/remote/server/tmux-sshd.sh
```

安装 openssh-server、配置端口 2222、配置 tmux 自动 attach。

### 4. 端口转发

Windows 管理员 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\tmux-portforward.ps1"
```

创建 0.0.0.0:2222 → WSL2:2222 转发、防火墙放行、计划任务（WSL 重启后自动更新 IP）。

### 5. 连接方案（二选一）

Windows 管理员 PowerShell：

```powershell
# EasyTier（推荐）
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\et-setup.ps1"

# Tailscale
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\ts-setup.ps1"
```

### 6. 查看本机 IP

```powershell
# EasyTier
& "C:\git\winremote\easytier\easytier-cli.exe" peer

# Tailscale
tailscale ip -4
```

记住这个 IP，客户端连接时需要。

---

## 新客户端（笔记本）操作

### 1. 拉取仓库

```bash
cd ~/git && git clone <repo-url>
```

### 2. 部署配置

```bash
bash ~/git/ccconfig/remote/deploy.sh client
```

### 3. 连接方案（和服务器选同一个）

Windows 管理员 PowerShell：

```powershell
# EasyTier（推荐）
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\et-setup.ps1"

# Tailscale
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\ts-setup.ps1"
```

### 4. 连接服务器

```bash
# EasyTier（用服务器的虚拟 IP）
ssh -p 2222 francis@10.126.126.x

# Tailscale
ssh -p 2222 francis@<服务器 Tailscale IP>
```

### 5. 可选：Win Terminal 一键连接

```powershell
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\terminaladd.ps1" -Host <服务器IP>
```

Win Terminal 下拉菜单会多出 "Claude Code" 选项。

---

## 日常使用

连上后自动进入 tmux `claude` 会话。

| 操作 | 按键 |
|------|------|
| 断开（进程保持） | `Ctrl+B` `D` |
| 重新连入 | `tmux attach -t claude` |
| 翻页模式 | `Ctrl+B` `[`（`q` 退出） |

## 常见问题

| 问题 | 检查 |
|------|------|
| tmux 鼠标滚轮不翻页 | `~/.tmux.conf` 是否有 `set -g mouse on` |
| SSH 超时 | `netsh interface portproxy show v4tov4` |
| Connection refused | WSL 内 `sudo systemctl status ssh` |
| WSL 重启后连不上 | 计划任务 "WSL SSH PortForward" 应自动更新 IP |
| easytier 被拦截 | `Get-ChildItem C:\git\winremote\easytier -File \| Unblock-File` |
| EasyTier peer 只看到自己 | 两台都运行，确认 network-name/secret 一致 |
| Tailscale 未登录 | `tailscale up` 打开浏览器登录 |

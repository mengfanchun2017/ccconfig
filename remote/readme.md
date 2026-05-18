# remote — 远程连接 Claude Code

> 从笔记本 SSH 连接到台式机 WSL2 中的 Claude Code tmux 会话。

## 架构

```
笔记本 ──SSH──▶ 台式机 Windows (端口转发 :2222) ──▶ WSL2 (SSH Server + tmux)
        │
        └─ Tailscale（P2P 优先，境外 DERP 中继兜底）
```

Tailscale 基于 WireGuard，端到端加密。P2P 打洞成功后不经过中继，同城延迟几毫秒；打洞失败时走境外 DERP 中继兜底。

## 目录

```
remote/
├── deploy.sh
├── readme.md
├── server/                    台式机
│   ├── tmux-sshd.sh           SSH Server + tmux（WSL）
│   ├── tmux-portforward.ps1   端口转发（管理员 PS）
│   ├── tmux.conf              tmux 配置（deploy 自动部署）
│   └── ts-setup.ps1           Tailscale 一键安装（管理员 PS）
└── client/                    笔记本
    └── ts-setup.ps1           Tailscale 一键安装（管理员 PS）
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

### 5. 启动 Tailscale

Windows 管理员 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\ts-setup.ps1"
```

首次运行需登录：`tailscale up` 打开浏览器用 Microsoft/GitHub/Google 账号登录。

### 6. 查看本机 IP

```powershell
tailscale ip -4
# 例如: 100.118.224.45
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

### 3. 启动 Tailscale

Windows 管理员 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\git\winremote\ts-setup.ps1"
```

### 4. 验证 P2P 直连

```powershell
tailscale status        # 确认显示 direct
tailscale ping <服务器主机名>   # 看延迟
```

### 5. 连接服务器

```bash
ssh -p 2222 $USER@<服务器 Tailscale IP>
```

### 6. 可选：Win Terminal 一键连接

在本机 PowerShell 执行（不需管理员），`<服务器IP>` 替换为服务器的 Tailscale 虚拟 IP：

```powershell
New-Item -ItemType Directory -Force -Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8weky3b8dbbwe\LocalState\Fragments" | Out-Null; @{profiles=@(@{guid="{(New-Guid)}";name="Claude Code";commandline="ssh -p 2222 $USER@<服务器IP>";icon="🐚";tabTitle="Claude";hidden=$false})} | ConvertTo-Json -Depth 3 | Out-File -FilePath "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8weky3b8dbbwe\LocalState\Fragments\claude-code-ssh.json" -Encoding UTF8; Write-Host 'Done' -ForegroundColor Green
```

关闭重开 Windows Terminal，下拉菜单会多出 "Claude Code" 选项。

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
| Tailscale 未登录 | `tailscale up` 打开浏览器登录 |
| 走 DERP 延迟高 | `tailscale ping <对方>` 看是否 relay，检查两边防火墙/VPN |
| VPN 干扰 Tailscale | 规则模式加 bypass：端口 41641 UDP、`*.tailscale.com` 直连 |

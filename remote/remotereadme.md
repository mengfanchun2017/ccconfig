# remote — 远程连接 Claude Code

> 从笔记本 SSH 连接到台式机 WSL2 中的 Claude Code，恢复 tmux 会话继续对话。

## 前提条件

### WSL 网络配置（必须）

在 Windows 侧 `%USERPROFILE%\.wslconfig` 配置网络镜像模式，确保 WSL2 与 Windows 网络互通：

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
```

配置后需重启 WSL：PowerShell 执行 `wsl --shutdown`，再打开 WSL。

## 架构

```
笔记本 ──SSH──▶ 台式机 Windows ──端口转发──▶ WSL2:2222 (tmux + Claude)
                  │
                  ├─ 局域网: 直接 IP
                  ├─ Tailscale: 100.118.224.45 (已配置)
                  └─ EasyTier: 10.126.126.x (国内 P2P)
```

## 文件说明

| 文件 | 执行环境 | 用途 |
|------|---------|------|
| `remote-ub-sshd.sh` | 台式机 Ubuntu/WSL | 安装 SSH Server + tmux |
| `remote-ps-portforward.ps1` | 台式机 Windows (管理员) | 端口转发 + 防火墙 + 计划任务 |
| `soft-tmux.conf` | 台式机 Ubuntu/WSL | tmux 配置（鼠标、历史行数） |
| `soft-tmux-profile.ps1` | 笔记本 Windows | Win Terminal 一键连接 |
| `soft-easytier.ps1` | 两台机器 Windows (管理员) | EasyTier P2P 组网 |

## 两个远程方案

| | 方案A: tmux | 方案B: EasyTier |
|---|---|---|
| **组网** | Tailscale（境外中转） | EasyTier（国内 P2P 直连） |
| **速度** | 取决于 Tailscale 节点 | P2P 直连跑满带宽 |
| **配置复杂度** | 简单（各装 Tailscale 即可） | 中等（各跑 setup 脚本） |
| **推荐场景** | 快速上手，对延迟不敏感 | 需要低延迟，国内网络 |

> 方案 A 用 Tailscale 组网 + tmux 管理会话；方案 B 用 EasyTier 组网（国内 P2P 更快）。选择一个即可。

## 初始化步骤

### 第一步：台式机 WSL — SSH Server

```bash
bash ccconfig/remote/remote-ub-sshd.sh
```

这一步会：安装 openssh-server、配置端口 2222、启用自启、配置 tmux 自动 attach。

### 第二步：台式机 Windows — 端口转发

右键开始菜单 → **终端(管理员)** → 执行：

```powershell
powershell -ExecutionPolicy Bypass -File "\\wsl$\Ubuntu\home\francis\git\ccconfig\remote\remote-ps-portforward.ps1"
```

这一步会：端口转发 0.0.0.0:2222 → WSL2:2222、防火墙放行、创建计划任务（WSL 重启后自动更新 IP）。

### 第三步：组网（选一个方案）

**方案A — Tailscale + tmux**：
1. 两台 Windows 都安装 Tailscale，同一账号登录
2. 台式机复制 `soft-tmux.conf` → `~/.tmux.conf`
3. 笔记本执行 `soft-tmux-profile.ps1` 配置 Win Terminal 一键连接

**方案B — EasyTier**：
1. 两台 Windows 管理员 PowerShell 执行 `soft-easytier.ps1`
2. 启动后 `C:\easytier\easytier-cli.exe peer` 查看虚拟 IP
3. EasyTier 国内节点中转，比 Tailscale 快

### 第四步：笔记本连接

```bash
# Tailscale
ssh -p 2222 francis@100.118.224.45

# EasyTier（运行 easytier-cli.exe peer 查看）
ssh -p 2222 francis@<台式机虚拟IP>
```

连上后自动进入 tmux session，看到 Claude Code 界面。

## tmux 常用操作

- `Ctrl+B` `D` — 断开（detach），Claude 继续在后台运行
- `tmux attach -t claude` — 重新连接
- `Ctrl+B` `[` — 翻页模式（方向键翻页，`q` 退出）

## 常见问题

**连接超时？**
检查台式机 WSL 是否运行、端口转发是否生效：`netsh interface portproxy show v4tov4`

**Connection refused？**
台式机 WSL 内执行 `sudo systemctl status ssh`

**WSL2 重启后连不上？**
Windows 任务计划程序 → "WSL SSH PortForward" 应自动更新 IP，或手动执行端口转发脚本。

**EasyTier 进程检查？**
```powershell
C:\easytier\easytier-cli.exe peer
taskkill /f /im easytier-core.exe   # 停止
```

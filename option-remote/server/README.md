# option-remote/server/ — 台式机（服务器端）

> 在台式机 WSL/Windows 上执行的脚本。

## 文件

| 文件 | 执行位置 | 用途 |
|------|---------|------|
| `tmux-sshd.sh` | WSL bash | 安装 SSH Server + tmux，配置端口 2222 |
| `tmux-portforward.ps1` | Windows 管理员 PS | 端口转发 0.0.0.0:2222 → WSL |
| `tmux.conf` | WSL（deploy 自动部署） | tmux 配置（鼠标、快捷键） |
| `ts-setup.ps1` | Windows 管理员 PS | Tailscale 一键安装 |

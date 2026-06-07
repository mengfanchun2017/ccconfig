# windows-tools/ — Windows + WSL 互操作工具

Windows 平台执行的 PowerShell 脚本，以及 WSL 侧配置脚本。所有脚本在 Windows 主机（管理员或普通用户）上运行。

## 目录

| 路径 | 类型 | 用途 |
|------|------|------|
| `music-convert/` | PS + 二进制 | 网易云 NCM 解密 + FLAC/MP3 格式转换 |
| `psupdate/` | PS | PowerShell 7 升级（绕过 winget 1714/1612） |
| `wslconfig.ps1` | PS | 写入 `%USERPROFILE%\.wslconfig`，mirrored 网络模式 |
| `setup-pwsh-profile.ps1` | PS | 禁 PowerShell 启动时的版本更新通知（幂等） |
| `wsl-interop.sh` | bash | WSL 侧：写入 `/etc/wsl.conf`，关 Windows PATH 注入 |

## 调用约定：直接 `powershell.exe -File`

> **原则**：WSL 环境下需要触发 Windows 侧脚本时，直接调 PowerShell，不走 bash 包装。

```bash
# WSL 端调 Win 端 ps1 的标准模式
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w <path-to-ps1>)"
```

`wslpath -w` 把 WSL 路径转 Windows 路径（如 `/home/francis/git/ccconfig/windows-tools/wslconfig.ps1` → `C:\git\ccconfig\windows-tools\wslconfig.ps1`）。

### 各脚本调用

```bash
# Win 端：写 .wslconfig（mirrored 网络）
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/wslconfig.ps1)"
wsl.exe --shutdown   # 择机执行，必须冷启 WSL 生效

# Win 端：禁用 PowerShell 启动更新通知
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/setup-pwsh-profile.ps1)"

# WSL 端：修 interop，关闭 Win PATH 注入
sudo bash ccconfig/windows-tools/wsl-interop.sh
wsl.exe --shutdown   # 冷启生效
```

## `.wslconfig` 配置说明

```ini
[wsl2]
networkingMode=mirrored   # 网络镜像模式（推荐）
dnsTunneling=true         # DNS 隧道
autoProxy=false           # 关闭代理监听，VPN/Clash 切换不弹窗
firewall=true             # 防火墙集成
```

mirrored 模式下 WSL 和 Windows 共享 localhost，远程连接不再需要端口转发。

`autoProxy=false` 是关键：关掉 WSL 自动监听 Windows 代理变更，避免 VPN 切换时 WSL 终端弹通知。已运行的 shell session **不会热更新**——`.wslconfig` 仅在 WSL 子系统冷启时读取一次，必须 `wsl --shutdown` 后重开终端才生效。

## 验证 `.wslconfig` 同步状态

```bash
bash ccconfig/status.sh   # 看 [13] .wslconfig 同步 是否绿勾
```

或手动 diff：

```bash
diff <(printf '[wsl2]\nnetworkingMode=mirrored\ndnsTunneling=true\nautoProxy=false\nfirewall=true\n') /mnt/c/Users/$USER/.wslconfig
```

无输出 = 同步，有 `<`/`>` 行 = 需要重跑 ps1 + `wsl --shutdown`。

## 历史

- `powershell/` 目录（2026-06-07 改名）：原名暗示只放 PowerShell 脚本，但同时收纳 WSL 互操作的 .sh 包装会造成误导。改名 `windows-tools/` 涵盖 Windows+WSL 整套工具
- 2 个 .sh 包装（`wslconfig-sync.sh`、`setup-pwsh-profile.sh`）删除，改用上面的 `powershell.exe -File` 直调模式 —— 减少一层间接
- `windows/` 目录（2026-06-07 合并）：`.ps1` 移入本目录

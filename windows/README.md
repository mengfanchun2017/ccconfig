# windows/ — Windows/WSL 互操作工具

> 需要在 **Windows 侧** 执行的 PowerShell 脚本，以及 WSL 侧修复脚本。

## 文件

| 文件 | 执行位置 | 用途 |
|------|---------|------|
| `wslconfig.ps1` | Windows 管理员 PowerShell | 创建 `.wslconfig`，配置 mirrored 网络模式 |
| `wsl-interop.sh` | WSL bash | 修复 WSL interop，关闭 Windows PATH 注入 |

## 快速使用

### 1. 配置 WSL 网络镜像模式

在 Windows 管理员 PowerShell 中：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\git\ccconfig\windows\wslconfig.ps1"
wsl --shutdown
```

配置后 WSL 与 Windows 共享网络栈，无需端口转发。

### 2. 修复 WSL interop（PATH 污染）

在 WSL 中：

```bash
bash ccconfig/windows/wsl-interop.sh
```

写入 `/etc/wsl.conf`，关闭 Windows PATH 注入到 WSL。执行后需 `wsl --shutdown` 重启。

## .wslconfig 配置说明

```ini
[wsl2]
networkingMode=mirrored   # 网络镜像模式（推荐）
dnsTunneling=true         # DNS 隧道
autoProxy=false           # 关闭代理监听，VPN/Clash 切换不弹窗
firewall=true             # 防火墙集成
```

mirrored 模式下 WSL 和 Windows 共享 localhost，远程连接不再需要端口转发。

## 更新 / 同步 .wslconfig

在 Win 端切换了代理（Clash/V2Ray 等）发现 WSL 终端弹通知，或者 `.wslconfig` 落后 ccconfig 源时：

```powershell
# Win 端 PowerShell
powershell -ExecutionPolicy Bypass -File "C:\git\ccconfig\windows\wslconfig.ps1"
wsl --shutdown
```

`wsl --shutdown` 后重开 WSL 终端，新配置生效。
**已运行的 WSL session 不会热更新**——`.wslconfig` 仅在 WSL 子系统冷启时读取一次。

### 验证

```bash
diff <(printf '[wsl2]\nnetworkingMode=mirrored\ndnsTunneling=true\nautoProxy=false\nfirewall=true\n') /mnt/c/Users/$USER/.wslconfig
```

无输出 = 已同步。

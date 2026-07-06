# windows-tools/ — Windows 工具脚本

Windows 平台执行的 PowerShell 脚本集合。所有脚本在 Windows 主机上运行。

## 目录

| 路径 | 用途 |
|------|------|
| `music-convert/` | 网易云 NCM 解密 + FLAC/MP3 格式转换 |
| `psupdate/` | PowerShell 7 升级（绕过 winget 1714/1612） |

## 调用约定

```bash
# WSL 端调 Win 端 ps1 的标准模式
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w <path-to-ps1>)"

# music-convert — 交互菜单模式
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/music-convert/convert.ps1)"

# psupdate — 必须以管理员身份运行
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/psupdate/psupdate.ps1)"
```

# windows-tools/ — Windows + WSL 互操作工具

Windows 平台执行的 PowerShell 脚本集合。所有脚本在 Windows 主机（管理员或普通用户）上运行。

## 目录

3 个子目录 = 3 个领域：

| 路径 | 类型 | 用途 |
|------|------|------|
| `music-convert/` | PS + 二进制 | 网易云 NCM 解密 + FLAC/MP3 格式转换 |
| `psupdate/` | PS | PowerShell 7 升级（绕过 winget 1714/1612） |
| `wslconf/` | PS | WSL 启动配置（`.wslconfig` + `/etc/wsl.conf` 双侧） |

## 调用约定：直接 `powershell.exe -File`

> **原则**：本目录下所有工具都用 PowerShell 执行，不依赖 Linux shell。WSL 环境下需要触发 Win 端脚本时，直接调 PowerShell。

```bash
# WSL 端调 Win 端 ps1 的标准模式
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w <path-to-ps1>)"
```

`wslpath -w` 把 WSL 路径转 Windows 路径（如 `/home/francis/git/ccconfig/windows-tools/wslconf/wslconfig.ps1` → `C:\git\ccconfig\windows-tools\wslconf\wslconfig.ps1`）。

### 各目录调用

```bash
# music-convert — 交互菜单模式
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/music-convert/convert.ps1)"

# psupdate — 必须以管理员身份运行
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/psupdate/psupdate.ps1)"

# wslconf — 写 .wslconfig（mirrored 网络）
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/wslconf/wslconfig.ps1)"
wsl.exe --shutdown   # 必须！改 .wslconfig 不热更新

# wslconf — 写 /etc/wsl.conf（关 Win PATH 注入；脚本内部用 wsl.exe -u root）
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w ccconfig/windows-tools/wslconf/wslconf.ps1)"
wsl.exe --shutdown   # 必须！改 wsl.conf 不热更新
```

## wslconf 配置说明

详见 [`wslconf/README.md`](wslconf/README.md)。要点：

- `.wslconfig` 配 VM 级（网络、内存、CPU、代理）— WSL 服务读
- `wsl.conf` 配 init 级（systemd、Win PATH 注入、默认用户）— WSL init 读
- 两个文件**都需 `wsl --shutdown` 冷启才生效**

## 验证 `.wslconfig` 同步状态

```bash
bash ccconfig/status.sh   # 看 [13] .wslconfig 同步 是否绿勾
```

## 历史

- 2026-06-08 整合：3 个子目录对应 3 个领域；`wslconfig.ps1` + `wslconf.ps1`（原 `wsl-interop.ps1`）合入 `wslconf/`；`setup-pwsh-profile.ps1` 删除（psupdate 解决升级问题后，禁用启动通知需求弱化）
- 2026-06-07 `powershell/` 改名为 `windows-tools/`，`windows/` 合并入内；2 个 .sh 包装（`wslconfig-sync.sh`、`setup-pwsh-profile.sh`）删除，改用 `powershell.exe -File $(wslpath -w ...)` 直调模式
- 2026-06-07 `wsl-interop.sh` → `wsl-interop.ps1`：写 `/etc/wsl.conf` 虽然改 WSL 文件，但 `wsl.exe -u root` 从 PowerShell 调用更干净；目录全部 PS 统一

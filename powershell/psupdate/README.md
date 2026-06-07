# psupdate — PowerShell 7 升级工具

## 解决什么问题

`winget upgrade --id Microsoft.PowerShell` 在某些环境下会失败：

- **Error 1714 / 1612** — Windows Installer 缓存的旧版 MSI 源丢失（`%WINDIR%\Installer\<hash>.msi` 不存在），新装器无法 RemoveExistingProducts
- **Error 1603** — 旧版 PowerShell 进程仍在运行（`pwsh.exe` 占用文件）

`winget repair` 报"安装程序技术不支持修复"，无解。

psupdate 绕过 winget，直接走 GitHub 官方 MSI + `msiexec /x ... REINSTALLMODE=vomus`（强制使用外部源卸载），再装新版。

## 依赖

- Windows 10/11
- PowerShell 5+（已自带）
- 管理员权限（MSI 安装需要 UAC 提升）
- 网络访问 `github.com` 和 `api.github.com`

## 使用

```powershell
# 必须以管理员身份运行 PowerShell
.\psupdate.ps1              # 升到 GitHub 最新 stable
.\psupdate.ps1 -Version 7.6.2   # 升到指定版本
.\psupdate.ps1 -KeepInstaller   # 保留下载的 MSI（调试用）
```

## 工作流

1. 读取注册表 `HKLM:\...\Uninstall\*` 获取当前 `PowerShell 7-x64` 版本
2. 调用 GitHub API 取最新 stable tag（或用 `-Version` 指定）
3. 下载目标 MSI 到 `$env:TEMP\psupdate-<ver>.msi`
4. 下载旧版 MSI 到 `$env:TEMP\psupdate-<old>.msi`
5. `msiexec /x <old>.msi /qn /norestart REINSTALLMODE=vomus` — `vomus` 让 msiexec 接受外部源，覆盖缓存缺失
6. `msiexec /i <new>.msi /qn /norestart` 装新版
7. 读注册表验证版本
8. 清理 `$env:TEMP` 下的 MSI（除非 `-KeepInstaller`）

## 关键 flag

- `REINSTALLMODE=vomus` — `v` 验证源、`o` 缺失则重装、`m` 重写 machine config、`u` 重装 user reg、`s` 重装 shortcuts。这是绕过 1612 的核心。
- `/qn` 完全静默；想看进度可换 `/qb`（基本 UI）。

## 典型场景

**正常 winget 升级失败**：
```
winget upgrade --id Microsoft.PowerShell
→ 安装程序失败，退出代码为: 1603
→ Error 1714. The older version of PowerShell 7-x64 cannot be removed. System Error 1612.
```
→ 跑 `.\psupdate.ps1`

**pwsh 进程占用导致 1603**：
- 关闭所有 PowerShell 窗口再跑 psupdate
- 或 `Get-Process pwsh | Stop-Process -Force`

## 已知限制

- 仅支持 x64（脚本里 URL 写死 `-win-x64`）。要 ARM64 自行改 URL。
- 不支持降级（git tags 都在，但 `RemoveExistingProducts` 不一定允许降版 — 可手动调 `msiexec /i` 试）。
- 不处理 PATH 配置（PowerShell 7 安装器默认会把自己加到 PATH）。

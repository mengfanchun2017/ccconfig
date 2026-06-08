# WSL 网络配置脚本 — 设置 .wslconfig
# 用途：在 Windows 侧创建 %USERPROFILE%\.wslconfig，配置 mirrored 网络模式
#
# 使用（Windows 管理员 PowerShell）：
#   powershell -ExecutionPolicy Bypass -File "C:\git\ccconfig\windows-tools\wslconfig.ps1"
#
# autoProxy=true：WSL 启动时和 Win 端代理变更时，自动把 Windows 端代理 IP
# 注入 WSL 进程 env (HTTP_PROXY/HTTPS_PROXY/NO_PROXY)，让 WSL 端 git/curl 等
# 能直接用 Win 端 clash/v2ray。autoProxy 不影响 WSL 弹窗（弹窗来自 GUI 应用
# 的代理检测 dialog，与本设置无关）。

$ErrorActionPreference = "Stop"

$wslconfigPath = "$env:USERPROFILE\.wslconfig"

$content = @"
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
firewall=true
"@

Write-Host "写入 $wslconfigPath ..."
# PowerShell 5.x 的 -Encoding UTF8 会写 BOM，status.sh 比对失败
# 显式用 UTF8Encoding($false) 写无 BOM 的 UTF-8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($wslconfigPath, $content, $utf8NoBom)

Write-Host ""
Write-Host "✅ .wslconfig 已配置（mirrored 网络模式，autoProxy=true）"
Write-Host ""
Write-Host "mirrored 模式下："
Write-Host "  - WSL 和 Windows 共享网络（无需端口转发）"
Write-Host "  - localhost 双向互通"
Write-Host "  - Tailscale 直接可用"
Write-Host "autoProxy=true：WSL 启动时和 Win 切代理时，自动同步 HTTP_PROXY env"
Write-Host ""
Write-Host "下一步：在 PowerShell 中运行 'wsl --shutdown' 重启 WSL 生效"

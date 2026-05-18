# WSL 网络配置脚本 — 设置 .wslconfig
# 用途：在 Windows 侧创建 %USERPROFILE%\.wslconfig，配置 mirrored 网络模式
#
# 使用（Windows 管理员 PowerShell）：
#   powershell -ExecutionPolicy Bypass -File "C:\git\ccconfig\windows\wslconfig.ps1"

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
Set-Content -Path $wslconfigPath -Value $content -Encoding UTF8

Write-Host ""
Write-Host "✅ .wslconfig 已配置（mirrored 网络模式）"
Write-Host ""
Write-Host "mirrored 模式下："
Write-Host "  - WSL 和 Windows 共享网络（无需端口转发）"
Write-Host "  - localhost 双向互通"
Write-Host "  - Tailscale 直接可用"
Write-Host ""
Write-Host "下一步：在 PowerShell 中运行 'wsl --shutdown' 重启 WSL 生效"

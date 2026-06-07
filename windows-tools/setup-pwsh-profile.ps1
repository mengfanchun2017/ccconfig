# 禁用 PowerShell 启动时的版本更新通知
# 用途：POWERSHELL_UPDATECHECK=Off 写入 CurrentUserAllHosts profile
#
# 运行（普通用户权限即可，无需管理员）：
#   powershell -ExecutionPolicy Bypass -File "C:\git\ccconfig\windows-tools\setup-pwsh-profile.ps1"
#
# 幂等：检测到 ccconfig marker 跳过
# 适用：Windows PowerShell 5.1+ / PowerShell 7+ (pwsh)，所有 host 共用

$ErrorActionPreference = "Stop"

$marker = '# ccconfig:pwsh-no-update-check'
$profilePath = $PROFILE.CurrentUserAllHosts

$dir = Split-Path $profilePath -Parent
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$existing = if (Test-Path $profilePath) {
    Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
} else { '' }

if ($existing -match [regex]::Escape($marker)) {
    Write-Host "[skip] $profilePath 已含 ccconfig marker"
    exit 0
}

$snippet = @"

$marker
`$env:POWERSHELL_UPDATECHECK = 'Off'
"@

Add-Content -Path $profilePath -Value $snippet -Encoding UTF8

Write-Host "[ok] 禁用 PowerShell 启动更新通知"
Write-Host "     路径: $profilePath"
Write-Host "     还原: 删除 ccconfig marker 段，或 Remove-Item '$profilePath'"

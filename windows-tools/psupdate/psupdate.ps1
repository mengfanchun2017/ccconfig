#requires -RunAsAdministrator
<#
.SYNOPSIS
  PowerShell 7 (MSI) 升级工具 — 绕过 winget 在源缓存丢失时的 Error 1714/1612。

.DESCRIPTION
  流程：检测当前版本 → 查 GitHub 最新 stable release → 下载目标 MSI →
  下载旧版 MSI（如果本机已装 PowerShell 7）→ msiexec /x 旧版（REINSTALLMODE=vomus
  强制使用外部源，覆盖丢失的 %WINDIR%\Installer 缓存）→ msiexec /i 新版 → 验证。

.PARAMETER Version
  目标版本号（不含 v 前缀，如 7.6.2）。留空则从 GitHub API 取最新 stable tag。

.PARAMETER KeepInstaller
  保留下载的 MSI（默认清理到 $env:TEMP\psupdate-\<ver>.msi，可在失败时重试）。

.EXAMPLE
  .\psupdate.ps1
  # 升到 GitHub 最新 stable

.EXAMPLE
  .\psupdate.ps1 -Version 7.6.2
  # 升到指定版本

.NOTES
  必须在管理员 PowerShell 中运行（MSI 安装需要提升）。
#>

[CmdletBinding()]
param(
    [string]$Version = "",
    [switch]$KeepInstaller
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Get-LatestStablePSTag {
    $api = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
    $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'psupdate' }
    if ($rel.prerelease) { throw "Latest release is prerelease ($($rel.tag_name)); pass -Version explicitly." }
    return $rel.tag_name.TrimStart('v')
}

function Get-InstalledPWMajorMinor {
    $reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $hit = Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq 'PowerShell 7-x64' } |
        Select-Object -First 1
    if (-not $hit) { return $null }
    return $hit.DisplayVersion
}

function Save-MSI {
    param([string]$Url, [string]$Dest)
    Write-Host "Downloading $Url" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    if ((Get-Item $Dest).Length -lt 1MB) { throw "Downloaded MSI looks too small: $Dest" }
}

# --- main --------------------------------------------------------------------

$installed = Get-InstalledPWMajorMinor
if (-not $installed) { throw "PowerShell 7-x64 not installed. Use winget install Microsoft.PowerShell first." }
Write-Host "Installed: $installed" -ForegroundColor Yellow

if (-not $Version) { $Version = Get-LatestStablePSTag }
Write-Host "Target:    $Version" -ForegroundColor Yellow

if ($Version -eq $installed) { Write-Host "Already up to date."; exit 0 }

# 下载目标 MSI
$newMsi = Join-Path $env:TEMP "psupdate-$Version.msi"
if (-not (Test-Path $newMsi)) { Save-MSI "https://github.com/PowerShell/PowerShell/releases/download/v$Version/PowerShell-$Version-win-x64.msi" $newMsi }

# 下载旧版 MSI（用于 REINSTALLMODE=vomus 强制卸载）
$oldMsi = Join-Path $env:TEMP "psupdate-$installed.msi"
if (-not (Test-Path $oldMsi)) { Save-MSI "https://github.com/PowerShell/PowerShell/releases/download/v$installed/PowerShell-$installed-win-x64.msi" $oldMsi }

# 卸载旧版（vomus = 接受外部源，覆盖 %WINDIR%\Installer 缓存缺失）
Write-Host "Uninstalling $installed ..." -ForegroundColor Cyan
$rc = (Start-Process msiexec.exe -ArgumentList @('/x', $oldMsi, '/qn', '/norestart', 'REINSTALLMODE=vomus') -Wait -PassThru).ExitCode
if ($rc -ne 0) { throw "msiexec /x failed: exit code $rc" }

# 装新版
Write-Host "Installing $Version ..." -ForegroundColor Cyan
$rc = (Start-Process msiexec.exe -ArgumentList @('/i', $newMsi, '/qn', '/norestart') -Wait -PassThru).ExitCode
if ($rc -ne 0) { throw "msiexec /i failed: exit code $rc" }

# 验证
$verify = Get-InstalledPWMajorMinor
Write-Host "Verified:  $verify" -ForegroundColor Green
if ($verify -ne $Version) { throw "Post-install version mismatch: expected $Version, got $verify" }

if (-not $KeepInstaller) {
    Remove-Item $newMsi, $oldMsi -ErrorAction SilentlyContinue
}

Write-Host "Done. Restart any open PowerShell windows to pick up the new version." -ForegroundColor Green

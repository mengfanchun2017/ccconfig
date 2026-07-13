# ============================================================
# Tailscale 一键安装 & 启动
# 台式机和笔记本都以管理员身份执行此脚本
# ============================================================
param(
    [string]$InstallerPath = ""
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Tailscale 组网安装"

# === 管理员检查 ===
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[错误] 请以管理员身份运行！" -ForegroundColor Red
    Write-Host "  右键开始菜单 -> 终端(管理员)" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Tailscale 组网 — 一键安装" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$tailscaleExe = "${env:ProgramFiles}\Tailscale\tailscale.exe"

# === 1. 检查是否已安装 ===
if (Test-Path $tailscaleExe) {
    $ver = & $tailscaleExe version 2>&1 | Select-Object -First 1
    Write-Host "[检测] Tailscale 已安装: $ver" -ForegroundColor Green
} else {
    Write-Host "[1/3] 安装 Tailscale..." -ForegroundColor Yellow

    # 方案A: winget（推荐）
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "  通过 winget 安装..."
        winget install tailscale.tailscale --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
    }

    # 方案B: 本地安装包
    if (-not (Test-Path $tailscaleExe)) {
        if ($InstallerPath -and (Test-Path $InstallerPath)) {
            Write-Host "  使用本地安装包: $InstallerPath"
            Start-Process -FilePath $InstallerPath -ArgumentList "/quiet" -Wait
        }
    }

    # 方案C: 联网下载最新版
    if (-not (Test-Path $tailscaleExe)) {
        Write-Host "  自动下载最新版 Tailscale..."
        $dlUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
        $dlPath = "$env:TEMP\tailscale-setup.exe"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $dlUrl -OutFile $dlPath -UseBasicParsing
        Start-Process -FilePath $dlPath -ArgumentList "/quiet" -Wait
        Remove-Item $dlPath -ErrorAction SilentlyContinue
    }

    if (Test-Path $tailscaleExe) {
        Write-Host "  安装完成" -ForegroundColor Green
    } else {
        Write-Host "  [失败] 安装未成功" -ForegroundColor Red
        Write-Host "  请手动安装: https://tailscale.com/download" -ForegroundColor Yellow
        pause
        exit 1
    }
}

# === 2. 确保服务运行 ===
Write-Host "[2/3] 检查服务状态..." -ForegroundColor Yellow
$service = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "  [警告] Tailscale 服务未找到，尝试启动..." -ForegroundColor Yellow
    Start-Process -FilePath $tailscaleExe -ArgumentList "up" -NoNewWindow -Wait 2>&1 | Out-Null
    Start-Sleep -Seconds 3
}

# === 3. 状态 & IP ===
Write-Host "[3/3] 获取连接状态..." -ForegroundColor Yellow
$status = & $tailscaleExe status 2>&1
$ip = & $tailscaleExe ip -4 2>&1

if ($status -match "Logged out" -or $status -match "not logged in") {
    Write-Host "  Tailscale 已安装但未登录" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  执行以下命令，浏览器会打开登录页面：" -ForegroundColor Cyan
    Write-Host "    tailscale up" -ForegroundColor White
    Write-Host "  用 Microsoft/GitHub/Google 账号登录即可" -ForegroundColor DarkGray
} else {
    Write-Host "  Tailscale 已连接" -ForegroundColor Green
    Write-Host "  虚拟 IP: $ip" -ForegroundColor White
    Write-Host "  节点列表:" -ForegroundColor White
    Write-Host "$status" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  完成" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "主要命令:" -ForegroundColor Yellow
Write-Host "  tailscale status  查看所有节点" -ForegroundColor White
Write-Host "  tailscale ip -4   查看本机虚拟 IP" -ForegroundColor White
Write-Host "  tailscale up       登录/重新连接" -ForegroundColor White
Write-Host ""

if ($status -match "Logged out" -or $status -match "not logged in") {
    Write-Host "立即登录:" -ForegroundColor Yellow
    Start-Process -FilePath $tailscaleExe -ArgumentList "up" -NoNewWindow
}

pause

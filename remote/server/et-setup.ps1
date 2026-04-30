# ============================================================
# EasyTier P2P 组网 — 一键安装 & 启动
# 台式机和笔记本都以管理员身份执行此脚本
# ============================================================
param(
    [string]$NetworkName = "claude-net",
    [string]$NetworkSecret = "claude-ssh-2026",
    [string]$InstallDir = "C:\git\winremote\easytier",
    [string]$Version = "v2.6.2"
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "EasyTier 组网安装"

# === 管理员检查 ===
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[错误] 请以管理员身份运行！" -ForegroundColor Red
    Write-Host "  右键开始菜单 -> 终端(管理员) -> 再执行此脚本" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  EasyTier P2P 组网 — 一键安装" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# === 0. 检查已安装 ===
$exePath = "$InstallDir\easytier-core.exe"
$cliPath = "$InstallDir\easytier-cli.exe"
$zipFile = "$InstallDir\easytier.zip"
$extractDir = "$InstallDir\easytier-windows-x86_64"

$alreadyInstalled = Test-Path $exePath
if ($alreadyInstalled) {
    Write-Host "[检测] EasyTier 已安装: $exePath" -ForegroundColor Green
    Write-Host ""
    Write-Host "接下来会检查防火墙并启动组网..." -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "[1/4] 下载 EasyTier $Version ..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $url = "https://github.com/EasyTier/EasyTier/releases/download/$Version/easytier-windows-x86_64-$Version.zip"
    Write-Host "  $url" -ForegroundColor DarkGray

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $zipFile)
        Write-Host "  下载完成 ($((Get-Item $zipFile).Length / 1MB) MB)" -ForegroundColor Green
    } catch {
        Write-Host "  [失败] 下载出错，请检查网络" -ForegroundColor Red
        Write-Host "  手动下载: https://github.com/EasyTier/EasyTier/releases" -ForegroundColor Yellow
        Write-Host "  解压到 $InstallDir 后重新运行此脚本" -ForegroundColor Yellow
        pause
        exit 1
    }

    Write-Host "[2/4] 解压安装..." -ForegroundColor Yellow
    Expand-Archive -Path $zipFile -DestinationPath $InstallDir -Force
    Remove-Item $zipFile

    # 新版 EasyTier 会解压到子目录，把文件移到上层
    if (Test-Path $extractDir) {
        Write-Host "  检测到子目录，移动文件到 $InstallDir..." -ForegroundColor DarkGray
        Get-ChildItem -Path $extractDir -File | Move-Item -Destination $InstallDir -Force
        Get-ChildItem -Path $extractDir -Directory | Move-Item -Destination $InstallDir -Force -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Force
    }

    # 解除下载文件的 Windows 安全封锁
    Write-Host "  解除文件安全封锁..." -ForegroundColor DarkGray
    Get-ChildItem -Path $InstallDir -File | Unblock-File -ErrorAction SilentlyContinue

    if (Test-Path $exePath) {
        Write-Host "  安装完成: $exePath" -ForegroundColor Green
    } else {
        Write-Host "  [失败] 解压后未找到 easytier-core.exe" -ForegroundColor Red
        Write-Host "  请检查 $InstallDir 目录内容：" -ForegroundColor Yellow
        Get-ChildItem $InstallDir
        pause
        exit 1
    }
}

# === 防火墙 ===
Write-Host "[3/4] 防火墙放行..." -ForegroundColor Yellow
$fwTcp = Get-NetFirewallRule -DisplayName "EasyTier TCP" -ErrorAction SilentlyContinue
$fwUdp = Get-NetFirewallRule -DisplayName "EasyTier UDP" -ErrorAction SilentlyContinue
if (-not $fwTcp) {
    New-NetFirewallRule -DisplayName "EasyTier TCP" -Direction Inbound -Protocol TCP -LocalPort 11010 -Action Allow | Out-Null
    Write-Host "  已添加 TCP 11010" -ForegroundColor Green
} else {
    Write-Host "  TCP 11010 规则已存在" -ForegroundColor DarkGray
}
if (-not $fwUdp) {
    New-NetFirewallRule -DisplayName "EasyTier UDP" -Direction Inbound -Protocol UDP -LocalPort 11010 -Action Allow | Out-Null
    Write-Host "  已添加 UDP 11010" -ForegroundColor Green
} else {
    Write-Host "  UDP 11010 规则已存在" -ForegroundColor DarkGray
}

# === 停旧进程 ===
Write-Host "[4/4] 启动 EasyTier..." -ForegroundColor Yellow
$existing = Get-Process -Name "easytier-core" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  停止已有进程..." -ForegroundColor DarkGray
    Stop-Process -Name "easytier-core" -Force
    Start-Sleep -Seconds 1
}

# === 启动 ===
$publicRelay = "tcp://public.easytier.top:11010"
$argList = "-d --network-name $NetworkName --network-secret $NetworkSecret -e $publicRelay --latency-first"

Start-Process -FilePath $exePath -ArgumentList $argList -WindowStyle Hidden
Start-Sleep -Seconds 3

$running = Get-Process -Name "easytier-core" -ErrorAction SilentlyContinue
if (-not $running) {
    Write-Host "  [警告] 进程未启动！" -ForegroundColor Red
    Write-Host "  请手动运行: $exePath $argList" -ForegroundColor Yellow
    Write-Host "  查看日志输出判断原因" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "  EasyTier 运行中 (PID: $($running.Id))" -ForegroundColor Green

# === 完成 ===
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  安装完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "检查状态（普通 PowerShell 即可）:" -ForegroundColor Yellow
Write-Host "  & `"$cliPath`" peer" -ForegroundColor White
Write-Host ""

Write-Host "=== 状态解读 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "只有自己（刚装完第一台，正常）:" -ForegroundColor Yellow
Write-Host "  | ipv4 | hostname    | cost  | lat(ms) | NAT    |" -ForegroundColor DarkGray
Write-Host "  | -    | 本机名       | Local | -       | Symmetric |" -ForegroundColor DarkGray
Write-Host ""
Write-Host "两台互见（两台都跑完后，正常）:" -ForegroundColor Green
Write-Host "  | 10.126.126.2 | 台式机名 | P2P   | 15      | Symmetric |" -ForegroundColor DarkGray
Write-Host "  | 10.126.126.3 | 笔记本名 | P2P   | 15      | PortRestricted |" -ForegroundColor DarkGray
Write-Host ""
Write-Host "如果 tunnel 列显示 Relay 而非 P2P — 打洞失败走中继，延迟会高一些但仍可用" -ForegroundColor DarkGray
Write-Host ""

Write-Host "连接 SSH（看到两台互见后）:" -ForegroundColor Yellow
Write-Host "  ssh -p 2222 francis@<台式机虚拟IP>" -ForegroundColor White
Write-Host "  ssh -p 2222 francis@10.126.126.2" -ForegroundColor DarkGray
Write-Host ""

Write-Host "停止 EasyTier:" -ForegroundColor DarkGray
Write-Host "  taskkill /f /im easytier-core.exe" -ForegroundColor DarkGray
Write-Host ""
pause

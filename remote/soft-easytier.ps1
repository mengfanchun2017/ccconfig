# ============================================================
# EasyTier 一键安装 & 启动脚本
# 在台式机和笔记本都以管理员身份执行
# ============================================================
param(
    [string]$NetworkName = "claude-net",
    [string]$NetworkSecret = "claude-ssh-2026",
    [string]$InstallDir = "C:\easytier",
    [string]$Version = "v2.6.2"
)

$ErrorActionPreference = "Stop"

# === 管理员检查 ===
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "请以管理员身份运行！" -ForegroundColor Red
    Write-Host "右键开始菜单 → 终端(管理员)" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "=== EasyTier P2P 组网设置 ===" -ForegroundColor Cyan
Write-Host ""

# === 1. 下载 EasyTier ===
$zipFile = "$InstallDir\easytier.zip"
$exePath = "$InstallDir\easytier-core.exe"

if (Test-Path $exePath) {
    Write-Host "[1/4] EasyTier 已安装: $exePath" -ForegroundColor Green
} else {
    Write-Host "[1/4] 下载 EasyTier $Version..."
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    $url = "https://github.com/EasyTier/EasyTier/releases/download/$Version/easytier-windows-x86_64-$Version.zip"
    Write-Host "  $url"

    try {
        # 优先用系统代理下载（国内可能需要代理加速 GitHub）
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $zipFile)
    } catch {
        Write-Host "  [失败] 下载出错，请检查网络或手动下载：" -ForegroundColor Red
        Write-Host "  https://github.com/EasyTier/EasyTier/releases" -ForegroundColor Yellow
        Write-Host "  下载后解压到 $InstallDir 再重新运行此脚本" -ForegroundColor Yellow
        pause
        exit 1
    }

    Write-Host "  解压到 $InstallDir..."
    Expand-Archive -Path $zipFile -DestinationPath $InstallDir -Force
    Remove-Item $zipFile
    Write-Host "  安装完成" -ForegroundColor Green
}

# === 2. 防火墙放行 ===
Write-Host "[2/4] 防火墙放行..."
$fwRule = Get-NetFirewallRule -DisplayName "EasyTier" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    New-NetFirewallRule -DisplayName "EasyTier" -Direction Inbound -Protocol TCP -LocalPort 11010 -Action Allow > $null
    New-NetFirewallRule -DisplayName "EasyTier UDP" -Direction Inbound -Protocol UDP -LocalPort 11010 -Action Allow > $null
    Write-Host "  已添加防火墙规则 (TCP/UDP 11010)" -ForegroundColor Green
} else {
    Write-Host "  防火墙规则已存在，跳过" -ForegroundColor Yellow
}

# === 3. 检查是否已在运行 ===
Write-Host "[3/4] 检查运行状态..."
$existing = Get-Process -Name "easytier-core" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  EasyTier 已在运行，先停止..." -ForegroundColor Yellow
    Stop-Process -Name "easytier-core" -Force
    Start-Sleep -Seconds 1
}

# === 4. 启动 EasyTier ===
Write-Host "[4/4] 启动 EasyTier..."
$publicRelay = "tcp://public.easytier.top:11010"

# 后台启动，输出写日志
$logFile = "$InstallDir\easytier.log"
$argList = "-d --network-name $NetworkName --network-secret $NetworkSecret -e $publicRelay --latency-first"

Write-Host "  参数: $argList"
Start-Process -FilePath $exePath -ArgumentList $argList -WindowStyle Hidden

Start-Sleep -Seconds 3

# 检查进程是否在跑
$running = Get-Process -Name "easytier-core" -ErrorAction SilentlyContinue
if (-not $running) {
    Write-Host "  [警告] 进程未启动，查看日志: $logFile" -ForegroundColor Yellow
} else {
    Write-Host "  EasyTier 已启动 (PID: $($running.Id))" -ForegroundColor Green
}

# === 验证 ===
Write-Host ""
Write-Host "=== 完成 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "组网信息:" -ForegroundColor Yellow
Write-Host "  虚拟网段: 10.126.126.0/24 (自动分配 IP)" -ForegroundColor White
Write-Host "  网络名称: $NetworkName" -ForegroundColor White
Write-Host "  中转兜底: $publicRelay" -ForegroundColor White
Write-Host ""
Write-Host "查看连接状态:" -ForegroundColor Yellow
Write-Host "  $InstallDir\easytier-cli.exe peer" -ForegroundColor White
Write-Host ""
Write-Host "日志文件:" -ForegroundColor Yellow
Write-Host "  $logFile" -ForegroundColor White
Write-Host ""
Write-Host "停止 EasyTier:" -ForegroundColor Yellow
Write-Host "  taskkill /f /im easytier-core.exe" -ForegroundColor White
Write-Host ""
Write-Host "笔记本连接台式机 SSH:" -ForegroundColor Cyan
Write-Host "  ssh -p 2222 francis@<台式机虚拟IP>" -ForegroundColor White
Write-Host "  (运行 easytier-cli.exe peer 查看 IP)" -ForegroundColor DarkGray
pause

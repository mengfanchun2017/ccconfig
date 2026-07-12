# ============================================================
# WSL2 SSH 端口转发 & 防火墙 & 计划任务
# ============================================================
# 在台式机 Windows 管理员 PowerShell 中执行:
#   powershell -ExecutionPolicy Bypass -File "C:\git\wsl-portforward.ps1"
# 或从 WSL 文件系统直接执行:
#   powershell -ExecutionPolicy Bypass -File "\\wsl$\Ubuntu\home\$env:USER\git\ccconfig\remote\server\wsl-portforward.ps1"
# ============================================================

$Port = 2222

# === 管理员检查 ===
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "请以管理员身份运行！" -ForegroundColor Red
    Write-Host "右键开始菜单 → 终端(管理员) 或搜索 PowerShell → 以管理员身份运行" -ForegroundColor Yellow
    pause
    exit 1
}

Write-Host "=== WSL2 SSH 端口转发设置 ===" -ForegroundColor Cyan
Write-Host ""

# === 1. 获取 WSL2 IP ===
Write-Host "[1/4] 获取 WSL2 IP..."
try {
    $raw = wsl -- hostname -I
    $WslIp = $raw.Trim().Split(' ')[0]
    if (-not $WslIp -or $WslIp -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        Write-Host "  [失败] 取不到 WSL2 IP" -ForegroundColor Red
        Write-Host "  请确认 WSL 在运行：先打开一个终端执行 wsl" -ForegroundColor Yellow
        pause
        exit 1
    }
    Write-Host "  WSL2 IP: $WslIp" -ForegroundColor Green
} catch {
    Write-Host "  [失败] 请确保 WSL 已安装并在运行" -ForegroundColor Red
    pause
    exit 1
}

# === 2. 端口转发 ===
Write-Host "[2/4] 设置端口转发..."
$null = netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 2>&1
netsh interface portproxy add v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=$WslIp
Write-Host "  0.0.0.0:$Port -> $WslIp`:$Port" -ForegroundColor Green

# === 3. 防火墙 ===
Write-Host "[3/4] 防火墙放行..."
$existing = Get-NetFirewallRule -DisplayName "WSL2 SSH (Port $Port)" -ErrorAction SilentlyContinue
if (-not $existing) {
    New-NetFirewallRule `
        -DisplayName "WSL2 SSH (Port $Port)" `
        -Direction Inbound `
        -LocalPort $Port `
        -Protocol TCP `
        -Action Allow `
        -Profile Any > $null
    Write-Host "  已添加防火墙规则" -ForegroundColor Green
} else {
    Write-Host "  防火墙规则已存在，跳过" -ForegroundColor Yellow
}

# === 4. 计划任务（WSL 重启后自动更新转发 IP） ===
Write-Host "[4/4] 创建计划任务（WSL 重启后自动更新端口转发）..."

$updateScript = @'
$Port = 2222
$ip = (wsl -- hostname -I 2>$null).Trim().Split(' ')[0]
if ($ip -and $ip -match '^\d+\.\d+\.\d+\.\d+$') {
    netsh interface portproxy delete v4tov4 listenport=$Port listenaddress=0.0.0.0 > $null 2>&1
    netsh interface portproxy add    v4tov4 listenport=$Port listenaddress=0.0.0.0 connectport=$Port connectaddress=$ip
}
'@

$updatePath = "$env:USERPROFILE\.wsl-ssh-update.ps1"
$updateScript | Out-File -FilePath $updatePath -Encoding UTF8 -Force

# 删除旧任务（如果有）
Get-ScheduledTask -TaskName "WSL SSH PortForward" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

$action    = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$updatePath`""

$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -RunLevel Highest

$settings  = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName "WSL SSH PortForward" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Force > $null

Write-Host "  计划任务 'WSL SSH PortForward' 已创建" -ForegroundColor Green

# === 验证 ===
Write-Host ""
Write-Host "=== 当前端口转发状态 ===" -ForegroundColor Cyan
netsh interface portproxy show v4tov4 | Select-String "0.0.0.0" | Select-String "$Port"
Write-Host ""
Write-Host "=== 完成 ===" -ForegroundColor Green
Write-Host ""
Write-Host "下一步:" -ForegroundColor Cyan
Write-Host "  1. 两台 Windows 安装 Tailscale 或 ZeroTier（如果不在同一局域网）" -ForegroundColor White
Write-Host "  2. 笔记本终端执行: ssh -p $Port francis@<台式机IP>" -ForegroundColor White
Write-Host ""
Write-Host "详细说明见: ~/git/ccconfig/ssh/README.md" -ForegroundColor DarkGray
pause

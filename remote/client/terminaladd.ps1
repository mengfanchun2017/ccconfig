# ============================================================
# Windows Terminal 一键连接配置
# 在笔记本 Windows 终端中执行（无需管理员）:
#   powershell -ExecutionPolicy Bypass -File "C:\git\winremote\terminaladd.ps1" -RemoteHost 100.118.224.45
# ============================================================
param(
    [Parameter(Mandatory=$true)]
    [string]$RemoteHost = "100.118.224.45",

    [int]$Port = 2222,
    [string]$User = "francis",
    [string]$ProfileName = "Claude Code"
)

# === 确定 Windows Terminal 路径 ===
$wtLocal   = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8weky3b8dbbwe\LocalState"
$wtDefault = "$env:LOCALAPPDATA\Microsoft\WindowsTerminal"

if (Test-Path "$wtLocal\settings.json") {
    $wtDir = $wtLocal
} elseif (Test-Path "$wtDefault\settings.json") {
    $wtDir = $wtDefault
} else {
    Write-Host "[错误] 找不到 Windows Terminal 配置文件" -ForegroundColor Red
    Write-Host "  请确认已安装 Windows Terminal（微软商店搜索安装）" -ForegroundColor Yellow
    pause
    exit 1
}

# === 使用 Fragment 方式（不修改主配置文件） ===
$fragDir = "$wtDir\Fragments"
New-Item -ItemType Directory -Force -Path $fragDir | Out-Null

$guid = [Guid]::NewGuid().ToString()
$sshCmd = "ssh -p $Port $User@$RemoteHost"

$fragment = @{
    profiles = @(
        @{
            guid       = "{$guid}"
            name       = $ProfileName
            commandline = $sshCmd
            icon       = "🐚"
            tabTitle   = "Claude"
            hidden     = $false
        }
    )
} | ConvertTo-Json -Depth 3

$fragPath = "$fragDir\claude-code-ssh.json"
$fragment | Out-File -FilePath $fragPath -Encoding UTF8
Write-Host "已创建配置: $fragPath" -ForegroundColor Green
Write-Host "SSH 命令: $sshCmd" -ForegroundColor Cyan
Write-Host ""
Write-Host "关闭重开 Windows Terminal，点击顶部下拉菜单选择 'Claude Code' 即可一键连接" -ForegroundColor Yellow
Write-Host ""
Write-Host "换 IP 后重新执行此脚本更新: " -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File C:\git\winremote\terminaladd.ps1 -RemoteHost <新IP>" -ForegroundColor White
Write-Host ""
Write-Host "例如当前 IP: " -ForegroundColor White -NoNewline
Write-Host "  .\terminaladd.ps1 -RemoteHost $RemoteHost" -ForegroundColor Cyan
pause

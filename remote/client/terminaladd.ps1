# ============================================================
# Windows Terminal 一键连接 — 手动模式
# 用法: .\terminaladd.ps1 -RemoteHost 100.126.242.105
# ============================================================
param(
    [Parameter(Mandatory=$true)]
    [string]$RemoteHost = "100.118.224.45",

    [int]$Port = 2222,
    [string]$User = "francis",
    [string]$ProfileName = "Claude Code"
)

Write-Host ""
Write-Host "=== 复制下面整段命令到 PowerShell 中执行 ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "New-Item -ItemType Directory -Force -Path `"`$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8weky3b8dbbwe\LocalState\Fragments`" | Out-Null; @{profiles=@(@{guid=`"{(New-Guid)}`";name=`"$ProfileName`";commandline=`"ssh -p $Port $User@$RemoteHost`";icon=`"🐚`";tabTitle=`"Claude`";hidden=`$false})} | ConvertTo-Json -Depth 3 | Out-File -FilePath `"`$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8weky3b8dbbwe\LocalState\Fragments\claude-code-ssh.json`" -Encoding UTF8; Write-Host 'Done. 关闭重开 Windows Terminal' -ForegroundColor Green"
Write-Host ""
Write-Host "如果你换 IP，改上面命令中的 $RemoteHost 为新 IP 即可" -ForegroundColor White
Write-Host ""
pause

# wslconf.ps1 — 写 /etc/wsl.conf（关闭 Windows PATH 注入）
# 用途：让 Claude Code / Bun 在 WSL 中不再尝试执行 Windows 程序
#
# 运行（普通用户权限即可）：
#   powershell -ExecutionPolicy Bypass -File "C:\git\ccconfig\windows-tools\wslconf\wslconf.ps1"
#
# 内部用 wsl.exe -u root 写 /etc/wsl.conf（WSL 启动配置）
# 幂等：每次覆盖写入同样内容
# 生效：必须 'wsl --shutdown' 冷启，WSL 仅启动时读一次
# 还原：手动编辑或删除 /etc/wsl.conf

$ErrorActionPreference = 'Stop'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe 不在 PATH（WSL 未安装？）"
}

# 拿当前 WSL 用户作为 default（避免环境差异）
$wslUser = (wsl.exe whoami 2>&1 | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($wslUser)) {
    throw "无法获取 WSL 用户（wsl.exe whoami 返回空）"
}

Write-Host "目标 WSL 用户: $wslUser" -ForegroundColor Cyan

# 写 /etc/wsl.conf（PowerShell here-string + bash heredoc 双层）
$rc = wsl.exe -u root -- bash -c @"
cat > /etc/wsl.conf <<'WSLCONF'
[boot]
systemd=true

[interop]
appendWindowsPath=false

[user]
default=$wslUser
WSLCONF
"@
if ($LASTEXITCODE -ne 0) { throw "wsl.exe 执行失败: exit $LASTEXITCODE" }

# 验证
$actual = wsl.exe cat /etc/wsl.conf 2>&1 | Out-String
Write-Host ""
Write-Host "✅ /etc/wsl.conf 已更新" -ForegroundColor Green
Write-Host "----- 内容 -----"
Write-Host $actual
Write-Host "----------------"
Write-Host ""
Write-Host "下一步：在 PowerShell 中运行 'wsl --shutdown' 重启 WSL 生效" -ForegroundColor Yellow
Write-Host "之后 Windows PATH 不会再注入到 WSL"

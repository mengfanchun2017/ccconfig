# Claude Code - 结束工作 (Windows PowerShell 7)
# 支持: Windows PowerShell 7, PowerShell Core

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

# 检测是否在 WSL 环境中
$IsWsl = $false
if ($env:WSL_DISTRO_NAME) {
    $IsWsl = $true
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code - 结束工作" -ForegroundColor Cyan
if ($IsWsl) {
    Write-Host "  当前系统: WSL ($env:WSL_DISTRO_NAME)" -ForegroundColor Cyan
} else {
    Write-Host "  当前系统: Windows" -ForegroundColor Cyan
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Set-Location $RepoDir

# 获取用户主目录
$UserHome = $env:USERPROFILE
Write-Host "用户主目录: $UserHome"

# 获取 Claude 配置目录
$ClaudeDir = Join-Path $UserHome ".claude"
Write-Host "Claude 配置目录: $ClaudeDir"

Write-Host ""
Write-Host "[1/4] 从本地同步配置到仓库..." -ForegroundColor Yellow

Write-Host "智能同步 settings.json..."
if (Get-Command node -ErrorAction SilentlyContinue) {
    & node "$ScriptDir\..\sync-settings.js" push
} else {
    Write-Host "⚠️  Node.js 未找到，使用直接复制方式" -ForegroundColor Yellow
    $SettingsSrc = Join-Path $ClaudeDir "settings.json"
    $SettingsDst = Join-Path $RepoDir "config\settings.json"
    if (Test-Path $SettingsSrc) {
        Copy-Item -Path $SettingsSrc -Destination $SettingsDst -Force
        Write-Host "   - settings.json 已复制"
    } else {
        Write-Host "   ⚠️  未找到 settings.json" -ForegroundColor Yellow
    }
}

Write-Host "同步 CLAUDE.md..." -ForegroundColor Yellow
# CLAUDE.md 在仓库中，由 git 管理，无需额外操作

Write-Host "✅ 配置文件收集完成" -ForegroundColor Green
Write-Host ""

Write-Host "[2/4] 检查 git 状态..." -ForegroundColor Yellow
git status --short
Write-Host ""

Write-Host "[3/4] 提交更改..." -ForegroundColor Yellow
git add .

if ($args.Count -gt 0) {
    $CommitMsg = $args[0]
} else {
    $CommitMsg = Read-Host "请输入提交信息 (默认: 更新配置)"
}
if ([string]::IsNullOrWhiteSpace($CommitMsg)) {
    $CommitMsg = "更新配置"
}
git commit -m $CommitMsg
Write-Host ""

Write-Host "[4/4] 推送到 GitHub..." -ForegroundColor Yellow
git push
Write-Host "✅ 成功推送到 GitHub" -ForegroundColor Green
Write-Host ""

Write-Host "[Memory] 同步 Memory..." -ForegroundColor Yellow

# 转换项目路径为 Claude Code 使用的目录名
$ProjectPath = $RepoDir -replace '\\', '-'
$ProjectPath = $ProjectPath -replace ':', ''
$MemoryDir = Join-Path $ClaudeDir "projects\$ProjectPath\memory"
$MemoryFile = Join-Path $MemoryDir "MEMORY.md"

if ((Test-Path $MemoryDir) -and (Test-Path $MemoryFile)) {
    $RepoMemoryDir = Join-Path $RepoDir "config\memory"
    if (-not (Test-Path $RepoMemoryDir)) {
        New-Item -ItemType Directory -Path $RepoMemoryDir -Force | Out-Null
    }
    Copy-Item -Path $MemoryFile -Destination (Join-Path $RepoMemoryDir "MEMORY.md") -Force
    git add (Join-Path $RepoMemoryDir "MEMORY.md")
    Write-Host "   - MEMORY.md 已同步"
} else {
    Write-Host "   ⚠️  未找到 MEMORY.md: $MemoryFile" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ✅ 同步完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

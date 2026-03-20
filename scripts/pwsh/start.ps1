# Claude Code - 开始工作 (Windows PowerShell 7)
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
Write-Host "  Claude Code - 开始工作" -ForegroundColor Cyan
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
Write-Host "[1/3] 从 GitHub 拉取最新配置..." -ForegroundColor Yellow
git pull
Write-Host "✅ 成功拉取最新配置" -ForegroundColor Green
Write-Host ""

Write-Host "[2/3] 智能同步 settings.json..." -ForegroundColor Yellow
if (Get-Command node -ErrorAction SilentlyContinue) {
    & node "$ScriptDir\..\sync-settings.js" pull
} else {
    Write-Host "⚠️  Node.js 未找到，使用直接复制方式" -ForegroundColor Yellow
    $SettingsSrc = Join-Path $RepoDir "config\settings.json"
    $SettingsDst = Join-Path $ClaudeDir "settings.json"
    if (Test-Path $SettingsSrc) {
        if (-not (Test-Path $ClaudeDir)) {
            New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
        }
        Copy-Item -Path $SettingsSrc -Destination $SettingsDst -Force
        Write-Host "   - settings.json 已复制"
    } else {
        Write-Host "   ⚠️  未找到 settings.json" -ForegroundColor Yellow
    }
}

Write-Host "[3/3] 同步 CLAUDE.md..." -ForegroundColor Yellow
# CLAUDE.md 位于仓库中，由 git pull 更新，无需额外复制操作

Write-Host ""
Write-Host "✅ 配置文件同步完成" -ForegroundColor Green
Write-Host ""

# 检查/创建 Memory 目录
Write-Host "检查 Memory 目录..." -ForegroundColor Yellow

# 转换项目路径为 Claude Code 使用的目录名
# C:\git -> C--git
$ProjectPath = $RepoDir -replace '\\', '-'
$ProjectPath = $ProjectPath -replace ':', ''
$MemoryDir = Join-Path $ClaudeDir "projects\$ProjectPath\memory"

if (Test-Path $MemoryDir) {
    Write-Host "   - Memory 目录已存在: $MemoryDir"
} else {
    New-Item -ItemType Directory -Path $MemoryDir -Force | Out-Null
    Write-Host "   - 已创建 Memory 目录: $MemoryDir"

    # 如果仓库中有 MEMORY.md，复制过去
    $RepoMemoryMd = Join-Path $RepoDir "memory\MEMORY.md"
    if (Test-Path $RepoMemoryMd) {
        Copy-Item -Path $RepoMemoryMd -Destination (Join-Path $MemoryDir "MEMORY.md") -Force
        Write-Host "   - 已复制 MEMORY.md 到 Memory 目录"
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ✅ 准备就绪！可以开始工作了" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "提示: 如果配置有更新，请重启 Claude Code" -ForegroundColor Gray
Write-Host ""

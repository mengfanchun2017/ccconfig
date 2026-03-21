# Claude Code - 开始工作 (Windows PowerShell)
#
# ============================================================
# 架构说明 - 双向同步机制
# ============================================================
#
# 本脚本通过符号链接实现本地配置与仓库的双向同步。
# 符号链接 = 两个路径指向同一个文件，修改任一，另一处同步变化。
#
# 同步结构：
#   settings.json  →  $env:USERPROFILE\.claude\settings.json
#   CLAUDE.md      →  $env:USERPROFILE\CLAUDE.md
#   MEMORY.md      →  $env:USERPROFILE\.claude\projects\{项目名}\memory\MEMORY.md
#
# 所有路径都链接到仓库中的源文件，实现双向同步。
# ============================================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code - 开始工作" -ForegroundColor Cyan
Write-Host "  当前系统: Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "仓库目录: $RepoDir"
Write-Host "Claude 目录: $ClaudeDir"
Write-Host ""

# ========== Git Pull ==========
Write-Host "[1/4] 从 GitHub 拉取最新配置..." -ForegroundColor Yellow
Set-Location $RepoDir
git pull
Write-Host "✅ 成功拉取最新配置" -ForegroundColor Green
Write-Host ""

# ========== settings.json 双向同步 ==========
Write-Host "[2/4] 同步 settings.json (符号链接)..." -ForegroundColor Yellow
$SettingsSrc = Join-Path $RepoDir "config\settings.json"
$SettingsDst = Join-Path $ClaudeDir "settings.json"

if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
}
if (Test-Path $SettingsDst) {
    Remove-Item $SettingsDst -Force
}
New-Item -ItemType SymbolicLink -Path $SettingsDst -Target $SettingsSrc -Force | Out-Null
Write-Host "   ✅ $SettingsDst -> $SettingsSrc" -ForegroundColor Green
Write-Host ""

# ========== CLAUDE.md 双向同步 ==========
Write-Host "[3/4] 同步 CLAUDE.md (符号链接)..." -ForegroundColor Yellow
$ClaudMdSrc = Join-Path $RepoDir "config\CLAUDE.md"
$ClaudMdDst = Join-Path $env:USERPROFILE "CLAUDE.md"

if (Test-Path $ClaudMdDst) {
    Remove-Item $ClaudMdDst -Force
}
New-Item -ItemType SymbolicLink -Path $ClaudMdDst -Target $ClaudMdSrc -Force | Out-Null
Write-Host "   ✅ $ClaudMdDst -> $ClaudMdSrc" -ForegroundColor Green
Write-Host ""

# ========== Memory 双向同步 ==========
Write-Host "[4/4] Memory 同步 (符号链接)..." -ForegroundColor Yellow

# 转换项目路径为 Claude Code 使用的目录名: C:\git -> C--git
$ProjectPath = $RepoDir -replace '\\', '-'
$ProjectPath = $ProjectPath -replace ':', ''
$MemoryDir = Join-Path $ClaudeDir "projects\$ProjectPath\memory"
$MemoryRepoPath = Join-Path $RepoDir "memory\MEMORY.md"

Write-Host "   仓库 Memory: $MemoryRepoPath"
Write-Host "   本地 Memory: $MemoryDir\MEMORY.md"

if (Test-Path $MemoryDir) {
    Write-Host "   - Memory 目录已存在: $MemoryDir"
} else {
    New-Item -ItemType Directory -Path $MemoryDir -Force | Out-Null
    Write-Host "   - 已创建 Memory 目录: $MemoryDir"
}

$MemoryDst = Join-Path $MemoryDir "MEMORY.md"
if (Test-Path $MemoryRepoPath) {
    if (Test-Path $MemoryDst) {
        Remove-Item $MemoryDst -Force
    }
    New-Item -ItemType SymbolicLink -Path $MemoryDst -Target $MemoryRepoPath -Force | Out-Null
    Write-Host "   ✅ Memory 已链接" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  仓库中未找到 Memory，跳过" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "  ✅ 准备就绪！可以开始工作了" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "提示: 所有配置已通过符号链接与仓库同步" -ForegroundColor Gray
Write-Host "      对任意文件的修改都会双向同步" -ForegroundColor Gray
Write-Host ""

# ========== 符号链接检查 ==========
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🔍 符号链接状态检查" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Test-Symlink {
    param($link, $name)
    if (Test-Path $link -PathType Link) {
        $target = Get-Item $link -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Target
        if (Test-Path $target) {
            Write-Host "   ✅ $name: 正常" -ForegroundColor Green
            return $true
        } else {
            Write-Host "   ❌ $name: 链接断开（目标不存在）" -ForegroundColor Red
            return $false
        }
    } elseif (Test-Path $link) {
        Write-Host "   ⚠️  $name: 是文件而非链接" -ForegroundColor Yellow
        return $false
    } else {
        Write-Host "   ❌ $name: 不存在" -ForegroundColor Red
        return $false
    }
}

$failed = 0
if (-not (Test-Symlink $SettingsDst "settings.json")) { $failed++ }
if (-not (Test-Symlink $ClaudMdDst "CLAUDE.md")) { $failed++ }
if (-not (Test-Symlink $MemoryDst "MEMORY.md")) { $failed++ }

Write-Host ""
if ($failed -gt 0) {
    Write-Host "❌ 符号链接检查失败" -ForegroundColor Red
} else {
    Write-Host "✅ 所有符号链接正常" -ForegroundColor Green
}
Write-Host ""

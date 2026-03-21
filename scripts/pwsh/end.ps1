# Claude Code - 结束工作 (Windows PowerShell)
#
# ============================================================
# 功能说明
# ============================================================
#
# 由于 start.ps1 已通过符号链接建立双向同步，
# 本脚本主要完成 Git 操作：
#   1. 符号链接检查 - 确保同步链路正常
#   2. git add .     - 暂存所有更改
#   3. git commit    - 提交更改
#   4. git push      - 推送到 GitHub
#
# 注意：MEMORY.md 等文件已通过符号链接同步，
#       无需额外复制操作。
# ============================================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$ClaudeDir = Join-Path $env:USERPROFILE ".claude"

# Memory 路径（Windows C:\git -> C--git）
$ProjectPath = $RepoDir -replace '\\', '-'
$ProjectPath = $ProjectPath -replace ':', ''
$MemoryDir = Join-Path $ClaudeDir "projects\$ProjectPath\memory"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code - 结束工作" -ForegroundColor Cyan
Write-Host "  当前系统: Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "仓库目录: $RepoDir"
Write-Host ""

Set-Location $RepoDir

# ========== 符号链接检查函数 ==========
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

# ========== 符号链接检查（push 前必须通过）==========
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🔍 符号链接状态检查" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$SettingsDst = Join-Path $ClaudeDir "settings.json"
$ClaudMdDst = Join-Path $env:USERPROFILE "CLAUDE.md"
$MemoryDst = Join-Path $MemoryDir "MEMORY.md"

$failed = 0
if (-not (Test-Symlink $SettingsDst "settings.json")) { $failed++ }
if (-not (Test-Symlink $ClaudMdDst "CLAUDE.md")) { $failed++ }
if (-not (Test-Symlink $MemoryDst "MEMORY.md")) { $failed++ }

Write-Host ""
if ($failed -gt 0) {
    Write-Host "❌ 符号链接检查失败，请先运行 start.ps1 修复" -ForegroundColor Red
    exit 1
}

Write-Host "✅ 符号链接检查通过" -ForegroundColor Green
Write-Host ""

# ========== Git 状态 ==========
Write-Host "[1/3] 检查 git 状态..." -ForegroundColor Yellow
git status --short
Write-Host ""

# ========== Git 提交 ==========
Write-Host "[2/3] 提交更改..." -ForegroundColor Yellow
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
Write-Host "✅ 已提交: $CommitMsg" -ForegroundColor Green
Write-Host ""

# ========== Git 推送 ==========
Write-Host "[3/3] 推送到 GitHub..." -ForegroundColor Yellow
git push
Write-Host "✅ 成功推送到 GitHub" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Green
Write-Host "  ✅ 同步完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

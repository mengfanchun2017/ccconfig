# Claude Code - 结束工作 (Windows PowerShell)
#
# ============================================================
# 功能说明
# ============================================================
#
# 由于 start.ps1 已通过符号链接建立双向同步，
# 本脚本主要完成 Git 操作：
#   1. git add .     - 暂存所有更改
#   2. git commit    - 提交更改
#   3. git push      - 推送到 GitHub
#
# 注意：MEMORY.md 等文件已通过符号链接同步，
#       无需额外复制操作。
# ============================================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code - 结束工作" -ForegroundColor Cyan
Write-Host "  当前系统: Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "仓库目录: $RepoDir"
Write-Host ""

Set-Location $RepoDir

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

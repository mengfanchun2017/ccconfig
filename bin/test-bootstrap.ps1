<#
.SYNOPSIS
  ccconfig 回归测试 — 从 tar 新建 WSL distro → 跑 bootstrap 全流程 → 结构化报告

.DESCRIPTION
  幂等、可重跑。每次 ccconfig 更新后跑一次，确认所有阶段没回归。

  重要：本脚本从不调用 wsl --unregister（破坏性），只新建独立 distro。
  历史 distro 保留在 C:\wsl\ 下，由用户手动清理。

.PARAMETER TarPath
  Ubuntu base tar 路径（默认 D:\backup\u26claudet-base.tar）

.PARAMETER Distro
  WSL 发行版名（默认 cc-<今天 YYYYMMDD>，例 cc-20260808）

.PARAMETER SkipNewDistro
  跳过新建 WSL（同名 distro 已存在时复用）

.PARAMETER EnvFile
  环境变量文件路径（含 GH_TOKEN / CCP_*_KEY），不入 git

.EXAMPLE
  .\bin\test-bootstrap.ps1

.NOTES
  必须以管理员 PowerShell 跑（wsl --import 需要）
  文件编码必须 UTF-8 with BOM（中文输出）
#>
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

param(
    [string]$TarPath = "D:\backup\u26claudet-base.tar",
    [string]$Distro = "cc-$(Get-Date -Format 'yyyyMMdd')",
    [switch]$SkipNewDistro,
    [string]$EnvFile = "$PSScriptRoot\.ccconfig-test.env.ps1"
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "ccconfig regression test"

function Step($name, $scriptBlock) {
    Write-Host ""
    Write-Host "━━━ $name ━━━" -ForegroundColor Cyan
    $stepSw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $scriptBlock
        $elapsed = $stepSw.Elapsed.TotalSeconds
        $script:reportLines += "PASS  $name  ($([math]::Round($elapsed,1))s)"
        Write-Host "[ok] $name ($([math]::Round($elapsed,1))s)" -ForegroundColor Green
    } catch {
        $elapsed = $stepSw.Elapsed.TotalSeconds
        $script:reportLines += "FAIL  $name  ($([math]::Round($elapsed,1))s)  $_"
        Write-Host "[fail] $name" -ForegroundColor Red
        Write-Host "  $_" -ForegroundColor Red
        throw
    }
}

# 管理员检查
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "[错误] 请以管理员身份运行 PowerShell" -ForegroundColor Red
    Write-Host "  右键开始菜单 → 终端(管理员) → 重新跑" -ForegroundColor Yellow
    exit 1
}

# 加载 env 文件（不入 git，.gitignore 已覆盖）
$reportLines = @()
$sw = [System.Diagnostics.Stopwatch]::StartNew()

if (Test-Path $EnvFile) {
    . $EnvFile
    Write-Host "[ok] env 文件已加载: $EnvFile" -ForegroundColor Green
} else {
    Write-Host "[warn] env 文件不存在: $EnvFile" -ForegroundColor Yellow
    Write-Host "       模板: $EnvFile.example" -ForegroundColor Yellow
    Write-Host "       命令: copy $EnvFile.example $EnvFile" -ForegroundColor Yellow
}

# 必要 env 检查
$required = @("GH_TOKEN","CCP_GH_USER","CCP_GIT_EMAIL")
foreach ($k in $required) {
    $v = (Get-Item env:$k -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrEmpty($v)) {
        Write-Host "[错误] 缺失环境变量: $k" -ForegroundColor Red
        Write-Host "  在 $EnvFile 里设: `$env:$k = `"xxx`"" -ForegroundColor Yellow
        exit 1
    }
}

# 步骤 1: 新建 WSL distro（绝不 --unregister）
Step "1/5 新建 WSL ($Distro)" {
    $wslDir = "C:\wsl\$Distro"
    $existing = wsl --list --quiet 2>$null | Select-String -SimpleMatch $Distro

    if ($existing) {
        Write-Host "  [info] distro 已存在，复用: $Distro" -ForegroundColor Yellow
        Write-Host "         路径: $wslDir" -ForegroundColor Gray
        Write-Host "         删旧请手动: Remove-Item $wslDir -Recurse -Force" -ForegroundColor Gray
    } else {
        if (-not (Test-Path $TarPath)) {
            throw "tar 不存在: $TarPath（先用 WSL 备份脚本生成）"
        }
        New-Item -ItemType Directory -Force -Path $wslDir | Out-Null
        wsl --import $Distro $wslDir $TarPath
        Write-Host "  [ok] distro 新建: $Distro" -ForegroundColor Green
        Write-Host "       路径: $wslDir" -ForegroundColor Gray

        # 设默认用户（首次导入默认是 root）
        $checkUser = wsl -d $Distro --user root -- bash -c "id $env:USERNAME" 2>$null
        if ($LASTEXITCODE -ne 0) {
            wsl -d $Distro --user root -- bash -c "useradd -m -G sudo -s /bin/bash $env:USERNAME && echo '$env:USERNAME ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$env:USERNAME" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [ok] 用户已建: $env:USERNAME" -ForegroundColor Green
            }
        }
    }
}

# 步骤 2-4: bootstrap 全流程
Step "2-4/5 Bootstrap 全流程 (gh → ccprivate → base)" {
    # 单引号字符串 + env 注入，避免转义陷阱
    $wslCmd = @'
set -euo pipefail
export GH_TOKEN='$env:GH_TOKEN'
export BOOTSTRAP_NOSUDO=1
export CCP_GH_USER='$env:CCP_GH_USER'
export CCP_GIT_EMAIL='$env:CCP_GIT_EMAIL'
export CCP_DEFAULT_LLM='$env:CCP_DEFAULT_LLM'
export CCP_LLM_DEEPSEEK_KEY='$env:CCP_LLM_DEEPSEEK_KEY'
export CCP_LLM_MINIMAX_KEY='$env:CCP_LLM_MINIMAX_KEY'
export CCP_LLM_ANTHROPIC_KEY='$env:CCP_LLM_ANTHROPIC_KEY'
export CCP_SKIP_FEISHU='$env:CCP_SKIP_FEISHU'
export CCP_SKIP_PREREQ_PROMPT=1

cd ~/git/ccconfig
git pull --ff-only 2>&1 || true
bash bootstrap-gh-auth.sh
bash init-ccprivate-repo.sh --non-interactive
bash init-base.sh all
'@
    wsl -d $Distro --user $env:USERNAME -- bash -c $wslCmd
}

# 步骤 5: 状态验证
Step "5/5 状态验证 (maintain.sh status)" {
    $wslStatusCmd = @'
export GH_TOKEN='$env:GH_TOKEN'
cd ~/git/ccconfig
bash maintain.sh status
'@
    wsl -d $Distro --user $env:USERNAME -- bash -c $wslStatusCmd
}

# 报告
Step "report 生成报告" {
    $logDir = Join-Path $PSScriptRoot "..\logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $reportPath = Join-Path $logDir "test-bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $sw.Stop()
    $summary = @"
ccconfig 回归测试报告
生成时间: $(Get-Date -Format 'o')
总耗时:   $($sw.Elapsed.ToString())
发行版:   $Distro
tar:      $TarPath

$($reportLines -join "`n")
"@
    $summary | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "  [ok] 报告已写入: $reportPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "━━━ 完成 ━━━" -ForegroundColor Cyan
$reportLines | ForEach-Object {
    if ($_ -match "^PASS") {
        Write-Host "  $_" -ForegroundColor Green
    } else {
        Write-Host "  $_" -ForegroundColor Red
    }
}
Write-Host "总耗时: $($sw.Elapsed.ToString())"
Write-Host ""
Write-Host "清理旧 distro（可选）:" -ForegroundColor Gray
Write-Host "  wsl --list --verbose" -ForegroundColor Gray
Write-Host "  Remove-Item C:\wsl\cc-<旧日期> -Recurse -Force" -ForegroundColor Gray

# 防 pause（CI 不阻塞）
if (-not $SkipNewDistro -and -not [Console]::IsInputRedirected) {
    pause
}
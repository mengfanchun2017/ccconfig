# ==============================================
# Git + GitHub CLI 环境初始化脚本 (Windows)
# 功能：安装 Git、配置 gh、克隆配置仓库
# ==============================================

$ErrorActionPreference = "Stop"

# 颜色输出
function Write-Info { param($m) Write-Host "ℹ️  $m" -ForegroundColor Cyan }
function Write-Success { param($m) Write-Host "✅ $m" -ForegroundColor Green }
function Write-Warning { param($m) Write-Host "⚠️  $m" -ForegroundColor Yellow }
function Write-Error { param($m) Write-Host "❌ $m" -ForegroundColor Red }

# -------------------------- 检查并安装 Git --------------------------
Write-Info "检查 git..."
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $gitVersion = git --version
    Write-Success "git 已安装: $gitVersion"
} else {
    Write-Warning "git 未安装，正在尝试安装..."
    winget install Git.Git --accept-package-agreements --accept-source-agreements -h
    if ($LASTEXITCODE -eq 0) {
        Write-Success "git 安装完成"
    } else {
        Write-Error "git 安装失败，请手动安装后重试"
        exit 1
    }
}

# 刷新 PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# -------------------------- 检查并安装 gh --------------------------
Write-Info "检查 GitHub CLI (gh)..."
$ghCmd = Get-Command gh -ErrorAppearance -ErrorAction SilentlyContinue
if ($ghCmd) {
    $ghVersion = gh --version
    Write-Success "gh 已安装: $ghVersion"
} else {
    Write-Warning "gh 未安装，正在安装..."
    winget install GitHub.cli --accept-package-agreements --accept-source-agreements -h
    if ($LASTEXITCODE -eq 0) {
        Write-Success "gh 安装完成"
    } else {
        Write-Error "gh 安装失败，请手动安装后重试"
        exit 1
    }
}

# 刷新 PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# -------------------------- GitHub 登录 --------------------------
Write-Info "检查 GitHub 登录状态..."
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -eq 0) {
    $userLogin = gh api user --jq '.login'
    Write-Success "已登录 GitHub: $userLogin"
} else {
    Write-Info "需要登录 GitHub..."
    gh auth login

    # 等待验证完成
    Write-Info "等待浏览器验证完成..."
    $maxWait = 60
    $waited = 0
    while ($waited -lt $maxWait) {
        Start-Sleep 2
        $waited += 2
        if ((gh auth status 2>&1) -and $LASTEXITCODE -eq 0) {
            $userLogin = gh api user --jq '.login'
            Write-Success "登录成功: $userLogin"
            break
        }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "登录超时，请重试"
        exit 1
    }
}

# -------------------------- 获取仓库信息 --------------------------
Write-Host ""
Write-Host "=========================================="
Write-Host "📦 仓库信息"
Write-Host "=========================================="
Write-Host ""

$defaultRepo = "<your-github-username>/claude-config"
$repoInput = Read-Host "GitHub 用户名/仓库名 [默认: $defaultRepo]"
$REPO = if ($repoInput) { $repoInput } else { $defaultRepo }

$defaultTarget = "$env:USERPROFILE\git\claude-config"
$targetInput = Read-Host "克隆到目录 [默认: $defaultTarget]"
$TARGET_DIR = if ($targetInput) { $targetInput } else { $defaultTarget }

# 确保目标目录存在
$parentDir = Split-Path $TARGET_DIR -Parent
if (-not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

# -------------------------- 克隆仓库 --------------------------
Write-Info "正在克隆仓库..."
Write-Info "仓库: $REPO"
Write-Info "目标: $TARGET_DIR"

# 使用 gh repo clone 或 git clone
if (gh repo clone $REPO $TARGET_DIR 2>&1) {
    Write-Success "克隆完成!"
} else {
    # 如果 gh 失败，尝试 git clone
    Write-Warning "gh repo clone 失败，尝试 git clone..."
    if (git clone "https://github.com/$REPO.git" $TARGET_DIR 2>&1) {
        Write-Success "克隆完成!"
    } else {
        Write-Error "克隆失败，请检查网络或仓库地址"
        exit 1
    }
}

# -------------------------- 安装 Claude Code --------------------------
Write-Host ""
Write-Host "=========================================="
Write-Host "📦 安装 Claude Code"
Write-Host "=========================================="
Write-Host ""

# 检查 Claude Code 是否已安装
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    $claudeVersion = claude --version 2>&1
    Write-Success "Claude Code 已安装: $claudeVersion"
} else {
    Write-Info "正在安装 Claude Code..."

    # 尝试使用 npm 全局安装
    Write-Info "使用 npm 全局安装..."
    npm install -g @anthropic-ai/claude-code

    if ($LASTEXITCODE -eq 0) {
        Write-Success "Claude Code 安装完成"
    } else {
        Write-Warning "npm 安装失败，尝试其他方式..."

        # 尝试使用 PowerShell 安装脚本
        Write-Info "尝试使用官方安装脚本..."
        try {
            Invoke-WebRequest -Uri "https://claude.ai/install.ps1" -UseBasicParsing | Invoke-Expression
        } catch {
            Write-Warning "官方安装脚本失败，请手动安装: npm install -g @anthropic-ai/claude-code"
        }
    }
}

# 刷新 PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# 验证安装
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    Write-Success "Claude Code 版本: $(claude --version 2>&1)"
}

# -------------------------- 完成 --------------------------
Write-Host ""
Write-Host "🎉 环境初始化完成！" -ForegroundColor Green
Write-Host ""
Write-Host "仓库位置: $TARGET_DIR"
$claudeVersion = claude --version 2>&1
Write-Host "Claude Code: $claudeVersion"
Write-Host ""
Write-Host "下一步："
Write-Host "  cd $TARGET_DIR"
Write-Host "  .\scripts\pwsh\initclaude.ps1  # 配置 LLM API"
Write-Host ""

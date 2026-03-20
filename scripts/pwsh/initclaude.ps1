# ==============================================
# Claude Code 配置脚本 (Windows)
# 功能：初始化或更新 Claude Code 的自定义 LLM API 配置
# 支持：MINIMAX
# ==============================================

$ErrorActionPreference = "Stop"

# 颜色输出
function Write-Info { param($m) Write-Host "ℹ️  $m" -ForegroundColor Cyan }
function Write-Success { param($m) Write-Host "✅ $m" -ForegroundColor Green }
function Write-Warning { param($m) Write-Host "⚠️  $m" -ForegroundColor Yellow }
function Write-Error { param($m) Write-Host "❌ $m" -ForegroundColor Red }

# 配置目录和文件
$CLAUDE_DIR = "$env:USERPROFILE\.claude"
$RepoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CONFIG_FILE = Join-Path $RepoDir "config\apillm.json"

# -------------------------- 模式选择 --------------------------
if (-not $args) {
    Write-Host "请选择操作模式："
    Write-Host "  1) 初始化 (init)  - 首次配置"
    Write-Host "  2) 更新 (update)  - 修改现有配置"
    Write-Host ""
    $choice = Read-Host "请输入选项 [1]"
    if (-not $choice) { $choice = "1" }
    $MODE = if ($choice -eq "1") { "init" } else { "update" }
} else {
    $MODE = $args[0]
}

Write-Host ""
if ($MODE -eq "init") {
    Write-Host "🚀 开始初始化 Claude Code 配置..."
} else {
    Write-Host "🚀 开始更新 Claude Code 配置..."
}
Write-Host "=========================================="
Write-Host ""

# -------------------------- 厂商选择 --------------------------
Write-Host "请选择 LLM 订阅厂商："
Write-Host "  1) MINIMAX"
Write-Host ""
$vendorChoice = Read-Host "请输入选项 [1]"
if (-not $vendorChoice) { $vendorChoice = "1" }

if ($vendorChoice -eq "1") {
    $VENDOR = "MINIMAX"
    Write-Success "已选择: $VENDOR"
} else {
    Write-Error "无效选项"
    exit 1
}
Write-Host ""

# -------------------------- 配置获取 --------------------------
$IMPORTED = $false
$BASE_URL = ""
$API_KEY = ""
$MODEL_NAME = ""

# 读取 apillm.json 配置模板
if (Test-Path $CONFIG_FILE) {
    $configContent = Get-Content $CONFIG_FILE -Raw | ConvertFrom-Json

    $BASE_URL = $configContent.base_url
    $MODEL_NAME = $configContent.model_name

    Write-Host "📋 $VENDOR 配置模板："
    Write-Host "  API 地址: $BASE_URL"
    Write-Host "  模型:     $MODEL_NAME"
    Write-Host ""

    # 逐条询问用户
    Write-Host "请逐项确认或修改配置："
    Write-Host ""

    # Base URL
    $inputUrl = Read-Host "API 地址 [$BASE_URL]"
    if ($inputUrl) { $BASE_URL = $inputUrl }

    # API Key
    Write-Host ""
    Write-Host "API Key 示例: sk-cp-xxx..."
    $inputKey = Read-Host "API Key" -AsSecureString
    $API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputKey))

    # Model Name
    Write-Host ""
    $inputModel = Read-Host "模型名称 [$MODEL_NAME]"
    if ($inputModel) { $MODEL_NAME = $inputModel }

    $IMPORTED = $true
    Write-Info "已根据 $VENDOR 配置模板设置参数"
    Write-Host ""
}

# 如果没有 apillm.json，使用默认值
if (-not $IMPORTED) {
    $BASE_URL = "https://api.minimaxi.com/anthropic"
    $inputUrl = Read-Host "API 基础地址 [$BASE_URL]"
    if ($inputUrl) { $BASE_URL = $inputUrl }

    Write-Host ""
    Write-Host "API Key 示例: sk-cp-xxx..."
    $inputKey = Read-Host "API Key" -AsSecureString
    $API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($inputKey))

    Write-Host ""
    $MODEL_NAME = "MiniMax-M2.7"
    $inputModel = Read-Host "模型名称 [$MODEL_NAME]"
    if ($inputModel) { $MODEL_NAME = $inputModel }
}

# 验证
if (-not $BASE_URL -or -not $API_KEY -or -not $MODEL_NAME) {
    Write-Error "配置不能为空"
    exit 1
}

Write-Host ""
Write-Info "📋 当前配置："
Write-Host "  API 地址: $BASE_URL"
Write-Host "  API Key:  $($API_KEY.Substring(0, [Math]::Min(15, $API_KEY.Length)))..."
Write-Host "  模型:     $MODEL_NAME"
Write-Host ""

$confirm = Read-Host "确认? [y/N]"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host "已取消"
    exit 0
}

# -------------------------- 写入配置 --------------------------
if (-not (Test-Path $CLAUDE_DIR)) {
    New-Item -ItemType Directory -Path $CLAUDE_DIR -Force | Out-Null
}

# 1. 跳过登录引导 + API 配置 (写入 ~/.claude.json - 不参与同步)
$claudeJsonPath = "$env:USERPROFILE\.claude.json"
$userConfig = @{
    hasCompletedOnboarding = $true
    ANTHROPIC_BASE_URL = $BASE_URL
    ANTHROPIC_AUTH_TOKEN = $API_KEY
    ANTHROPIC_MODEL = $MODEL_NAME
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
}

if (Test-Path $claudeJsonPath) {
    # 合并现有配置
    $existing = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json
    $existing.PSObject.Properties | ForEach-Object { $userConfig[$_.Name] = $_.Value }
}

$userConfig | ConvertTo-Json -Depth 3 | Set-Content $claudeJsonPath -Encoding UTF8
Write-Success "已配置 Claude Code 设置（写入 ~/.claude.json，不参与同步）"

# 3. 设置环境变量（永久）
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $BASE_URL, "User")
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", $API_KEY, "User")
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_MODEL", $MODEL_NAME, "User")
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1", "User")
Write-Success "已设置环境变量（永久生效）"

# 当前会话也设置
$env:ANTHROPIC_BASE_URL = $BASE_URL
$env:ANTHROPIC_AUTH_TOKEN = $API_KEY
$env:ANTHROPIC_MODEL = $MODEL_NAME
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"

# -------------------------- 完成 --------------------------
Write-Host ""
if ($MODE -eq "init") {
    Write-Host "🎉 Claude Code 初始化完成！" -ForegroundColor Green
} else {
    Write-Host "🎉 Claude Code 配置更新完成！" -ForegroundColor Green
}
Write-Host ""
Write-Host "下一步操作："
Write-Host "  1. 重启终端或重新打开 Claude Code"
Write-Host "  2. 输入 'claude' 开始使用！"
Write-Host ""
Write-Warning "API 密钥仅写入 Claude 配置，未保存到 apillm.json"
Write-Host ""

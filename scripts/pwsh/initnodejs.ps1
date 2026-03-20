# Node.js 安装脚本
# 用途：为 Claude Code MCP 安装 Node.js 环境（npm/npx 需要）
#
# 使用方法：
#   .\scripts\pwsh\install-nodejs.ps1
#
# 此脚本会：
#   1. 检测 Node.js 是否已安装
#   2. 下载并安装 Node.js 20.x LTS 到 $env:LOCALAPPDATA\nodejs\（Windows）
#      或 ~/.local/（Linux WSL）
#   3. 创建 node, npm, npx 符号链接或 PATH 配置
#
# 安装完成后运行 mcpcheck 安装 MCP：
#   .\scripts\pwsh\mcpcheck.ps1

$ErrorActionPreference = "Stop"

$NODE_VERSION = "20.11.0"
$DOWNLOAD_URL = "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-win-x64.zip"
$TARBALL = "$env:TEMP\node.zip"

# 颜色函数
function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

# 检查是否已安装
function Test-NodeInstalled {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $version = node --version 2>$null
        Write-Info "Node.js 已安装: $version"
        return $true
    }
    return $false
}

# 下载 Node.js
function Install-NodeJs {
    Write-Info "下载 Node.js v${NODE_VERSION}..."
    Write-Info "URL: $DOWNLOAD_URL"

    try {
        # 如果是 Linux/WSL
        if ($IsLinux -or (Test-Path "/usr/bin/wsl.exe")) {
            $linuxUrl = "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz"
            $tarball = "$env:TEMP/node.tar.gz"
            Write-Info "检测到 Linux 环境，使用 Linux 版本"
            Invoke-WebRequest -Uri $linuxUrl -OutFile $tarball -UseBasicParsing
            tar -xzf $tarball -C "$env:HOME/.local/"
            Remove-Item $tarball -Force

            $nodeDir = "$env:HOME/.local/node-v${NODE_VERSION}-linux-x64"
            $binDir = "$env:HOME/.local/bin"
            New-Item -ItemType Directory -Force -Path $binDir | Out-Null

            # 创建符号链接
            cmd /c "mklink $binDir\node.exe $nodeDir\bin\node" 2>$null
            cmd /c "mklink $binDir\npm.exe $nodeDir\bin\npm" 2>$null
            cmd /c "mklink $binDir\npx.exe $nodeDir\bin\npx" 2>$null
        } else {
            # Windows
            Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $TARBALL -UseBasicParsing
            Expand-Archive -Path $TARBALL -DestinationPath $env:LOCALAPPDATA -Force
            Remove-Item $TARBALL -Force

            $nodeDir = "$env:LOCALAPPDATA\nodejs"
            $binDir = "$env:LOCALAPPDATA\nodejs\bin"

            # 添加到 PATH（临时）
            $env:PATH = "$binDir;$env:PATH"
        }

        Write-Info "安装完成"
        return $true
    } catch {
        Write-Err "安装失败: $_"
        return $false
    }
}

# 验证安装
function Verify-Installation {
    Write-Info "验证安装..."
    Write-Host ""
    Write-Host "  node: $(node --version)"
    Write-Host "  npm:  $(npm --version)"
    if (Get-Command npx -ErrorAction SilentlyContinue) {
        Write-Host "  npx:  $(npx --version)"
    }
    Write-Host ""
}

# 主流程
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Node.js 安装脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (Test-NodeInstalled) {
    $confirm = Read-Host "Node.js 已存在，是否重新安装? [y/N]"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Info "跳过安装"
        exit 0
    }
}

if (Install-NodeJs) {
    Verify-Installation
} else {
    Write-Err "安装失败"
    exit 1
}

# MCP 环境准备脚本
# 用途：为 Claude Code MCP 安装运行时环境依赖
#
# 使用方法：
#   .\scripts\pwsh\initmcp.ps1
#
# 此脚本会检测并安装 MCP 服务器所需的依赖：
#   1. Node.js (用于 npm/npx-based MCP 服务器)
#   2. uv (用于 Python-based MCP 服务器)
#   3. Playwright (用于浏览器自动化)
#   4. 中文字体 (用于显示中文网页)
#
# 安装完成后，请运行 mcpcheck.ps1 安装具体的 MCP 服务器：
#   .\scripts\pwsh\mcpcheck.ps1
#
# MCP 服务器安装完成后，在 Claude Code 中执行 /mcp 添加服务器

$ErrorActionPreference = "Stop"

# 版本
$NODE_VERSION = "20.11.0"
$UV_VERSION = "0.10.12"

# 目录
$LOCAL_DIR = "$env:HOME/.local"
$BIN_DIR = "$LOCAL_DIR/bin"
$NODE_DIR = "$LOCAL_DIR/node-v${NODE_VERSION}-linux-x64"
$UV_DIR = "$LOCAL_DIR/uv-${UV_VERSION}-x86_64-unknown-linux-gnu"

# 颜色函数
function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }
function Write-Section { param($m) Write-Host "=== $m ===" -ForegroundColor Cyan }

# 检查命令是否存在
function Test-CommandExists {
    param($cmd)
    $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

# ========== Node.js ==========
function Test-NodeInstalled {
    if (Test-CommandExists "node") {
        $version = node --version 2>$null
        Write-Info "Node.js 已安装: $version"
        return $true
    }
    return $false
}

function Install-NodeJs {
    Write-Section "安装 Node.js"

    # 检测是否是 Linux/WSL
    $IsLinux = $IsLinux -or (Test-Path "/usr/bin/wsl.exe")

    if ($IsLinux) {
        $url = "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz"
        $tarball = "$env:TEMP/node.tar.gz"

        Write-Info "检测到 Linux/WSL 环境"
        Write-Info "下载 Node.js v${NODE_VERSION}..."
        Write-Info "URL: $url"

        try {
            Invoke-WebRequest -Uri $url -OutFile $tarball -UseBasicParsing
            tar -xzf $tarball -C "$LOCAL_DIR/"
            Remove-Item $tarball -Force

            New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null

            # 创建符号链接
            cmd /c "mklink $BIN_DIR/node.exe $NODE_DIR/bin/node" 2>$null
            cmd /c "mklink $BIN_DIR/npm.exe $NODE_DIR/bin/npm" 2>$null
            cmd /c "mklink $BIN_DIR/npx.exe $NODE_DIR/bin/npx" 2>$null

            Write-Info "Node.js 安装完成"
            return $true
        } catch {
            Write-Err "Node.js 安装失败: $_"
            return $false
        }
    } else {
        # Windows
        $url = "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-win-x64.zip"
        $zipball = "$env:TEMP/node.zip"

        Write-Info "检测到 Windows 环境"
        Write-Info "下载 Node.js v${NODE_VERSION}..."
        Write-Info "URL: $url"

        try {
            Invoke-WebRequest -Uri $url -OutFile $zipball -UseBasicParsing
            Expand-Archive -Path $zipball -DestinationPath $LOCAL_DIR -Force
            Remove-Item $zipball -Force

            $nodeDir = "$LOCAL_DIR/node-v${NODE_VERSION}-win-x64"
            $binDir = "$nodeDir\bin"

            # 添加到 PATH（当前会话）
            $env:PATH = "$binDir;$env:PATH"

            Write-Info "Node.js 安装完成"
            Write-Info "注意: Windows 版本需要手动添加到 PATH"
            return $true
        } catch {
            Write-Err "Node.js 安装失败: $_"
            return $false
        }
    }
}

function Verify-NodeJs {
    Write-Info "Node.js 验证:"
    Write-Host "  node: $(node --version)"
    Write-Host "  npm:  $(npm --version)"
    if (Test-CommandExists "npx") {
        Write-Host "  npx:  $(npx --version)"
    }
    Write-Host ""
}

# ========== uv (Python 包管理器) ==========
function Test-UvInstalled {
    if (Test-CommandExists "uvx" -or Test-CommandExists "uv") {
        $version = uvx --version 2>$null
        if (-not $version) { $version = uv --version 2>$null }
        Write-Info "uv 已安装: $version"
        return $true
    }
    return $false
}

function Install-Uv {
    Write-Section "安装 uv"

    # 检测架构
    $arch = uname -m
    if ($arch -eq "x86_64") {
        $archStr = "x86_64-unknown-linux-gnu"
    } elseif ($arch -eq "aarch64") {
        $archStr = "aarch64-unknown-linux-gnu"
    } else {
        Write-Warn "不支持的架构: $arch，尝试 x86_64"
        $archStr = "x86_64-unknown-linux-gnu"
    }

    $url = "https://astral.sh/uv/${UV_VERSION}/uv-${UV_VERSION}-${archStr}.tar.gz"
    $tarball = "$env:TEMP/uv.tar.gz"

    Write-Info "下载 uv v${UV_VERSION}..."
    Write-Info "URL: $url"

    try {
        Invoke-WebRequest -Uri $url -OutFile $tarball -UseBasicParsing
        tar -xzf $tarball -C "$LOCAL_DIR/"

        New-Item -ItemType Directory -Force -Path $BIN_DIR | Out-Null

        # 创建符号链接
        cmd /c "mklink $BIN_DIR\uv.exe $UV_DIR\uv" 2>$null
        cmd /c "mklink $BIN_DIR\uvx.exe $UV_DIR\uvx" 2>$null

        Remove-Item $tarball -Force
        Write-Info "uv 安装完成"
        return $true
    } catch {
        Write-Err "uv 安装失败: $_"
        return $false
    }
}

function Verify-Uv {
    Write-Info "uv 验证:"
    if (Test-CommandExists "uv") {
        Write-Host "  uv:  $(uv --version)"
    }
    if (Test-CommandExists "uvx") {
        Write-Host "  uvx: $(uvx --version)"
    }
    Write-Host ""
}

# ========== Playwright ==========
function Test-PlaywrightInstalled {
    try {
        $version = npx playwright --version 2>$null
        if ($version) {
            Write-Info "Playwright 已安装: $version"
            return $true
        }
    } catch {}
    return $false
}

function Install-PlaywrightBrowsers {
    Write-Section "安装 Playwright 浏览器"
    Write-Info "安装 Playwright chromium (官方推荐)..."
    try {
        npx playwright install chromium 2>&1 | Out-Null
        Write-Info "Chromium 安装成功"
    } catch {
        Write-Warn "Chromium 安装可能需要管理员权限"
    }
}

function Verify-Playwright {
    Write-Info "Playwright 验证:"
    if (Test-CommandExists "npx") {
        $version = npx playwright --version 2>$null
        Write-Host "  npx playwright: $($version ? $version : '未安装')"
        $browserCount = (Get-ChildItem "$env:HOME/.cache/ms-playwright" -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host "  浏览器缓存: $browserCount 个"
    }
    Write-Host ""
}

# ========== 中文字体 ==========
function Test-ChineseFontsInstalled {
    try {
        $fonts = fc-list :lang=zh 2>$null
        if ($fonts -and $fonts -match '.+') {
            return $true
        }
    } catch {}
    return $false
}

function Install-ChineseFonts {
    Write-Section "安装中文字体"
    Write-Info "安装 Noto CJK 中文字体..."
    try {
        sudo apt-get update && sudo apt-get install -y fonts-noto-cjk fontconfig 2>&1 | Out-Null
        fc-cache -f 2>$null
        Write-Info "中文字体安装成功"
    } catch {
        Write-Warn "需要 sudo 权限，请手动执行:"
        Write-Host "  sudo apt-get install fonts-noto-cjk fontconfig"
    }
}

function Verify-Fonts {
    Write-Info "字体验证:"
    try {
        $count = (fc-list :lang=zh 2>$null | Measure-Object -Line).Lines
        Write-Host "  中文字体数量: $count"
    } catch {
        Write-Host "  中文字体数量: 0"
    }
    Write-Host ""
}

# ========== 主流程 ==========
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MCP 环境准备脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "此脚本将安装 MCP 服务器所需的运行时环境：" -ForegroundColor White
Write-Host "  1. Node.js - 用于 npm/npx-based MCP 服务器"
Write-Host "  2. uv - 用于 Python-based MCP 服务器"
Write-Host "  3. Playwright - 用于浏览器自动化"
Write-Host "  4. 中文字体 - 用于显示中文网页"
Write-Host ""
Write-Host "安装完成后请运行 mcpcheck.ps1 安装具体的 MCP 服务器"
Write-Host ""

# Node.js
Write-Section "检测 Node.js"
if (Test-NodeInstalled) {
    Write-Warn "跳过 Node.js 安装（已存在）"
    Verify-NodeJs
} else {
    $null = Install-NodeJs
    Verify-NodeJs
}

# uv
Write-Section "检测 uv"
if (Test-UvInstalled) {
    Write-Warn "跳过 uv 安装（已存在）"
    Verify-Uv
} else {
    $null = Install-Uv
    Verify-Uv
}

# Playwright
Write-Section "检测 Playwright"
if (Test-PlaywrightInstalled) {
    Write-Warn "跳过 Playwright 安装（已存在）"
} else {
    Write-Info "安装 Playwright..."
    npm install -g playwright -ErrorAction SilentlyContinue | Out-Null
}
Verify-Playwright

# Playwright 浏览器
Write-Section "检测 Playwright 浏览器"
$chromeExists = Test-Path "$env:HOME/.cache/ms-playwright/chromium-*/chrome-linux/chrome" -ErrorAction SilentlyContinue
$headlessExists = Test-Path "$env:HOME/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux/chrome" -ErrorAction SilentlyContinue
if ($chromeExists -or $headlessExists) {
    Write-Warn "跳过浏览器安装（已存在）"
} else {
    Install-PlaywrightBrowsers
}
Verify-Playwright

# 中文字体
Write-Section "检测中文字体"
if (Test-ChineseFontsInstalled) {
    Write-Warn "跳过中文字体安装（已存在）"
} else {
    Install-ChineseFonts
}
Verify-Fonts

Write-Section "安装完成"
Write-Info "MCP 环境已准备就绪"
Write-Host ""
Write-Host "下一步：" -ForegroundColor White
Write-Host "  1. 运行 mcpcheck.ps1 安装具体的 MCP 服务器"
Write-Host "     .\scripts\pwsh\mcpcheck.ps1"
Write-Host ""
Write-Host "  2. 在 Claude Code 中执行 /mcp 添加服务器"
Write-Host ""

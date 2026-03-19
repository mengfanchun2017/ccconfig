# Claude Code MCP 自动更新脚本
# 作用：对比 mcplist.json，安装本地缺失的 MCP

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$McpListFile = Join-Path $RepoDir "mcplist.json"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code MCP 自动更新" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查 mcplist.json 是否存在
if (-not (Test-Path $McpListFile)) {
    Write-Host "❌ 未找到 mcplist.json" -ForegroundColor Red
    exit 1
}

# 读取 MCP 列表
$McpList = Get-Content $McpListFile -Raw | ConvertFrom-Json

# 获取已安装的 MCP 列表
Write-Host "检查已安装的 MCP..." -ForegroundColor Yellow
$InstalledMcp = @{}
try {
    $result = claude mcp list 2>&1
    if ($result -match "No MCP servers") {
        Write-Host "   当前没有安装任何 MCP" -ForegroundColor Gray
    } else {
        # 解析已安装的 MCP
        $result -split "`n" | ForEach-Object {
            if ($_ -match "^\s*(\S+)") {
                $InstalledMcp[$Matches[1]] = $true
            }
        }
    }
} catch {
    Write-Host "   ⚠️ 无法获取 MCP 列表: $_" -ForegroundColor Yellow
}

Write-Host "   已安装: $($InstalledMcp.Keys -join ', ')" -ForegroundColor Gray
Write-Host ""

# 遍历 MCP 列表，安装缺失的
$ToInstall = @()
$ToConfig = @()

foreach ($mcp in $McpList.mcp) {
    Write-Host "检查: $($mcp.name) - $($mcp.description)" -ForegroundColor White

    if ($InstalledMcp.ContainsKey($mcp.name)) {
        Write-Host "   ✅ 已安装" -ForegroundColor Green
        continue
    }

    if ($mcp.type -eq "http") {
        # HTTP 类型的 MCP
        Write-Host "   ⏳ 需要配置 (HTTP)" -ForegroundColor Cyan
        $ToConfig += $mcp
    } else {
        # stdio 类型的 MCP
        Write-Host "   ❌ 未安装，需要安装" -ForegroundColor Yellow
        $ToInstall += $mcp
    }
}

Write-Host ""

# 安装缺失的 MCP
if ($ToInstall.Count -gt 0) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  开始安装 MCP..." -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    foreach ($mcp in $ToInstall) {
        Write-Host ""
        Write-Host "安装: $($mcp.name)" -ForegroundColor White
        Write-Host "命令: $($mcp.install)" -ForegroundColor Gray

        try {
            # 解析命令
            $parts = $mcp.install -split ' '
            $cmd = $parts[0]
            $args = $parts[1..($parts.Length - 1)]

            # 执行安装
            claude mcp add $mcp.name -- @args
            Write-Host "   ✅ 安装成功" -ForegroundColor Green
        } catch {
            Write-Host "   ❌ 安装失败: $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "✅ 所有 MCP 都已安装" -ForegroundColor Green
}

# 提示需要配置的 HTTP MCP
if ($ToConfig.Count -gt 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  以下 MCP 需要手动配置（包含敏感信息）:" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    foreach ($mcp in $ToConfig) {
        Write-Host "  - $($mcp.name): $($mcp.description)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "提示: HTTP 类型的 MCP 包含敏感信息，请在本地 .claude.json 中配置" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MCP 更新完成!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Claude Code MCP 检查脚本
# 功能：对比 mcplist.json 与当前环境，提供专业交互选项

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$McpListFile = Join-Path $RepoDir "mcplist.json"

# 颜色函数
function Write-Title { param($m) Write-Host "`n========================================" -ForegroundColor Cyan; Write-Host "  $m" -ForegroundColor Cyan; Write-Host "========================================`n" -ForegroundColor Cyan }
function Write-Section { param($m) Write-Host "`n【$m】" -ForegroundColor Yellow }
function Write-Item { param($m) Write-Host "  $m" -ForegroundColor White }
function Write-Good { param($m) Write-Host "  $m" -ForegroundColor Green }
function Write-Bad { param($m) Write-Host "  $m" -ForegroundColor Red }
function Write-Info { param($m) Write-Host "  $m" -ForegroundColor Gray }

# 检查 mcplist.json
if (-not (Test-Path $McpListFile)) {
    Write-Bad "❌ 未找到 mcplist.json"
    exit 1
}

$McpList = Get-Content $McpListFile -Raw | ConvertFrom-Json

# 获取当前已安装的 MCP
$InstalledMcp = @{}
try {
    $result = claude mcp list 2>&1
    $result -split "`n" | ForEach-Object {
        if ($_ -match "^\s*(\S+):") {
            $InstalledMcp[$Matches[1]] = $true
        }
    }
} catch {
    Write-Info "⚠️ 无法获取 MCP 列表: $_"
}

# ========== 对比分析 ==========
$MissingFromList = @()   # 列表有但环境无
$ExtraInEnv = @()        # 环境有但列表无
$Matched = @()           # 列表和环境都有的

foreach ($mcp in $McpList.mcp) {
    if ($InstalledMcp.ContainsKey($mcp.name)) {
        $Matched += $mcp
    } else {
        $MissingFromList += $mcp
    }
}

foreach ($name in $InstalledMcp.Keys) {
    $found = $false
    foreach ($mcp in $McpList.mcp) {
        if ($mcp.name -eq $name) { $found = $true; break }
    }
    if (-not $found) { $ExtraInEnv += $name }
}

# ========== 显示结果 ==========
Write-Title "Claude Code MCP 检查"

# 匹配的部分
if ($Matched.Count -gt 0) {
    Write-Section "✅ 列表与环境一致"
    foreach ($mcp in $Matched) {
        Write-Good "✓ $($mcp.name): $($mcp.description)"
    }
}

# 缺失的部分
if ($MissingFromList.Count -gt 0) {
    Write-Section "❌ 列表中有但环境缺失"
    foreach ($mcp in $MissingFromList) {
        $type = if ($mcp.type -eq "http") { "[HTTP]" } else { "[STDIO]" }
        Write-Item "$($mcp.name) - $($mcp.description) $type"
    }
}

# 多出的部分
if ($ExtraInEnv.Count -gt 0) {
    Write-Section "⚠️ 环境中有但列表缺失"
    foreach ($name in $ExtraInEnv) {
        Write-Item $name
    }
}

# ========== 交互菜单 ==========
if ($MissingFromList.Count -eq 0 -and $ExtraInEnv.Count -eq 0) {
    Write-Title "检查完成"
    Write-Good "✅ 列表与环境完全一致，无需操作"
    exit 0
}

Write-Title "请选择操作"

Write-Host "  1) 安装所有缺失的 MCP 到现有环境" -ForegroundColor White
Write-Host "  2) 补充缺失项到 mcplist.json" -ForegroundColor White

if ($ExtraInEnv.Count -gt 0) {
    Write-Host "  3) 双向同步（安装+补充）" -ForegroundColor White
}

Write-Host "  4) 单独安装某个 MCP（按名称选择）" -ForegroundColor White
Write-Host "  5) 单独添加到列表（按名称选择）" -ForegroundColor White
Write-Host "  0) 跳过，不做任何修改" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "请输入选项 [0-5]"

switch ($choice) {
    "1" {
        # 安装缺失的 MCP 到环境
        Write-Title "安装 MCP 到环境"
        $installed = 0
        $skipped = 0

        foreach ($mcp in $MissingFromList) {
            if ($mcp.type -eq "http") {
                Write-Info "⏭ $($mcp.name): HTTP 类型需手动配置，跳过"
                $skipped++
                continue
            }

            Write-Host "安装: $($mcp.name) ..." -NoNewline
            try {
                $parts = $mcp.install -split ' '
                $args = $parts[1..($parts.Length - 1)]
                claude mcp add $mcp.name -- @args 2>&1 | Out-Null
                Write-Good " ✅"
                $installed++
            } catch {
                Write-Bad " ❌ $_"
            }
        }

        Write-Host ""
        Write-Good "✅ 完成：已安装 $installed 个，跳过 $skipped 个（HTTP类型）"
    }

    "2" {
        # 补充缺失项到 mcplist.json
        Write-Title "补充到 mcplist.json"

        foreach ($name in $ExtraInEnv) {
            Write-Host "添加: $name ..." -NoNewline

            # 尝试获取 MCP 信息（这里用简单方式）
            $newMcp = @{
                name = $name
                description = "（待补充）"
                type = "http"
            }

            $McpList.mcp += $newMcp
            Write-Good " ✅"
        }

        # 保存文件
        $McpList | ConvertTo-Json -Depth 10 | Set-Content $McpListFile -Encoding UTF8
        Write-Host ""
        Write-Good "✅ 已更新 mcplist.json，请补充描述信息"
    }

    "3" {
        if ($ExtraInEnv.Count -eq 0) {
            Write-Bad "❌ 没有多出的项目，无法双向同步"
            exit 1
        }

        # 双向同步
        Write-Title "双向同步"

        # 先补充列表
        Write-Info "1/2: 补充列表..."
        foreach ($name in $ExtraInEnv) {
            $McpList.mcp += @{
                name = $name
                description = "（待补充）"
                type = "http"
            }
        }
        $McpList | ConvertTo-Json -Depth 10 | Set-Content $McpListFile -Encoding UTF8
        Write-Good "✅ 列表已更新"

        # 再安装缺失
        Write-Info "2/2: 安装缺失..."
        $installed = 0
        foreach ($mcp in $MissingFromList) {
            if ($mcp.type -eq "http") { continue }
            try {
                $parts = $mcp.install -split ' '
                $args = $parts[1..($parts.Length - 1)]
                claude mcp add $mcp.name -- @args 2>&1 | Out-Null
                $installed++
            } catch { }
        }
        Write-Good "✅ 完成：安装 $installed 个，列表 +$($ExtraInEnv.Count) 个"
    }

    "4" {
        # 单独安装某个 MCP
        Write-Title "单独安装 MCP"

        Write-Section "可安装的 MCP（不在环境中）:"
        $i = 1
        $installable = @()
        foreach ($mcp in $MissingFromList) {
            if ($mcp.type -eq "http") { continue }
            Write-Host "  $i) $($mcp.name) - $($mcp.description)" -ForegroundColor White
            $installable += @{index=$i; mcp=$mcp}
            $i++
        }

        if ($installable.Count -eq 0) {
            Write-Info "没有可安装的 MCP"
            exit 0
        }

        Write-Host ""
        $sel = Read-Host "请输入编号 [1-$($installable.Count)]，或 0 取消"

        if ($sel -eq "0" -or $sel -eq "") {
            Write-Info "已取消"
            exit 0
        }

        $selected = $installable | Where-Object { $_.index -eq [int]$sel }
        if ($selected) {
            $mcp = $selected.mcp
            Write-Host "安装: $($mcp.name) ..." -NoNewline
            try {
                $parts = $mcp.install -split ' '
                $args = $parts[1..($parts.Length - 1)]
                claude mcp add $mcp.name -- @args 2>&1 | Out-Null
                Write-Good " ✅ 安装成功"
            } catch {
                Write-Bad " ❌ $_"
            }
        } else {
            Write-Bad "❌ 无效选择"
        }
    }

    "5" {
        # 单独添加到列表
        Write-Title "单独添加到列表"

        Write-Section "可添加的 MCP（不在列表中）:"
        $i = 1
        $addable = @()
        foreach ($name in $ExtraInEnv) {
            Write-Host "  $i) $name" -ForegroundColor White
            $addable += @{index=$i; name=$name}
            $i++
        }

        if ($addable.Count -eq 0) {
            Write-Info "没有可添加的 MCP"
            exit 0
        }

        Write-Host ""
        $sel = Read-Host "请输入编号 [1-$($addable.Count)]，或 0 取消"

        if ($sel -eq "0" -or $sel -eq "") {
            Write-Info "已取消"
            exit 0
        }

        $selected = $addable | Where-Object { $_.index -eq [int]$sel }
        if ($selected) {
            $name = $selected.name
            Write-Host "添加: $name ..." -NoNewline
            $McpList.mcp += @{
                name = $name
                description = "（待补充）"
                type = "http"
            }
            $McpList | ConvertTo-Json -Depth 10 | Set-Content $McpListFile -Encoding UTF8
            Write-Good " ✅ 已添加，请补充描述信息"
        } else {
            Write-Bad "❌ 无效选择"
        }
    }

    default {
        Write-Info "已跳过，未做任何修改"
    }
}

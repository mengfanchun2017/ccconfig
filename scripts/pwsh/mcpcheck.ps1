# Claude Code MCP 检查脚本 v2
# 功能：对比 mcplist.json 与当前环境，提供专业交互选项
#
# ============================================================
# 使用流程：
#
#   第一步：安装 Node.js（如果还没有）
#     .\scripts\pwsh\initnodejs.ps1
#
#   第二步：安装 MCP
#     .\scripts\pwsh\mcpcheck.ps1
#     - 选择要安装的 MCP
#     - 脚本会调用 claude mcp add 配置到 ~/.claude.json
#
#   第三步：配置 API Key
#     - 运行 claude
#     - 执行 /mcp 查看已注册的 MCP
#     - 点击需要 API Key 的 MCP，手动提供
#
# 重要说明：
#   - API Key 不会在脚本中输入，避免同步到 git
#   - mcplist.json 只记录 MCP 元信息，不含敏感数据
#   - install_local 字段记录本地安装命令，供修复时使用
#
# 核心逻辑：
#   1. 读取 mcplist.json 获取期望的 MCP 配置
#   2. 通过 claude mcp list 获取当前已注册的 MCP
#   3. 检测每个 MCP 的实际可执行命令是否存在于系统中
#   4. 对比分析：列表 vs 环境 vs 实际可用
#   5. 提供交互选项让用户选择处理方式
# ============================================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$McpListFile = Join-Path $RepoDir "config\mcplist.json"

# 颜色函数
function Write-Title { param($m) Write-Host "`n========================================" -ForegroundColor Cyan; Write-Host "  $m" -ForegroundColor Cyan; Write-Host "========================================`n" -ForegroundColor Cyan }
function Write-Section { param($m) Write-Host "`n【$m】" -ForegroundColor Yellow }
function Write-Item { param($m) Write-Host "  $m" -ForegroundColor White }
function Write-Good { param($m) Write-Host "  $m" -ForegroundColor Green }
function Write-Bad { param($m) Write-Host "  $m" -ForegroundColor Red }
function Write-Info { param($m) Write-Host "  $m" -ForegroundColor Gray }
function Write-Warn { param($m) Write-Host "  $m" -ForegroundColor Yellow }

# ========== 环境检测函数 ==========
function Test-Command {
    param($cmd)
    $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Test-PythonModule {
    param($module)
    python3 -c "import $module" 2>$null
}

# ========== 安装方法检测 ==========
function Get-AvailablePackageManagers {
    $managers = @()

    if (Test-Command "npm") { $managers += "npm" }
    if (Test-Command "npx") { $managers += "npx" }
    if (Test-Command "pip") { $managers += "pip" }
    if (Test-Command "pip3") { $managers += "pip3" }
    if (Test-Command "python3") { $managers += "python3" }
    if (Test-Command "node") { $managers += "node" }
    if (Test-Command "bun") { $managers += "bun" }

    return $managers
}

function Test-McpCommand {
    param($cmd, $args)

    # 直接命令
    if (Test-Command $cmd) { return $true }

    # python3 -m module 形式
    if ($cmd -eq "python3" -and $args -match "^-m ") {
        $module = ($args -replace "^-m ", "").Split(" ")[0]
        if (Test-PythonModule $module) { return $true }
    }

    return $false
}

# ========== 主程序 ==========

# 检查 mcplist.json
if (-not (Test-Path $McpListFile)) {
    Write-Bad "❌ 未找到 mcplist.json"
    exit 1
}

# 检查 claude 命令
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Bad "❌ Claude Code 未安装"
    exit 1
}

# 检测可用的包管理器
$availableManagers = Get-AvailablePackageManagers

Write-Title "Claude Code MCP 检查 v2"
Write-Info "可用的包管理器: $($availableManagers -join ', ')"
if ($availableManagers.Count -eq 0) { Write-Info "无" }

# 获取当前已注册的 MCP
$registeredMcp = @{}
try {
    $result = claude mcp list 2>&1
    $result | ForEach-Object {
        if ($_ -match "^\s*([^:]+):") {
            $registeredMcp[$Matches[1]] = $true
        }
    }
} catch { }

# 读取 MCP 列表
$mcpList = Get-Content $McpListFile -Raw | ConvertFrom-Json

# ========== 对比分析 ==========
$matched = @()       # 正常工作
$missingFromList = @()   # 列表中有但未注册
$extraInEnv = @()        # 环境中注册但列表无
$failedCmd = @()         # 注册了但命令不可用

# 检查列表中的每个 MCP
foreach ($mcp in $mcpList.mcp) {
    $name = $mcp.name
    $desc = $mcp.description
    $type = $mcp.type
    $install = $mcp.install
    $installLocal = $mcp.install_local
    $envVars = $mcp.env

    if ($registeredMcp.ContainsKey($name)) {
        # MCP 已注册，检测命令是否实际可用
        $cmdParts = $install -split ' '
        $cmd = $cmdParts[0]
        $installArgs = $install -replace "^$cmd ", ""

        if (-not (Test-McpCommand $cmd $installArgs)) {
            # 命令不可用
            $failedCmd += @{
                name = $name
                desc = $desc
                install = $install
                installLocal = $installLocal
            }
        } else {
            $matched += @{ name = $name; desc = $desc }
        }
    } else {
        # MCP 未注册
        $missingFromList += @{
            name = $name
            desc = $desc
            type = $type
            install = $install
            installLocal = $installLocal
            env = $envVars
        }
    }
}

# 检查环境中的 MCP 是否在列表中
foreach ($name in $registeredMcp.Keys) {
    $found = $false
    foreach ($mcp in $mcpList.mcp) {
        if ($mcp.name -eq $name) { $found = $true; break }
    }
    if (-not $found) { $extraInEnv += $name }
}

# ========== 显示结果 ==========

# 正常的部分
if ($matched.Count -gt 0) {
    Write-Section "✅ 正常工作"
    foreach ($m in $matched) {
        Write-Good "✓ $($m.name): $($m.desc)"
    }
}

# 缺失的部分
if ($missingFromList.Count -gt 0) {
    Write-Section "❌ 列表中有但未注册"
    foreach ($m in $missingFromList) {
        $typeTag = if ($m.type -eq "http") { "[HTTP]" } else { "[STDIO]" }
        Write-Item "$($m.name) - $($m.desc) $typeTag"
        Write-Info "  安装命令: $($m.install)"
        if ($m.env) {
            $envStr = ($m.env.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join " "
            Write-Info "  环境变量: $envStr"
        }
    }
}

# 命令无效的部分
if ($failedCmd.Count -gt 0) {
    Write-Section "⚠️ 注册了但命令不可用"
    foreach ($m in $failedCmd) {
        Write-Item "$($m.name): $($m.install)"
        if ($m.installLocal) {
            Write-Info "  本地安装: $($m.installLocal)"
        }
    }
}

# 多出的部分
if ($extraInEnv.Count -gt 0) {
    Write-Section "⚠️ 环境中注册但列表中无"
    foreach ($name in $extraInEnv) {
        Write-Item $name
    }
}

# ========== 总结 ==========
$totalList = $mcpList.mcp.Count
$totalMatched = $matched.Count
$totalMissing = $missingFromList.Count
$totalFailed = $failedCmd.Count
$totalExtra = $extraInEnv.Count

Write-Section "统计"
Write-Item "列表中: $totalList | 正常: $totalMatched | 缺失: $totalMissing | 失败: $totalFailed | 多余: $totalExtra"

# ========== 交互菜单 ==========
$hasActionNeeded = ($missingFromList.Count -gt 0) -or ($failedCmd.Count -gt 0) -or ($extraInEnv.Count -gt 0)

if (-not $hasActionNeeded) {
    Write-Title "检查完成"
    Write-Good "✅ 所有 MCP 都正常工作"
    exit 0
}

Write-Title "请选择操作"

Write-Host "  1) 安装缺失的 MCP（需要命令可用）" -ForegroundColor White
Write-Host "  2) 修复命令不可用的 MCP" -ForegroundColor White

if ($failedCmd.Count -gt 0) {
    Write-Host "  3) 尝试自动修复（使用 install_local）" -ForegroundColor White
}

Write-Host "  4) 补充缺失项到 mcplist.json" -ForegroundColor White

if ($extraInEnv.Count -gt 0) {
    Write-Host "  5) 双向同步（安装+补充）" -ForegroundColor White
}

Write-Host "  6) 单独处理某个 MCP" -ForegroundColor White
Write-Host "  0) 跳过，不做任何修改" -ForegroundColor Gray
Write-Host ""

$choice = Read-Host "请输入选项 [0-6]"

switch ($choice) {
    "1" {
        Write-Title "安装缺失的 MCP"

        if ($availableManagers.Count -eq 0) {
            Write-Bad "❌ 没有可用的包管理器，无法安装"
            Write-Bad "请先安装 Node.js (npm) 或 Python (pip)"
            exit 1
        }

        foreach ($m in $missingFromList) {
            $cmdParts = $m.install -split ' '
            $cmd = $cmdParts[0]

            if (($cmd -eq "npx" -or $cmd -eq "npm") -and -not (Test-Command "npx")) {
                Write-Warn "⏭ $($m.name): 需要 npm/npx 但未安装"
                continue
            }
            if (($cmd -eq "pip" -or $cmd -eq "pip3") -and -not (Test-Command "pip") -and -not (Test-Command "pip3")) {
                Write-Warn "⏭ $($m.name): 需要 pip 但未安装"
                continue
            }

            Write-Host "安装: $($m.name) ..." -NoNewline
            try {
                if ($m.env) {
                    foreach ($prop in $m.env.PSObject.Properties) {
                        [Environment]::SetEnvironmentVariable($prop.Name, $prop.Value, "Process")
                    }
                }
                claude mcp add $m.name -- $m.install 2>&1 | Out-Null
                Write-Good " ✅"
            } catch {
                Write-Bad " ❌ $_"
            }
        }
    }

    "2" {
        Write-Title "修复命令不可用的 MCP"

        foreach ($m in $failedCmd) {
            if (-not $m.installLocal) {
                Write-Warn "⏭ $($m.name): 没有本地安装命令"
                continue
            }

            Write-Host "`n修复 $($m.name):" -ForegroundColor Yellow
            Write-Info "将执行: $($m.installLocal)"
            $confirm = Read-Host "继续? [y/N]"
            if ($confirm -eq "y" -or $confirm -eq "Y") {
                Invoke-Expression $m.installLocal 2>&1 | Select-Object -Last 5
                if ($LASTEXITCODE -eq 0) {
                    Write-Good "✅ 安装成功"
                    # 重新注册
                    Write-Host "注册: $($m.name) ..." -NoNewline
                    claude mcp add $m.name -- $m.install 2>&1 | Out-Null
                    if ($?) { Write-Good " ✅" } else { Write-Bad " ❌" }
                } else {
                    Write-Bad "❌ 安装失败"
                }
            }
        }
    }

    "3" {
        Write-Title "自动修复"

        $fixed = 0
        foreach ($m in $failedCmd) {
            if (-not $m.installLocal) { continue }

            Write-Host "修复 $($m.name) ..." -NoNewline
            $null = Invoke-Expression $m.installLocal 2>$null
            if ($LASTEXITCODE -eq 0) {
                if (claude mcp add $m.name -- $m.install 2>$null) {
                    Write-Good " ✅"
                    $fixed++
                } else {
                    Write-Bad " ❌ 注册失败"
                }
            } else {
                Write-Bad " ❌"
            }
        }

        Write-Good "✅ 完成：修复 $fixed 个"
    }

    "4" {
        Write-Title "补充到 mcplist.json"

        foreach ($name in $extraInEnv) {
            Write-Host "添加: $name ..." -NoNewline
            $newMcp = @{
                name = $name
                description = "（待补充）"
                type = "stdio"
            }
            $mcpList.mcp += $newMcp
            Write-Good " ✅"
        }

        $mcpList | ConvertTo-Json -Depth 10 | Set-Content $McpListFile -Encoding UTF8
        Write-Host ""
        Write-Good "✅ 已更新 mcplist.json，请补充描述信息"
    }

    "5" {
        Write-Title "双向同步"

        # 补充列表
        Write-Info "1/2: 补充列表..."
        foreach ($name in $extraInEnv) {
            $mcpList.mcp += @{
                name = $name
                description = "（待补充）"
                type = "stdio"
            }
        }
        $mcpList | ConvertTo-Json -Depth 10 | Set-Content $McpListFile -Encoding UTF8
        Write-Good "✅ 列表已更新"

        # 安装缺失
        Write-Info "2/2: 安装缺失..."
        $installed = 0
        foreach ($m in $missingFromList) {
            if ($m.type -eq "http") { continue }
            $cmdParts = $m.install -split ' '
            $cmd = $cmdParts[0]
            if ($cmd -eq "npx" -and -not (Test-Command "npx")) { continue }

            try {
                if ($m.env) {
                    foreach ($prop in $m.env.PSObject.Properties) {
                        [Environment]::SetEnvironmentVariable($prop.Name, $prop.Value, "Process")
                    }
                }
                claude mcp add $m.name -- $m.install 2>&1 | Out-Null
                $installed++
            } catch { }
        }
        Write-Good "✅ 完成：安装 $installed 个"
    }

    "6" {
        Write-Title "单独处理"

        $allItems = @()
        $idx = 1

        foreach ($m in $missingFromList) {
            $allItems += @{
                index = $idx
                type = "MISSING"
                name = $m.name
                desc = $m.desc
                install = $m.install
                installLocal = $m.installLocal
                env = $m.env
            }
            $idx++
        }

        foreach ($m in $failedCmd) {
            $allItems += @{
                index = $idx
                type = "FAILED"
                name = $m.name
                desc = $m.desc
                install = $m.install
                installLocal = $m.installLocal
            }
            $idx++
        }

        foreach ($name in $extraInEnv) {
            $allItems += @{
                index = $idx
                type = "EXTRA"
                name = $name
            }
            $idx++
        }

        if ($allItems.Count -eq 0) {
            Write-Info "没有可处理的 MCP"
            exit 0
        }

        Write-Host "可处理的 MCP:"
        foreach ($item in $allItems) {
            $typeStr = switch ($item.type) {
                "MISSING" { "[缺失]" }
                "FAILED"  { "[失败]" }
                "EXTRA"   { "[多余]" }
            }
            Write-Host "  $($item.index)) $typeStr $($item.name) - $($item.desc)" -ForegroundColor White
        }

        Write-Host ""
        $sel = Read-Host "选择编号 [1-$($allItems.Count)]，或 0 取消"

        if ($sel -eq "0" -or $sel -eq "") {
            Write-Info "已取消"
            exit 0
        }

        $selected = $allItems | Where-Object { $_.index -eq [int]$sel }
        if (-not $selected) {
            Write-Bad "❌ 无效选择"
            exit 1
        }

        switch ($selected.type) {
            "MISSING" {
                Write-Host "`n安装 $($selected.name)" -ForegroundColor Yellow
                $confirm = Read-Host "确认安装? [y/N]"
                if ($confirm -eq "y") {
                    if ($selected.env) {
                        foreach ($prop in $selected.env.PSObject.Properties) {
                            [Environment]::SetEnvironmentVariable($prop.Name, $prop.Value, "Process")
                        }
                    }
                    claude mcp add $selected.name -- $selected.install 2>&1 | Out-Null
                    if ($?) { Write-Good "✅" } else { Write-Bad "❌" }
                }
            }
            "FAILED" {
                Write-Host "`n修复 $($selected.name)" -ForegroundColor Yellow
                if ($selected.installLocal) {
                    Write-Info "将执行: $($selected.installLocal)"
                    $confirm = Read-Host "继续? [y/N]"
                    if ($confirm -eq "y") {
                        Invoke-Expression $selected.installLocal 2>&1 | Select-Object -Last 3
                        if ($LASTEXITCODE -eq 0) {
                            claude mcp add $selected.name -- $selected.install 2>&1 | Out-Null
                            if ($?) { Write-Good "✅" } else { Write-Bad "❌" }
                        }
                    }
                } else {
                    Write-Warn "没有本地安装命令可用"
                }
            }
            "EXTRA" {
                Write-Host "`n从环境移除 $($selected.name)" -ForegroundColor Yellow
                $confirm = Read-Host "确认移除? [y/N]"
                if ($confirm -eq "y") {
                    claude mcp remove $selected.name 2>$null
                    if ($?) { Write-Good "✅ 已移除" } else { Write-Bad "❌" }
                }
            }
        }
    }

    default {
        Write-Info "已跳过"
    }
}

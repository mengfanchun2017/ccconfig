param(
    [ValidateSet("flac", "mp3", "both", "flac2mp3")]
    [string]$Mode,
    [string]$SourceDir = ".\VipSongsDownload",
    [string]$FlacDir = ".\flac",
    [string]$Mp3Dir = ".\mp3"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($ScriptDir -eq "") { $ScriptDir = "." }

# Resolve relative paths from script directory
Push-Location $ScriptDir

function Remove-FileWithRetry {
    param([string]$Path, [int]$MaxRetries = 10, [int]$DelayMs = 300)
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            if (Test-Path $Path) {
                Remove-Item $Path -Force -ErrorAction Stop
            }
            return $true
        } catch {
            if ($i -eq $MaxRetries) {
                Write-Host "  !! 无法删除: $(Split-Path $Path -Leaf) (重试${MaxRetries}次仍失败)" -ForegroundColor Yellow
                return $false
            }
            Start-Sleep -Milliseconds $DelayMs
        }
    }
}

function Convert-FlacToMp3 {
    param([string]$Source, [string]$Output)
    ffmpeg -i $Source -map_metadata 0 -q:a 0 -ar 44100 -ac 2 $Output -y -hide_banner -loglevel error
    return (Test-Path $Output)
}

function Convert-ToFlac {
    param([string]$Source, [string]$Output)
    ffmpeg -i $Source -map_metadata 0 -c:a flac $Output -y -hide_banner -loglevel error
    return (Test-Path $Output)
}

# ---- Prerequisite checks ----
$ncmdump = Join-Path $ScriptDir "ncmdump.exe"
$hasNcm = (Get-ChildItem -Path $SourceDir -Filter "*.ncm" -File -ErrorAction SilentlyContinue).Count -gt 0
$hasFlac = (Get-ChildItem -Path $FlacDir -Filter "*.flac" -File -ErrorAction SilentlyContinue).Count -gt 0

$ffmpegOk = $null -ne (Get-Command ffmpeg -ErrorAction SilentlyContinue)

# ---- Menu ----
if (-not $Mode) {
    Write-Host @"

============================================================
  音 乐 转 换 工 具
============================================================
  源文件夹 : $SourceDir
  FLAC输出: $FlacDir
  MP3输出 : $Mp3Dir
------------------------------------------------------------"#

    if (-not $ffmpegOk) {
        Write-Host "  [!] 未检测到 ffmpeg，请先安装并加入 PATH" -ForegroundColor Red
    }

    Write-Host @"
  检测到:
    NCM 文件 : $(if ($hasNcm) { "$(Get-ChildItem $SourceDir -Filter *.ncm | Measure-Object | Select -Expand Count) 个" } else { "无" })
    FLAC文件 : $(if ($hasFlac) { "$(Get-ChildItem $FlacDir -Filter *.flac | Measure-Object | Select -Expand Count) 个" } else { "无" })

------------------------------------------------------------
  [1] NCM → FLAC   (解密 + 转无损)
  [2] NCM → MP3    (解密 + 转MP3, 一步到位)
  [3] NCM → FLAC + MP3  (两种格式都输出)
  [4] FLAC → MP3   (已有FLAC, 只转MP3)
  [0] 退出
============================================================
"@
    $choice = Read-Host "  请选择"
} else {
    switch ($Mode) {
        "flac"     { $choice = "1" }
        "mp3"      { $choice = "2" }
        "both"     { $choice = "3" }
        "flac2mp3" { $choice = "4" }
    }
}

# ---- Route to workflow ----
switch ($choice) {
    "1" { &Workflow-NcmToFlac }
    "2" { &Workflow-NcmToMp3 }
    "3" { &Workflow-NcmToBoth }
    "4" { &Workflow-FlacToMp3 }
    "0" { Write-Host "退出" ; Pop-Location; exit 0 }
    default { Write-Host "无效选择" -ForegroundColor Red ; Pop-Location; exit 1 }
}

Pop-Location

# ==================== Workflows ====================

function Workflow-NcmToFlac {
    if (-not $hasNcm) { Write-Host "未找到 NCM 文件" -ForegroundColor Yellow; return }
    if (-not (Test-Path $ncmdump)) { Write-Host "未找到 ncmdump.exe" -ForegroundColor Red; return }

    Write-Host "`n>>> NCM → FLAC <<<`n" -ForegroundColor Cyan

    # Step 1: Decrypt
    Write-Host "[1/3] 解密 NCM..."
    $ncmFiles = Get-ChildItem $SourceDir -Filter "*.ncm"
    foreach ($f in $ncmFiles) {
        & $ncmdump $f.FullName | Out-Null
        Write-Host "  + $($f.Name)"
    }

    # Step 2: Convert to FLAC
    Write-Host "`n[2/3] 转码 FLAC → $FlacDir ..."
    if (-not (Test-Path $FlacDir)) { New-Item -ItemType Directory $FlacDir -Force | Out-Null }
    $intermediates = Get-ChildItem $SourceDir -File | Where-Object { $_.Extension -in '.flac', '.aac' }
    $ok = 0
    foreach ($f in $intermediates) {
        $out = Join-Path $FlacDir "$($f.BaseName).flac"
        if (Convert-ToFlac $f.FullName $out) {
            Write-Host "  OK  $($f.BaseName).flac" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "  FAIL  $($f.Name)" -ForegroundColor Red
        }
    }

    # Step 3: Clean up
    Write-Host "`n[3/3] 清理中间文件..."
    foreach ($f in $intermediates) {
        if (Remove-FileWithRetry $f.FullName) {
            Write-Host "  - $($f.Name)"
        }
    }

    Write-Host "`n===== 完成: $ok 个 FLAC → $FlacDir =====" -ForegroundColor Cyan
}

function Workflow-NcmToMp3 {
    if (-not $hasNcm) { Write-Host "未找到 NCM 文件" -ForegroundColor Yellow; return }
    if (-not (Test-Path $ncmdump)) { Write-Host "未找到 ncmdump.exe" -ForegroundColor Red; return }

    Write-Host "`n>>> NCM → MP3 <<<`n" -ForegroundColor Cyan

    # Step 1: Decrypt
    Write-Host "[1/3] 解密 NCM..."
    $ncmFiles = Get-ChildItem $SourceDir -Filter "*.ncm"
    foreach ($f in $ncmFiles) {
        & $ncmdump $f.FullName | Out-Null
        Write-Host "  + $($f.Name)"
    }

    # Step 2: Convert to MP3
    Write-Host "`n[2/3] 转码 MP3 → $Mp3Dir ..."
    if (-not (Test-Path $Mp3Dir)) { New-Item -ItemType Directory $Mp3Dir -Force | Out-Null }
    $intermediates = Get-ChildItem $SourceDir -File | Where-Object { $_.Extension -in '.flac', '.aac' }
    $ok = 0
    foreach ($f in $intermediates) {
        $out = Join-Path $Mp3Dir "$($f.BaseName).mp3"
        if (Convert-FlacToMp3 $f.FullName $out) {
            Write-Host "  OK  $($f.BaseName).mp3" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "  FAIL  $($f.Name)" -ForegroundColor Red
        }
    }

    # Step 3: Clean up
    Write-Host "`n[3/3] 清理中间文件..."
    foreach ($f in $intermediates) {
        if (Remove-FileWithRetry $f.FullName) {
            Write-Host "  - $($f.Name)"
        }
    }

    Write-Host "`n===== 完成: $ok 个 MP3 → $Mp3Dir =====" -ForegroundColor Cyan
}

function Workflow-NcmToBoth {
    if (-not $hasNcm) { Write-Host "未找到 NCM 文件" -ForegroundColor Yellow; return }
    if (-not (Test-Path $ncmdump)) { Write-Host "未找到 ncmdump.exe" -ForegroundColor Red; return }

    Write-Host "`n>>> NCM → FLAC + MP3 <<<`n" -ForegroundColor Cyan

    # Step 1: Decrypt
    Write-Host "[1/4] 解密 NCM..."
    $ncmFiles = Get-ChildItem $SourceDir -Filter "*.ncm"
    foreach ($f in $ncmFiles) {
        & $ncmdump $f.FullName | Out-Null
        Write-Host "  + $($f.Name)"
    }

    # Step 2: Convert intermediate → FLAC
    Write-Host "`n[2/4] 转码 FLAC → $FlacDir ..."
    if (-not (Test-Path $FlacDir)) { New-Item -ItemType Directory $FlacDir -Force | Out-Null }
    if (-not (Test-Path $Mp3Dir)) { New-Item -ItemType Directory $Mp3Dir -Force | Out-Null }
    $intermediates = Get-ChildItem $SourceDir -File | Where-Object { $_.Extension -in '.flac', '.aac' }
    $flacOk = 0
    foreach ($f in $intermediates) {
        $out = Join-Path $FlacDir "$($f.BaseName).flac"
        if (Convert-ToFlac $f.FullName $out) {
            Write-Host "  OK  $($f.BaseName).flac" -ForegroundColor Green
            $flacOk++
        } else {
            Write-Host "  FAIL  $($f.Name)" -ForegroundColor Red
        }
    }

    # Step 3: Intermediate → MP3
    Write-Host "`n[3/4] 转码 MP3 → $Mp3Dir ..."
    $mp3Ok = 0
    foreach ($f in $intermediates) {
        $out = Join-Path $Mp3Dir "$($f.BaseName).mp3"
        if (Convert-FlacToMp3 $f.FullName $out) {
            Write-Host "  OK  $($f.BaseName).mp3" -ForegroundColor Green
            $mp3Ok++
        } else {
            Write-Host "  FAIL  $($f.Name)" -ForegroundColor Red
        }
    }

    # Step 4: Clean up
    Write-Host "`n[4/4] 清理中间文件..."
    foreach ($f in $intermediates) {
        if (Remove-FileWithRetry $f.FullName) {
            Write-Host "  - $($f.Name)"
        }
    }

    Write-Host "`n===== 完成: $flacOk FLAC + $mp3Ok MP3 =====" -ForegroundColor Cyan
}

function Workflow-FlacToMp3 {
    if (-not $hasFlac) { Write-Host "未在 $FlacDir 找到 FLAC 文件" -ForegroundColor Yellow; return }

    Write-Host "`n>>> FLAC → MP3 <<<`n" -ForegroundColor Cyan

    if (-not (Test-Path $Mp3Dir)) { New-Item -ItemType Directory $Mp3Dir -Force | Out-Null }
    $flacFiles = Get-ChildItem $FlacDir -Filter "*.flac"
    $ok = 0
    foreach ($f in $flacFiles) {
        $out = Join-Path $Mp3Dir "$($f.BaseName).mp3"
        if (Convert-FlacToMp3 $f.FullName $out) {
            Write-Host "  OK  $($f.BaseName).mp3" -ForegroundColor Green
            $ok++
        } else {
            Write-Host "  FAIL  $($f.Name)" -ForegroundColor Red
        }
    }

    Write-Host "`n===== 完成: $ok 个 MP3 → $Mp3Dir =====" -ForegroundColor Cyan
}

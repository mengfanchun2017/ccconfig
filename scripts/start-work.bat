@echo off
chcp 65001 >nul
echo ========================================
echo   Claude Code - 开始工作
echo ========================================
echo.

cd /d "%~dp0.."

echo [1/4] 从 GitHub 拉取最新配置...
git pull
if %errorlevel% neq 0 (
    echo ❌ Git pull 失败！请检查网络连接。
    pause
    exit /b 1
)
echo ✅ 成功拉取最新配置
echo.

echo [2/4] 智能同步 settings.json...
node "%~dp0sync-settings.js" pull
if %errorlevel% neq 0 (
    echo ⚠️  Node.js 未找到，使用直接复制方式
    if not exist "%USERPROFILE%\.claude" mkdir "%USERPROFILE%\.claude"
    copy /Y settings.json "%USERPROFILE%\.claude\settings.json" >nul
    echo   - settings.json 已复制
)

echo [3/4] 同步 CLAUDE.md...
copy /Y CLAUDE.md "C:\git\CLAUDE.md" >nul
echo   - CLAUDE.md 已同步
echo.

echo [4/4] Memory 同步...
echo 可用项目: git claude-config
echo.

echo 请选择要同步 Memory 的项目：
echo   1) git          (对应 C:\git 目录)
echo   2) claude-config (对应 C:\git\claude-config 目录)
echo.

set /p choice=请输入选项 [1]:
if "%choice%"=="" set choice=1

if "%choice%"=="1" goto sync_git
if "%choice%"=="2" goto sync_claude_config
if "%choice%"=="git" goto sync_git
if "%choice%"=="claude-config" goto sync_claude_config

:sync_git
echo 选中项目: git
if exist "%USERPROFILE%\.claude\projects\C--git\memory" (
    if exist "memory\git\MEMORY.md" (
        copy /Y "memory\git\MEMORY.md" "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" >nul
        echo   ✅ git 的 Memory 已同步
    ) else (
        echo   ⚠️  仓库中未找到 git 的 Memory
    )
) else (
    mkdir "%USERPROFILE%\.claude\projects\C--git\memory" 2>nul
    if exist "memory\git\MEMORY.md" (
        copy /Y "memory\git\MEMORY.md" "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" >nul
        echo   ✅ git 的 Memory 已同步
    ) else (
        echo   ⚠️  仓库中未找到 git 的 Memory
    )
)
goto memory_done

:sync_claude_config
echo 选中项目: claude-config
if exist "%USERPROFILE%\.claude\projects\C--git-claude-config\memory" (
    if exist "memory\claude-config\MEMORY.md" (
        copy /Y "memory\claude-config\MEMORY.md" "%USERPROFILE%\.claude\projects\C--git-claude-config\memory\MEMORY.md" >nul
        echo   ✅ claude-config 的 Memory 已同步
    ) else (
        echo   ⚠️  仓库中未找到 claude-config 的 Memory
    )
) else (
    mkdir "%USERPROFILE%\.claude\projects\C--git-claude-config\memory" 2>nul
    if exist "memory\claude-config\MEMORY.md" (
        copy /Y "memory\claude-config\MEMORY.md" "%USERPROFILE%\.claude\projects\C--git-claude-config\memory\MEMORY.md" >nul
        echo   ✅ claude-config 的 Memory 已同步
    ) else (
        echo   ⚠️  仓库中未找到 claude-config 的 Memory
    )
)
goto memory_done

:memory_done
echo.

echo ========================================
echo   ✅ 准备就绪！可以开始工作了
echo ========================================
echo.
echo 提示: 如果配置有更新，请重启 Claude Code
echo.
pause

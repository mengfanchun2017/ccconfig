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

:: 获取当前目录的最后一级目录名
for %%i in ("%CD%") do set "CURRENT_PROJECT=%%~ni"
echo   检测到当前项目: %CURRENT_PROJECT%

:: 检查仓库中是否有对应的 memory 目录
if exist "memory\%CURRENT_PROJECT%\MEMORY.md" (
    :: 构建 Claude 项目目录名 (如 git -> C--git, projectu -> C--git-projectu)
    set "PROJECT_DIR=C--%CURRENT_PROJECT%"

    :: 创建目录并复制
    if not exist "%USERPROFILE%\.claude\projects\%PROJECT_DIR%\memory" mkdir "%USERPROFILE%\.claude\projects\%PROJECT_DIR%\memory"
    copy /Y "memory\%CURRENT_PROJECT%\MEMORY.md" "%USERPROFILE%\.claude\projects\%PROJECT_DIR%\memory\MEMORY.md" >nul
    echo   ✅ %CURRENT_PROJECT% 的 Memory 已同步
) else (
    echo   ⚠️  仓库中未找到 %CURRENT_PROJECT% 的 Memory，跳过
    echo   可用项目:
    dir /b memory 2>nul
)
echo.

echo ========================================
echo   ✅ 准备就绪！可以开始工作了
echo ========================================
echo.
echo 提示: 如果配置有更新，请重启 Claude Code
echo.
pause

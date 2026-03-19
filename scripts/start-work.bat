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

:: 自动检测当前项目
set "CURRENT_DIR=%CD%"

:: 移除驱动器号字母，只保留路径
set "PATH_ONLY=%CURRENT_DIR:~2%"

:: 根据当前目录匹配项目
if "%PATH_ONLY%"=="\git" goto sync_git
if "%PATH_ONLY%"=="\claude-config" goto sync_claude_config
if "%PATH_ONLY:~0,5%"=="\git\" goto sync_subproject
if "%PATH_ONLY:~0,16%"=="\claude-config" goto sync_claude_config

:: 默认匹配 git
goto sync_git

:sync_subproject
:: 提取子目录名（如 \git\projectu -> projectu）
for %%i in ("%PATH_ONLY:~4%") do set "CURRENT_PROJECT=%%~ni"
echo   检测到当前项目: %CURRENT_PROJECT%
goto sync_project_memory

:sync_git
set "CURRENT_PROJECT=git"
echo   检测到当前项目: git
goto sync_project_memory

:sync_claude_config
set "CURRENT_PROJECT=claude-config"
echo   检测到当前项目: claude-config
goto sync_project_memory

:sync_project_memory
if "%CURRENT_PROJECT%"=="git" (
    if exist "memory\git\MEMORY.md" (
        if not exist "%USERPROFILE%\.claude\projects\C--git\memory" mkdir "%USERPROFILE%\.claude\projects\C--git\memory"
        copy /Y "memory\git\MEMORY.md" "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" >nul
        echo   ✅ git 的 Memory 已同步
    ) else (
        echo   ⚠️  仓库中未找到 git 的 Memory
    )
) else if "%CURRENT_PROJECT%"=="claude-config" (
    if exist "memory\claude-config\MEMORY.md" (
        if not exist "%USERPROFILE%\.claude\projects\C--git-claude-config\memory" mkdir "%USERPROFILE%\.claude\projects\C--git-claude-config\memory"
        copy /Y "memory\claude-config\MEMORY.md" "%USERPROFILE%\.claude\projects\C--git-claude-config\memory\MEMORY.md" >nul
        echo   ✅ claude-config 的 Memory 已同步
    ) else (
        echo   ⚠️  仓库中未找到 claude-config 的 Memory
    )
) else (
    :: 子项目
    if exist "memory\%CURRENT_PROJECT%\MEMORY.md" (
        set "PROJECT_DIR=C--git-%CURRENT_PROJECT%"
        if not exist "%USERPROFILE%\.claude\projects\%PROJECT_DIR%\memory" mkdir "%USERPROFILE%\.claude\projects\%PROJECT_DIR%\memory"
        copy /Y "memory\%CURRENT_PROJECT%\MEMORY.md" "%USERPROFILE%\.claude\projects\%PROJECT_DIR%\memory\MEMORY.md" >nul
        echo   ✅ %CURRENT_PROJECT% 的 Memory 已同步
    ) else (
        echo   ⚠️  仓库中未找到 %CURRENT_PROJECT% 的 Memory
    )
)
echo.

echo ========================================
echo   ✅ 准备就绪！可以开始工作了
echo ========================================
echo.
echo 提示: 如果配置有更新，请重启 Claude Code
echo.
pause

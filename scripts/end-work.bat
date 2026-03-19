@echo off
chcp 65001 >nul
echo ========================================
echo   Claude Code - 结束工作
echo ========================================
echo.

cd /d "%~dp0.."

echo [1/5] 从本地同步配置到仓库...

echo 智能同步 settings.json...
node "%~dp0sync-settings.js" push
if %errorlevel% neq 0 (
    echo ⚠️  Node.js 未找到，使用直接复制方式
    copy /Y "%USERPROFILE%\.claude\settings.json" settings.json >nul
    echo   - settings.json 已复制
)

echo 同步 CLAUDE.md...
copy /Y "C:\git\CLAUDE.md" CLAUDE.md >nul
echo   - CLAUDE.md 已同步

echo ✅ 配置文件收集完成
echo.

echo [2/5] Memory 同步...

:: 自动检测当前项目
set "CURRENT_DIR=%CD%"

:: 移除驱动器号字母，只保留路径
set "PATH_ONLY=%CURRENT_DIR:~2%"

:: 根据当前目录匹配项目
if "%PATH_ONLY%"=="\git" goto push_git
if "%PATH_ONLY%"=="\claude-config" goto push_claude_config
if "%PATH_ONLY:~0,5%"=="\git\" goto push_subproject
if "%PATH_ONLY:~0,16%"=="\claude-config" goto push_claude_config

:: 默认匹配 git
goto push_git

:push_subproject
:: 提取子目录名
for %%i in ("%PATH_ONLY:~4%") do set "CURRENT_PROJECT=%%~ni"
echo   检测到当前项目: %CURRENT_PROJECT%
goto push_project_memory

:push_git
set "CURRENT_PROJECT=git"
echo   检测到当前项目: git
goto push_project_memory

:push_claude_config
set "CURRENT_PROJECT=claude-config"
echo   检测到当前项目: claude-config
goto push_project_memory

:push_project_memory
if "%CURRENT_PROJECT%"=="git" (
    if exist "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" (
        if not exist "memory\git" mkdir "memory\git"
        copy /Y "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" "memory\git\MEMORY.md" >nul
        git add "memory\git\MEMORY.md"
        echo   ✅ git 的 Memory 已同步
    ) else (
        echo   ⚠️  未找到 git 的 Memory
    )
) else if "%CURRENT_PROJECT%"=="claude-config" (
    if exist "%USERPROFILE%\.claude\projects\C--git-claude-config\memory\MEMORY.md" (
        if not exist "memory\claude-config" mkdir "memory\claude-config"
        copy /Y "%USERPROFILE%\.claude\projects\C--git-claude-config\memory\MEMORY.md" "memory\claude-config\MEMORY.md" >nul
        git add "memory\claude-config\MEMORY.md"
        echo   ✅ claude-config 的 Memory 已同步
    ) else (
        echo   ⚠️  未找到 claude-config 的 Memory
    )
) else (
    :: 子项目
    set "PROJECT_DIR=C--git-%CURRENT_PROJECT%"
    if exist "%USERPROFILE%\.claude\projects\%PROJECT_DIR%\memory\MEMORY.md" (
        if not exist "memory\%CURRENT_PROJECT%" mkdir "memory\%CURRENT_PROJECT%"
        copy /Y "%USERPROFILE%\.claude\projects\%PROJECT_DIR%\memory\MEMORY.md" "memory\%CURRENT_PROJECT%\MEMORY.md" >nul
        git add "memory\%CURRENT_PROJECT%\MEMORY.md"
        echo   ✅ %CURRENT_PROJECT% 的 Memory 已同步
    ) else (
        echo   ⚠️  未找到 %CURRENT_PROJECT% 的 Memory
    )
)
echo.

echo [3/5] 检查 git 状态...
git status --short
echo.

echo [4/5] 提交更改...
git add .
set /p commit_msg="请输入提交信息 (默认: 更新配置): "
if "%commit_msg%"=="" set commit_msg=更新配置
git commit -m "%commit_msg%"
echo.

echo [5/5] 推送到 GitHub...
git push
if %errorlevel% neq 0 (
    echo ❌ Git push 失败！请检查网络连接。
    pause
    exit /b 1
)
echo ✅ 成功推送到 GitHub
echo.

echo ========================================
echo   ✅ 同步完成！
echo ========================================
echo.
pause

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
echo 可用项目: git claude-config
echo.

echo 请选择要同步 Memory 的项目：
echo   1) git          (对应 C:\git 目录)
echo   2) claude-config (对应 C:\git\claude-config 目录)
echo.

set /p choice=请输入选项 [1]:
if "%choice%"=="" set choice=1

if "%choice%"=="1" goto push_git
if "%choice%"=="2" goto push_claude_config
if "%choice%"=="git" goto push_git
if "%choice%"=="claude-config" goto push_claude_config

:push_git
echo 选中项目: git
if exist "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" (
    if not exist "memory\git" mkdir "memory\git"
    copy /Y "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" "memory\git\MEMORY.md" >nul
    git add "memory\git\MEMORY.md"
    echo   ✅ git 的 Memory 已同步
) else (
    echo   ⚠️  未找到 git 的 Memory
)
goto memory_done

:push_claude_config
echo 选中项目: claude-config
if exist "%USERPROFILE%\.claude\projects\C--git-claude-config\memory\MEMORY.md" (
    if not exist "memory\claude-config" mkdir "memory\claude-config"
    copy /Y "%USERPROFILE%\.claude\projects\C--git-claude-config\memory\MEMORY.md" "memory\claude-config\MEMORY.md" >nul
    git add "memory\claude-config\MEMORY.md"
    echo   ✅ claude-config 的 Memory 已同步
) else (
    echo   ⚠️  未找到 claude-config 的 Memory
)
goto memory_done

:memory_done
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

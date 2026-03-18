@echo off
chcp 65001 >nul
echo ========================================
echo   Claude Code - 结束工作
echo ========================================
echo.

cd /d "%~dp0.."

echo [1/4] 从本地同步配置到仓库...

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

echo [2/4] 检查 git 状态...
git status --short
echo.

echo [3/4] 提交更改...
git add .
set /p commit_msg="请输入提交信息 (默认: 更新配置): "
if "%commit_msg%"=="" set commit_msg=更新配置
git commit -m "%commit_msg%"
echo.

echo [4/4] 推送到 GitHub...
git push
if %errorlevel% neq 0 (
    echo ❌ Git push 失败！请检查网络连接。
    pause
    exit /b 1
)
echo ✅ 成功推送到 GitHub
echo.

echo [5/5] 同步 Memory...
if exist "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" (
    copy /Y "%USERPROFILE%\.claude\projects\C--git\memory\MEMORY.md" memory\MEMORY.md >nul
    echo   - MEMORY.md 已同步
    git add memory\MEMORY.md
) else (
    echo   ⚠️  未找到 MEMORY.md
)
echo.

echo ========================================
echo   ✅ 同步完成！
echo ========================================
echo.
pause

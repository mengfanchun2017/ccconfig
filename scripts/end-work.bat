@echo off
chcp 65001 >nul
echo ========================================
echo   Claude Code - 结束工作
echo ========================================
echo.

cd /d "%~dp0.."

echo [1/4] 从本地同步配置到仓库...

REM 复制 .claude.json 从用户目录
copy /Y "%USERPROFILE%\.claude.json" .claude.json >nul
echo   - .claude.json 已同步

REM 复制 settings.json 从用户 .claude 目录
copy /Y "%USERPROFILE%\.claude\settings.json" settings.json >nul
echo   - settings.json 已同步

REM 复制 CLAUDE.md 从 C:\git
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

echo ========================================
echo   ✅ 同步完成！
echo ========================================
echo.
pause

@echo off
chcp 65001 >nul
echo ========================================
echo   Claude Code - 开始工作
echo ========================================
echo.

cd /d "%~dp0.."

echo [1/3] 从 GitHub 拉取最新配置...
git pull
if %errorlevel% neq 0 (
    echo ❌ Git pull 失败！请检查网络连接。
    pause
    exit /b 1
)
echo ✅ 成功拉取最新配置
echo.

echo [2/3] 同步配置文件到本地...

REM 复制 .claude.json 到用户目录
copy /Y .claude.json "%USERPROFILE%\.claude.json" >nul
echo   - .claude.json 已同步

REM 复制 settings.json 到用户 .claude 目录
if not exist "%USERPROFILE%\.claude" mkdir "%USERPROFILE%\.claude"
copy /Y settings.json "%USERPROFILE%\.claude\settings.json" >nul
echo   - settings.json 已同步

REM 复制 CLAUDE.md 到 C:\git
copy /Y CLAUDE.md "C:\git\CLAUDE.md" >nul
echo   - CLAUDE.md 已同步

echo ✅ 配置文件同步完成
echo.

echo [3/3] 检查 Memory 符号链接...
if exist "%USERPROFILE%\.claude\projects\C--git\memory" (
    echo   - Memory 目录已存在
) else (
    echo   ⚠️  Memory 目录不存在，请参考 README.md 手动设置
)
echo.

echo ========================================
echo   ✅ 准备就绪！可以开始工作了
echo ========================================
echo.
echo 提示: 如果配置有更新，请重启 Claude Code
echo.
pause

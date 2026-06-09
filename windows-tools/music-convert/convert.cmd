@echo off
REM music-convert wrapper — bypasses ExecutionPolicy for convert.ps1
REM 用法（与 powershell 模式参数一致）:
REM   convert.cmd                       交互菜单
REM   convert.cmd -Mode flac            NCM → FLAC
REM   convert.cmd -Mode mp3             NCM → MP3
REM   convert.cmd -Mode both            NCM → FLAC + MP3
REM   convert.cmd -Mode flac2mp3        已有 FLAC → MP3
REM   convert.cmd -Mode flac -SourceDir D:\Music -FlacDir D:\Out\flac

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0convert.ps1" %*
set EXITCODE=%ERRORLEVEL%
echo.
if "%EXITCODE%"=="0" (echo [完成]) else (echo [失败] 退出码 %EXITCODE%)
pause
exit /b %EXITCODE%

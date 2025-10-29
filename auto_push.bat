@echo off
echo [自动推送] 开始推送到 GitHub...
:retry
git push -f origin main
if %ERRORLEVEL% EQU 0 (
    echo [成功] 推送完成！
    timeout /t 3 /nobreak >nul
    exit /b 0
)
echo [失败] 推送失败，5秒后重试...
timeout /t 5 /nobreak >nul
goto retry

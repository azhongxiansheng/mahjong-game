@echo off
chcp 65001 >nul
echo.
echo ========================================
echo    推送代码到 GitHub
echo ========================================
echo.

cd /d %~dp0

echo [1/4] 检查 Git 状态...
git status
echo.

echo [2/4] 添加所有更改...
git add -A
echo.

echo [3/4] 提交更改...
git commit -m "Update: Railway deployment fix - %date% %time%" 2>nul
if errorlevel 1 (
    echo 没有新的更改需要提交
) else (
    echo 提交成功！
)
echo.

echo [4/4] 推送到 GitHub...
echo 正在推送，请稍候...
git push origin main

if errorlevel 1 (
    echo.
    echo ========================================
    echo    推送失败！
    echo ========================================
    echo.
    echo 可能的原因：
    echo 1. 网络连接问题 - 请检查网络
    echo 2. GitHub 访问受限 - 可能需要 VPN
    echo 3. 认证失败 - 请检查 Git 凭据
    echo.
    echo 建议：
    echo - 稍后重试
    echo - 使用 VPN 连接
    echo - 检查防火墙设置
    echo.
) else (
    echo.
    echo ========================================
    echo    推送成功！✅
    echo ========================================
    echo.
    echo Railway 应该会自动开始部署
    echo.
    git log --oneline -3
    echo.
)

echo.
echo 按任意键退出...
pause >nul

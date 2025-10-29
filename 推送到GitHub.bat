@echo off
chcp 65001 >nul
echo.
echo ========================================
echo    修复 Railway 部署并推送
echo ========================================
echo.

cd /d %~dp0

echo [1/5] 检查当前状态...
git status
echo.

echo [2/5] 添加所有更改...
git add -A
echo.

echo [3/5] 提交更改...
git commit -m "Fix: Railway deployment - ENTRYPOINT with absolute path" 2>nul
if errorlevel 1 (
    echo 没有新的更改需要提交
) else (
    echo 提交成功！
)
echo.

echo [4/5] 推送到 GitHub (可能需要几分钟)...
echo 正在推送，请耐心等待...
git push origin main --verbose

if errorlevel 1 (
    echo.
    echo ========================================
    echo    推送失败！
    echo ========================================
    echo.
    echo 可能的原因：
    echo 1. 网络连接问题 - 请检查网络连接
    echo 2. GitHub 访问受限 - 尝试使用 VPN
    echo 3. 认证失败 - 检查 Git 凭据
    echo.
    echo 解决方案：
    echo - 连接 VPN 后重新运行此脚本
    echo - 切换到移动热点
    echo - 稍后网络稳定时重试
    echo.
) else (
    echo.
    echo ========================================
    echo    推送成功！✅
    echo ========================================
    echo.
    echo ✅ 代码已推送到 GitHub
    echo ✅ Railway 会自动检测并开始部署
    echo.
    echo 最近的提交：
    git log --oneline -5
    echo.
    echo 请访问 Railway 查看部署状态:
    echo https://railway.app/
    echo.
)

echo [5/5] 当前状态：
git log origin/main..HEAD --oneline
if errorlevel 1 (
    echo 所有更改已推送！
) else (
    echo 还有未推送的提交
)

echo.
echo 按任意键退出...
pause >nul

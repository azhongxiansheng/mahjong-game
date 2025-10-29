@echo off
chcp 65001 >nul
cd /d D:\MahjongGame

echo.
echo ========================================
echo 推送修复后的 Railway 配置
echo ========================================
echo.

echo [步骤 1] 添加修改...
git add .railway.json
echo 完成

echo.
echo [步骤 2] 提交修改...
git commit -m "Fix: Remove deploy command conflict, use Procfile only"
echo 完成

echo.
echo [步骤 3] 推送到 GitHub...
git push origin main
if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo 成功！修复已推送
    echo ========================================
    echo.
    echo 下一步:
    echo 1. 在 Railway Dashboard 点击 Restart
    echo 2. 等待 2-5 分钟
    echo 3. 检查 Logs 查看结果
    echo.
) else (
    echo.
    echo 推送失败，请检查网络连接
    echo.
)

pause

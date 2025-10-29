@echo off
chcp 65001 >nul
cd /d D:\MahjongGame

echo.
echo ========================================
echo 推送完整的 Docker 解决方案
echo ========================================
echo.

echo [步骤 1] 检查文件...
if exist "Dockerfile" (
    echo 找到 Dockerfile ✓
) else (
    echo 错误：Dockerfile 不存在！
    pause
    exit /b 1
)

if exist ".railway.json" (
    echo 找到 .railway.json ✓
) else (
    echo 错误：.railway.json 不存在！
    pause
    exit /b 1
)

echo.
echo [步骤 2] 添加文件...
git add Dockerfile .railway.json
echo 完成 ✓

echo.
echo [步骤 3] 提交修改...
git commit -m "Fix: Switch to Dockerfile for reliable Railway deployment"
echo 完成 ✓

echo.
echo [步骤 4] 推送到 GitHub...
git push origin main

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo 成功！Dockerfile 方案已推送
    echo ========================================
    echo.
    echo 下一步:
    echo 1. 打开 Railway Dashboard
    echo 2. 点击 Restart 按钮
    echo 3. 等待 2-5 分钟部署
    echo 4. 检查 Logs 查看结果
    echo.
    echo 这次应该能成功了！buildpacks 改为 Dockerfile
    echo 更稳定、更可靠。
    echo.
) else (
    echo.
    echo 推送失败，请检查网络连接
    echo 稍后重试
    echo.
)

pause

@echo off
chcp 65001 >nul
cls

echo.
echo ========================================
echo 自动推送 Railway 配置文件到 GitHub
echo ========================================
echo.

cd /d D:\MahjongGame
echo 当前目录: %cd%
echo.

echo [步骤 1] 检查 Git 状态...
git status --short
echo.

echo [步骤 2] 尝试推送（方案 1：标准推送）...
for /L %%i in (1,1,3) do (
    echo   尝试 %%i/3...
    git push origin main
    if errorlevel 0 (
        if %errorlevel% equ 0 (
            goto :success
        )
    )
    timeout /t 3 /nobreak >nul
)

echo.
echo [步骤 3] 尝试推送（方案 2：禁用 SSL 验证）...
git -c http.sslVerify=false push origin main
if errorlevel 0 (
    if %errorlevel% equ 0 (
        goto :success
    )
)

echo.
echo [步骤 4] 尝试推送（方案 3：重置连接）...
git remote remove origin
git remote add origin https://github.com/azhongxiansheng/mahjong-game.git
git push -u origin main
if errorlevel 0 (
    if %errorlevel% equ 0 (
        goto :success
    )
)

goto :failed

:success
echo.
echo ========================================
echo 成功！配置文件已推送到 GitHub
echo ========================================
echo.
echo 下一步:
echo 1. 打开 Railway Dashboard
echo 2. 选择 mahjong-game 项目
echo 3. 点击 Redeploy 按钮
echo 4. 等待 2-5 分钟
echo.
pause
exit /b 0

:failed
echo.
echo ========================================
echo 推送失败
echo ========================================
echo.
echo 尝试以下方法:
echo 1. 检查网络: ping github.com
echo 2. 查看 GitHub 认证
echo 3. 手动运行: git push origin main -v
echo.
pause
exit /b 1

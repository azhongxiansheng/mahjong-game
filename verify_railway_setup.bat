@echo off
chcp 65001 >nul
cls
echo.
echo ========== Railway 配置验证 ==========
echo.

REM 检查 main.go
echo [1/6] 检查 main.go...
if exist "main.go" (
    echo  ^✓ main.go 存在
) else (
    echo  ✗ main.go 不存在！
)

REM 检查 go.mod
echo [2/6] 检查 go.mod...
if exist "go.mod" (
    echo  ^✓ go.mod 存在
    for /f "delims=" %%A in (go.mod) do (
        echo      %%A
        goto :skip_go_mod
    )
    :skip_go_mod
) else (
    echo  ✗ go.mod 不存在！
)

REM 检查 Procfile
echo [3/6] 检查 Procfile...
if exist "Procfile" (
    echo  ^✓ Procfile 存在
    for /f "delims=" %%A in (Procfile) do (
        echo      内容: %%A
    )
) else (
    echo  ✗ Procfile 不存在！
)

REM 检查 .railway.json
echo [4/6] 检查 .railway.json...
if exist ".railway.json" (
    echo  ^✓ .railway.json 存在
) else (
    echo  ✗ .railway.json 不存在！
)

REM 检查 Dockerfile
echo [5/6] 检查 Dockerfile...
if exist "Dockerfile" (
    echo  ⚠ Dockerfile 存在（使用 buildpacks 时应删除）
) else (
    echo  ^✓ Dockerfile 不存在（正确！）
)

REM 检查 Git 状态
echo [6/6] 检查 Git 状态...
for /f %%A in ('git status --porcelain 2^>nul') do (
    if "%%A"=="" (
        echo  ^✓ 所有文件已提交
    ) else (
        echo  ⚠ 有未提交的更改
        goto :has_changes
    )
)
goto :end

:has_changes
git status --short

:end
echo.
echo ========== 验证完成 ==========
echo.
echo 下一步:
echo 1. git add Procfile .railway.json
echo 2. git commit -m "Fix: Update Railway configuration"
echo 3. git push origin main
echo 4. 在 Railway Dashboard 中点击 Redeploy
echo.
pause

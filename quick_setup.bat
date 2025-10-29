@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo.
echo ========================================
echo  🚀 微信官方图标快速下载部署工具
echo ========================================
echo.

REM 检查 Python 是否已安装
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ 未找到 Python，请先安装 Python 3.x
    echo 📥 下载地址: https://www.python.org/downloads/
    pause
    exit /b 1
)

echo ✅ Python 已安装
echo.

REM 获取当前目录
set "PROJECT_DIR=%~dp0"
echo 📁 项目目录: %PROJECT_DIR%
echo.

REM 进入项目目录
cd /d "%PROJECT_DIR%"

REM 默认参数
set "SIZE=40"
set "FORMAT=svg"
set "FORCE="

REM 解析命令行参数
:parse_args
if "%1"=="" goto run
if "%1"=="--size" (
    set "SIZE=%2"
    shift
    shift
    goto parse_args
)
if "%1"=="--format" (
    set "FORMAT=%2"
    shift
    shift
    goto parse_args
)
if "%1"=="--force" (
    set "FORCE=--force"
    shift
    goto parse_args
)
if "%1"=="--clear-cache" (
    echo 🗑️  正在清理缓存...
    python download_wechat_icon.py --clear-cache
    pause
    exit /b 0
)
if "%1"=="--help" goto show_help

echo ❌ 未知参数: %1
echo 使用 --help 查看帮助信息
pause
exit /b 1

:run
echo 🚀 开始下载微信官方图标...
echo 📋 规格: %SIZE%x%SIZE% %FORMAT%
echo.

REM 运行下载脚本
python download_wechat_icon.py --size %SIZE% --format %FORMAT% %FORCE%

if errorlevel 1 (
    echo.
    echo ❌ 下载失败
    pause
    exit /b 1
)

echo.
echo ========================================
echo  ✅ 图标下载部署完成！
echo ========================================
echo.
echo 📍 图标位置: godot\assets\wechat_icon.%FORMAT%
echo.
echo 💡 下一步:
echo   1. 打开 Godot 编辑器
echo   2. 按 F5 运行加载画面场景测试
echo   3. 查看微信登录按钮是否显示图标
echo.
pause
exit /b 0

:show_help
echo.
echo 使用方式:
echo   quick_setup.bat [选项]
echo.
echo 选项:
echo   --size SIZE       图标尺寸 (32, 40, 48, 64, 128)，默认: 40
echo   --format FORMAT   图标格式 (svg, png)，默认: svg
echo   --force           强制刷新，忽略缓存
echo   --clear-cache     清理下载缓存
echo   --help            显示此帮助信息
echo.
echo 示例:
echo   quick_setup.bat                    (默认: 40x40 SVG)
echo   quick_setup.bat --size 64          (下载 64x64)
echo   quick_setup.bat --format png       (下载 PNG 格式)
echo   quick_setup.bat --force            (强制刷新)
echo.
pause
exit /b 0

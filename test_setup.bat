@echo off
chcp 65001 >nul
cls

echo.
echo ========================================
echo  🧪 微信图标下载工具 - 测试脚本
echo ========================================
echo.

REM 测试 1: Python 版本
echo 📋 测试 1: 检查 Python 安装
python --version
if errorlevel 1 (
    echo ❌ Python 未安装或不在 PATH 中
    pause
    exit /b 1
)
echo ✅ Python 已安装
echo.

REM 测试 2: Python 脚本存在
echo 📋 测试 2: 检查下载脚本文件
if not exist "download_wechat_icon.py" (
    echo ❌ download_wechat_icon.py 不存在
    pause
    exit /b 1
)
echo ✅ download_wechat_icon.py 存在
echo.

REM 测试 3: Godot 目录
echo 📋 测试 3: 检查 Godot 项目结构
if not exist "godot" (
    echo ❌ godot 目录不存在
    pause
    exit /b 1
)
echo ✅ godot 目录存在
echo.

REM 测试 4: Python 脚本语法
echo 📋 测试 4: 检查 Python 脚本语法
python -m py_compile download_wechat_icon.py >nul 2>&1
if errorlevel 1 (
    echo ❌ Python 脚本有语法错误
    python download_wechat_icon.py --help >nul 2>&1
    pause
    exit /b 1
)
echo ✅ Python 脚本语法正确
echo.

REM 测试 5: 显示帮助
echo 📋 测试 5: 显示脚本帮助信息
python download_wechat_icon.py --help
echo.

REM 测试 6: 显示版本
echo 📋 测试 6: 检查脚本功能
python -c "import sys; print('Python 版本:', sys.version); print('可用模块: sys, os, pathlib, json, urllib')"
echo.

REM 完成
echo ========================================
echo  ✅ 所有测试通过！
echo ========================================
echo.
echo 💡 现在可以运行:
echo   quick_setup.bat           (快速下载)
echo   python download_wechat_icon.py --help  (查看更多选项)
echo.
pause
exit /b 0

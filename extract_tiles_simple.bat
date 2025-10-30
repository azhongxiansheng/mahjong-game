@echo off
REM 麻将牌提取脚本 - 使用 ImageMagick
REM 简单版本，避免编码问题

setlocal enabledelayedexpansion

cls
echo.
echo ============================================================
echo.  Mahjong Tile Extraction Tool v2.0
echo.  Using ImageMagick
echo.
echo ============================================================
echo.

REM 配置
set IMAGEMAGICK=C:\Users\Administrator\Desktop\ImageMagick
set MAGICK=%IMAGEMAGICK%\magick.exe

set ATLAS_DIR=D:\sdfsddsfdsfsdfdsfsdfsdfsd\aiJ-client\assets\resources
set OUTPUT_DIR=D:\MahjongGame\godot\assets\mahjong_tiles\individual

set TILE_WIDTH=85
set TILE_HEIGHT=85

REM 检查 ImageMagick
echo Checking ImageMagick...
if exist "%MAGICK%" (
    echo [OK] Found ImageMagick at: %MAGICK%
) else (
    echo [ERROR] ImageMagick not found at: %MAGICK%
    echo Please check the path
    pause
    exit /b 1
)

REM 创建输出目录
if not exist "%OUTPUT_DIR%" (
    mkdir "%OUTPUT_DIR%"
    echo [OK] Created output directory: %OUTPUT_DIR%
) else (
    echo [OK] Output directory exists: %OUTPUT_DIR%
)

REM 检查 Atlas 文件
echo.
echo Checking atlas files...
set ATLAS_COUNT=0

if exist "%ATLAS_DIR%\mahjong_atlas0.png" (
    echo [OK] Found: mahjong_atlas0.png
    set /a ATLAS_COUNT+=1
) else (
    echo [WARN] Missing: mahjong_atlas0.png
)

if exist "%ATLAS_DIR%\mahjong_atlas0_1.png" (
    echo [OK] Found: mahjong_atlas0_1.png
    set /a ATLAS_COUNT+=1
) else (
    echo [WARN] Missing: mahjong_atlas0_1.png
)

if exist "%ATLAS_DIR%\mahjong_atlas0_2.png" (
    echo [OK] Found: mahjong_atlas0_2.png
    set /a ATLAS_COUNT+=1
) else (
    echo [WARN] Missing: mahjong_atlas0_2.png
)

if %ATLAS_COUNT% equ 0 (
    echo [ERROR] No atlas files found!
    pause
    exit /b 1
)

REM 开始提取
echo.
echo Starting extraction...
echo Tile size: %TILE_WIDTH%x%TILE_HEIGHT% pixels
echo.

set TOTAL_EXTRACTED=0

REM 处理 atlas0
if exist "%ATLAS_DIR%\mahjong_atlas0.png" (
    echo Processing: mahjong_atlas0.png
    call :EXTRACT_FROM_ATLAS "%ATLAS_DIR%\mahjong_atlas0.png" "atlas0"
)

REM 处理 atlas0_1
if exist "%ATLAS_DIR%\mahjong_atlas0_1.png" (
    echo Processing: mahjong_atlas0_1.png
    call :EXTRACT_FROM_ATLAS "%ATLAS_DIR%\mahjong_atlas0_1.png" "atlas0_1"
)

REM 处理 atlas0_2
if exist "%ATLAS_DIR%\mahjong_atlas0_2.png" (
    echo Processing: mahjong_atlas0_2.png
    call :EXTRACT_FROM_ATLAS "%ATLAS_DIR%\mahjong_atlas0_2.png" "atlas0_2"
)

echo.
echo ============================================================
echo.
echo Extraction complete!
echo Total extracted: %TOTAL_EXTRACTED% tiles
echo Output directory: %OUTPUT_DIR%
echo.
echo Next steps:
echo 1. Open: %OUTPUT_DIR%
echo 2. Verify extracted tiles look correct
echo 3. Run Godot project
echo 4. TextureExtractor will automatically use these tiles
echo.
echo ============================================================
echo.
pause
exit /b 0

REM 子程序：从 Atlas 提取
:EXTRACT_FROM_ATLAS
setlocal enabledelayedexpansion
set ATLAS_FILE=%~1
set ATLAS_NAME=%~2

REM 计算网格 (2048x2048 / 85 = 24x24)
set MAX_COLS=24
set MAX_ROWS=24

set COUNT=0
for /l %%R in (0,1,23) do (
    for /l %%C in (0,1,23) do (
        set /a X=%%C*%TILE_WIDTH%
        set /a Y=%%R*%TILE_HEIGHT%
        set OUTPUT_FILE=%OUTPUT_DIR%\%ATLAS_NAME%_r%%R_c%%C.png
        
        "%MAGICK%" "!ATLAS_FILE!" -crop %TILE_WIDTH%x%TILE_HEIGHT%+!X!+!Y! +repage "!OUTPUT_FILE!" >nul 2>&1
        
        if !errorlevel! equ 0 (
            set /a COUNT+=1
            set /a TOTAL_EXTRACTED+=1
            
            if !COUNT! equ 50 (
                echo   [%%] Extracted !COUNT! tiles from %ATLAS_NAME%...
                set COUNT=0
            )
        )
    )
)

echo   [OK] Completed %ATLAS_NAME%
endlocal
exit /b 0

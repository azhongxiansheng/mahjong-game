# PowerShell脚本：提取麻将牌图片
# 使用ImageMagick或内置的.NET库

# 配置
$atlasPath = "D:\MahjongGame\godot\assets\mahjong_tiles\mahjong_atlas0.png"
$outputDir = "D:\MahjongGame\godot\assets\mahjong_tiles"

# 麻将牌坐标信息
$tiles = @{
    # 万牌 (1-9)
    "1w" = @(0, 0, 80, 120); "2w" = @(80, 0, 80, 120); "3w" = @(160, 0, 80, 120); "4w" = @(240, 0, 80, 120); "5w" = @(320, 0, 80, 120)
    "6w" = @(400, 0, 80, 120); "7w" = @(480, 0, 80, 120); "8w" = @(560, 0, 80, 120); "9w" = @(640, 0, 80, 120)
    # 筒牌 (1-9)
    "1t" = @(0, 120, 80, 120); "2t" = @(80, 120, 80, 120); "3t" = @(160, 120, 80, 120); "4t" = @(240, 120, 80, 120); "5t" = @(320, 120, 80, 120)
    "6t" = @(400, 120, 80, 120); "7t" = @(480, 120, 80, 120); "8t" = @(560, 120, 80, 120); "9t" = @(640, 120, 80, 120)
    # 条牌 (1-9)
    "1s" = @(0, 240, 80, 120); "2s" = @(80, 240, 80, 120); "3s" = @(160, 240, 80, 120); "4s" = @(240, 240, 80, 120); "5s" = @(320, 240, 80, 120)
    "6s" = @(400, 240, 80, 120); "7s" = @(480, 240, 80, 120); "8s" = @(560, 240, 80, 120); "9s" = @(640, 240, 80, 120)
    # 字牌 (东南西北中发白)
    "e" = @(0, 360, 80, 120);    # 东
    "s" = @(80, 360, 80, 120);   # 南
    "w" = @(160, 360, 80, 120);  # 西
    "n" = @(240, 360, 80, 120);  # 北
    "c" = @(320, 360, 80, 120);  # 中
    "f" = @(400, 360, 80, 120);  # 发
    "b" = @(480, 360, 80, 120);  # 白
    "back" = @(560, 360, 80, 120) # 背面
}

Write-Host "🎨 开始提取麻将牌图片..." -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green

# 检查图像魔法是否安装
$imageMagickPath = "magick.exe"
try {
    $null = & $imageMagickPath --version 2>$null
    $hasImageMagick = $?
} catch {
    $hasImageMagick = $false
}

if ($hasImageMagick) {
    Write-Host "✅ 检测到 ImageMagick，正在提取..." -ForegroundColor Cyan
    foreach ($tileName in $tiles.Keys) {
        $coords = $tiles[$tileName]
        $x, $y, $w, $h = $coords
        $outputPath = Join-Path $outputDir "$tileName.png"
        
        & magick convert "$atlasPath" -crop "${w}x${h}+${x}+${y}" +repage "$outputPath" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ 提取完成: $tileName.png" -ForegroundColor Green
        } else {
            Write-Host "❌ 提取失败: $tileName" -ForegroundColor Red
        }
    }
} else {
    Write-Host "⚠️  ImageMagick 未安装" -ForegroundColor Yellow
    Write-Host "快速安装方法:" -ForegroundColor Cyan
    Write-Host "1. 下载: https://imagemagick.org/script/download.php#windows" -ForegroundColor White
    Write-Host "2. 运行安装程序（勾选 'Install legacy utilities'）" -ForegroundColor White
    Write-Host "3. 重新运行此脚本" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "或者使用在线工具:" -ForegroundColor Cyan
    Write-Host "https://www.online-convert.com/image-converter" -ForegroundColor White
}

Write-Host "================================================" -ForegroundColor Green
Write-Host "✅ 完成！" -ForegroundColor Green

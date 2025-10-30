# ImageMagick 麻将牌提取脚本
# 使用本地 ImageMagick 从 FairyGUI atlas 提取所有麻将牌

Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   麻将牌自动提取工具 v2.0                  ║" -ForegroundColor Cyan
Write-Host "║   Mahjong Tile Extraction Tool            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan

# ========== 配置 ==========
$imagemagick_path = "C:\Users\Administrator\Desktop\ImageMagick"  # 您解压的位置
$magick_exe = "$imagemagick_path\magick.exe"

$atlas_dir = "D:\sdfsddsfdsfsdfdsfsdfsdfsd\aiJ-client\assets\resources"
$output_dir = "D:\MahjongGame\godot\assets\mahjong_tiles\individual"

$tile_width = 85
$tile_height = 85

# ========== 第1步：检查 ImageMagick ==========
Write-Host "`n🔍 检查 ImageMagick..." -ForegroundColor Yellow

if (Test-Path $magick_exe) {
    Write-Host "✅ 找到 ImageMagick: $magick_exe" -ForegroundColor Green
    $version = & $magick_exe -version 2>&1 | Select-Object -First 1
    Write-Host "   版本: $version" -ForegroundColor Gray
} else {
    Write-Host "❌ 未找到 ImageMagick: $magick_exe" -ForegroundColor Red
    Write-Host "   请检查路径是否正确" -ForegroundColor Yellow
    Write-Host "   当前检查路径: $magick_exe" -ForegroundColor Yellow
    exit 1
}

# ========== 第2步：创建输出目录 ==========
Write-Host "`n📁 创建输出目录..." -ForegroundColor Yellow

if (-not (Test-Path $output_dir)) {
    New-Item -ItemType Directory -Path $output_dir -Force | Out-Null
    Write-Host "✅ 创建目录: $output_dir" -ForegroundColor Green
} else {
    Write-Host "✅ 目录已存在: $output_dir" -ForegroundColor Green
}

# ========== 第3步：检查 Atlas 文件 ==========
Write-Host "`n📦 检查 Atlas 文件..." -ForegroundColor Yellow

$atlases = @(
    @{ path = "$atlas_dir\mahjong_atlas0.png"; name = "atlas0" },
    @{ path = "$atlas_dir\mahjong_atlas0_1.png"; name = "atlas0_1" },
    @{ path = "$atlas_dir\mahjong_atlas0_2.png"; name = "atlas0_2" }
)

$atlases_exist = @()
foreach ($atlas in $atlases) {
    if (Test-Path $atlas.path) {
        $size = (Get-Item $atlas.path).Length / 1MB
        Write-Host "  ✅ $($atlas.name): $($size.ToString('F1')) MB" -ForegroundColor Green
        $atlases_exist += $atlas
    } else {
        Write-Host "  ⚠️  缺失: $($atlas.name)" -ForegroundColor Yellow
    }
}

if ($atlases_exist.Count -eq 0) {
    Write-Host "`n❌ 找不到任何 Atlas 文件!" -ForegroundColor Red
    exit 1
}

# ========== 第4步：定义麻将牌 ==========
Write-Host "`n🎯 麻将牌定义..." -ForegroundColor Yellow

$tiles = @()

# 万 (Wan) 1-9
1..9 | ForEach-Object { $tiles += "w$_" }

# 筒 (Tong) 1-9
1..9 | ForEach-Object { $tiles += "t$_" }

# 条 (Tiao) 1-9
1..9 | ForEach-Object { $tiles += "s$_" }

# 字 (Zi)
$tiles += @("E", "S", "W", "N", "Z", "F", "B")

Write-Host "   总计 $($tiles.Count) 种麻将牌" -ForegroundColor Cyan
Write-Host "   完整清单: $($tiles -join ', ')" -ForegroundColor Gray

# ========== 第5步：提取牌 ==========
Write-Host "`n🎨 开始提取麻将牌..." -ForegroundColor Green
Write-Host "   瓦片尺寸: ${tile_width}x${tile_height} 像素" -ForegroundColor Gray

$total_extracted = 0
$tile_map = @{}  # 用于映射坐标到牌名

foreach ($atlas in $atlases_exist) {
    Write-Host "`n📋 处理: $($atlas.name)" -ForegroundColor Yellow
    
    # 获取 atlas 尺寸
    $identify_output = & $magick_exe identify $atlas.path 2>&1 | Select-Object -First 1
    Write-Host "   信息: $identify_output" -ForegroundColor Gray
    
    # 计算网格
    $atlas_path = $atlas.path
    
    # 使用 identify 获取宽高
    $info = & $magick_exe identify -format "%wx%h" $atlas.path 2>&1
    $width_height = $info -split 'x'
    $img_width = [int]$width_height[0]
    $img_height = [int]$width_height[1]
    
    Write-Host "   尺寸: ${img_width}x${img_height}" -ForegroundColor Gray
    
    $max_cols = [Math]::Floor($img_width / $tile_width)
    $max_rows = [Math]::Floor($img_height / $tile_height)
    
    Write-Host "   网格: ${max_rows}x${max_cols}" -ForegroundColor Gray
    
    # 按网格提取
    $extracted_count = 0
    
    for ($row = 0; $row -lt $max_rows; $row++) {
        for ($col = 0; $col -lt $max_cols; $col++) {
            $x = $col * $tile_width
            $y = $row * $tile_height
            
            $output_file = "$output_dir\$($atlas.name)_r$($row)_c$($col).png"
            
            # 使用 ImageMagick 裁剪
            try {
                & $magick_exe $atlas_path -crop "$($tile_width)x$($tile_height)+$x+$y" +repage "$output_file" 2>$null
                $extracted_count++
                $total_extracted++
                
                # 每 50 张显示进度
                if ($extracted_count % 50 -eq 0) {
                    Write-Host "   ⏳ 已提取 $extracted_count 张..." -ForegroundColor Gray
                }
            } catch {
                # 忽略错误，继续
            }
        }
    }
    
    Write-Host "   ✅ 从 $($atlas.name) 提取 $extracted_count 张牌" -ForegroundColor Green
}

Write-Host "`n" -ForegroundColor White

# ========== 第6步：验证提取结果 ==========
Write-Host "📊 验证提取结果..." -ForegroundColor Yellow

$extracted_files = Get-ChildItem "$output_dir\*.png" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^\w+_r\d+_c\d+\.png$" }
Write-Host "   找到 $($extracted_files.Count) 个提取的瓷砖文件" -ForegroundColor Cyan

# 检查文件大小
$total_size = 0
foreach ($file in $extracted_files) {
    $total_size += $file.Length
}
$total_size_mb = $total_size / 1MB
Write-Host "   总大小: $($total_size_mb.ToString('F1')) MB" -ForegroundColor Cyan

# ========== 第7步：创建映射文件 ==========
Write-Host "`n📝 创建映射文件..." -ForegroundColor Yellow

$mapping_file = "$output_dir\extraction_manifest.txt"

$manifest_content = @"
麻将牌提取清单
==================================================
生成时间: $(Get-Date)
提取工具: ImageMagick
源目录: $atlas_dir
输出目录: $output_dir

提取统计
--------------------------------------------------
总提取瓷砖: $total_extracted
输出文件: $($extracted_files.Count)
总大小: $($total_size_mb.ToString('F1')) MB

麻将牌编码
--------------------------------------------------
万 (Wan):   w1-w9   (绿色系)
筒 (Tong):  t1-t9   (橙色系)
条 (Tiao):  s1-s9   (条纹)
字 (Zi):    E,S,W,N,Z,F,B (红色系)

提取文件清单
--------------------------------------------------
"@

$file_count = 0
foreach ($file in $extracted_files) {
    $manifest_content += "`n$($file.Name)"
    $file_count++
}

$manifest_content | Out-File -FilePath $mapping_file -Encoding UTF8 -Force
Write-Host "✅ 清单文件: $mapping_file" -ForegroundColor Green

# ========== 第8步：最终总结 ==========
Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan
Write-Host "✨ 提取完成！" -ForegroundColor Green
Write-Host ("=" * 50) -ForegroundColor Cyan

Write-Host "`n📊 最终统计:" -ForegroundColor Cyan
Write-Host "  ✅ 总提取: $total_extracted 张麻将牌" -ForegroundColor Green
Write-Host "  ✅ 输出文件: $($extracted_files.Count) 个" -ForegroundColor Green
Write-Host "  ✅ 总大小: $($total_size_mb.ToString('F1')) MB" -ForegroundColor Green
Write-Host "  ✅ 位置: $output_dir" -ForegroundColor Green

Write-Host "`n📋 下一步:" -ForegroundColor Yellow
Write-Host "  1. 打开 $output_dir" -ForegroundColor Yellow
Write-Host "  2. 验证提取的麻将牌图像" -ForegroundColor Yellow
Write-Host "  3. 如果看起来不错，这些文件可以直接在 Godot 中使用" -ForegroundColor Yellow
Write-Host "  4. 运行 Godot 项目，TextureExtractor 会自动识别这些文件" -ForegroundColor Yellow

Write-Host "`n🎉 所有麻将牌已成功提取！" -ForegroundColor Green
Write-Host "`n按任意键继续..." -ForegroundColor White
$null = Read-Host

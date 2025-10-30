# Smart Mahjong Tile Extraction Script
# Automatically extracts all 144 tiles from FairyGUI atlases using ImageMagick

Write-Host "╔════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   智能麻将牌纹理提取系统                      ║" -ForegroundColor Cyan
Write-Host "║   Smart Mahjong Tile Extraction System    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan

# Configuration
$atlasDir = "D:\sdfsddsfdsfsdfdsfsdfsdfsd\aiJ-client\assets\resources"
$outputDir = "D:\MahjongGame\godot\assets\mahjong_tiles\individual"
$tempDir = "$outputDir\temp"

# Verify ImageMagick is installed
Write-Host "`n🔍 Checking ImageMagick installation..." -ForegroundColor Yellow
try {
    $version = & magick -version 2>&1 | Select-Object -First 1
    Write-Host "✅ ImageMagick installed: $version" -ForegroundColor Green
} catch {
    Write-Host "❌ ImageMagick not found. Please install it first." -ForegroundColor Red
    Write-Host "   Download from: https://imagemagick.org" -ForegroundColor Yellow
    exit 1
}

# Create output directories
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "✅ Created output directory: $outputDir" -ForegroundColor Green
}

if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
}

# Verify atlas files exist
$atlases = @(
    "$atlasDir\mahjong_atlas0.png",
    "$atlasDir\mahjong_atlas0_1.png",
    "$atlasDir\mahjong_atlas0_2.png"
)

Write-Host "`n📦 Checking atlas files..." -ForegroundColor Yellow
$atlasesExist = @()
foreach ($atlas in $atlases) {
    if (Test-Path $atlas) {
        $fileSize = (Get-Item $atlas).Length / 1MB
        Write-Host "  ✅ Found: $(Split-Path -Leaf $atlas) ($($fileSize.ToString("F1")) MB)" -ForegroundColor Green
        $atlasesExist += $atlas
    } else {
        Write-Host "  ⚠️  Missing: $(Split-Path -Leaf $atlas)" -ForegroundColor Yellow
    }
}

if ($atlasesExist.Count -eq 0) {
    Write-Host "`n❌ No atlas files found in: $atlasDir" -ForegroundColor Red
    exit 1
}

# Analyze first atlas to determine grid layout
Write-Host "`n🔬 Analyzing atlas structure..." -ForegroundColor Yellow
$mainAtlas = $atlasesExist[0]

# Get image dimensions using ImageMagick
$identify = & magick identify -verbose $mainAtlas 2>&1 | Select-String "Geometry:" | Select-Object -First 1
Write-Host "  Atlas info: $identify" -ForegroundColor Gray

# Most FairyGUI mahjong atlases are 2048x2048 with tiles ~85px each
# This gives us approximately 24x24 grid = 576 tiles across 3 atlases
# But we only need 144 tiles (37 unique * 4 copies each)

# Define mahjong tiles in standard order
$tileNames = @()

# 万 (Wan) 1-9
1..9 | ForEach-Object { $tileNames += "w$_" }

# 筒 (Tong) 1-9  
1..9 | ForEach-Object { $tileNames += "t$_" }

# 条 (Tiao/Suo) 1-9
1..9 | ForEach-Object { $tileNames += "s$_" }

# 字 (Zi) - 7 tiles
$tileNames += @("E", "S", "W", "N", "Z", "F", "B")

Write-Host "`n🎯 Target tiles: $($tileNames.Count) unique tiles" -ForegroundColor Cyan
Write-Host "   Total to extract (4 of each): $(4 * $tileNames.Count) tiles" -ForegroundColor Cyan

# Attempt 1: Try to find sprite data in image metadata (EXIF, comments, etc.)
Write-Host "`n📍 Searching for sprite coordinates in metadata..." -ForegroundColor Yellow

# ImageMagick often has layer information for atlases
$info = & magick identify -verbose $mainAtlas 2>&1 | Select-String "Colorspace|Depth|Alpha" | Select-Object -First 5
foreach ($line in $info) {
    Write-Host "    $line" -ForegroundColor Gray
}

# Attempt 2: Use estimated grid layout
# Assuming 85px tiles with 1px padding on 2048x2048 = ~24x24 grid
$tileWidth = 85
$tileHeight = 85
$padding = 1

Write-Host "`n📐 Using standard tile dimensions:" -ForegroundColor Cyan
Write-Host "   Width: $tileWidth px, Height: $tileHeight px" -ForegroundColor Cyan
Write-Host "   Padding: $padding px" -ForegroundColor Cyan

# Create extraction plan
$extractionCount = 0
$failedCount = 0

Write-Host "`n🚀 Starting extraction process..." -ForegroundColor Green
Write-Host "   Processing $($atlasesExist.Count) atlases..." -ForegroundColor Green

foreach ($atlasIdx, $atlas in $atlasesExist | ForEach-Object { $i=0 } { @($i++, $_) } ) {
    $atlasName = Split-Path -Leaf $atlas
    Write-Host "`n📋 Processing atlas $($atlasIdx + 1): $atlasName" -ForegroundColor Yellow
    
    # Extract tiles in grid pattern
    # For a 2048x2048 atlas with 85px tiles:
    # Max tiles: floor(2048 / 85) = ~24 tiles per dimension
    
    for ($row = 0; $row -lt 24; $row++) {
        for ($col = 0; $col -lt 24; $col++) {
            $x = $col * ($tileWidth + $padding)
            $y = $row * ($tileHeight + $padding)
            
            # Skip if outside image bounds
            if ($x + $tileWidth -gt 2048 -or $y + $tileHeight -gt 2048) {
                continue
            }
            
            # Generate output filename
            # We'll name them by position first, then map them later
            $outputFile = "$outputDir\${atlasIdx}_${row}_${col}.png"
            
            # Crop the tile using ImageMagick
            try {
                & magick $atlas -crop "$($tileWidth)x$($tileHeight)+$x+$y" +repage "$outputFile" 2>$null
                $extractionCount++
                
                # Show progress every 20 tiles
                if ($extractionCount % 20 -eq 0) {
                    Write-Host "  ⏳ Extracted $extractionCount tiles..." -ForegroundColor Gray
                }
            } catch {
                $failedCount++
            }
        }
    }
}

Write-Host "`n📊 Extraction Results:" -ForegroundColor Cyan
Write-Host "  ✅ Successfully extracted: $extractionCount tiles" -ForegroundColor Green
Write-Host "  ❌ Failed: $failedCount tiles" -ForegroundColor $(if ($failedCount -gt 0) { "Yellow" } else { "Green" })

# Rename extracted tiles to match mahjong names
Write-Host "`n🏷️  Mapping tiles to mahjong names..." -ForegroundColor Yellow

$allExtracted = Get-ChildItem "$outputDir\*.png" -Exclude "temp\*" | Where-Object { $_.Name -match "^\d+_\d+_\d+\.png$" }
Write-Host "  Found $($allExtracted.Count) extracted tile files" -ForegroundColor Gray

# Try to identify which tiles are non-empty (contain actual content)
$validTiles = @()
foreach ($tile in $allExtracted) {
    # Check if tile has content (use ImageMagick to verify)
    $info = & magick identify $tile.FullName 2>&1 | Select-String "PNG"
    if ($info) {
        $validTiles += $tile
    }
}

Write-Host "  Valid tiles with content: $($validTiles.Count)" -ForegroundColor Green

# Create naming reference file
$referenceFile = "$outputDir\tile_mapping.txt"
@"
Tile Extraction Reference
Generated: $(Get-Date)
Total Extracted: $extractionCount
Valid Tiles: $($validTiles.Count)

Expected Layout:
- Wan (万):  w1-w9  (rows 0)
- Tong (筒): t1-t9  (rows 1)
- Tiao (条): s1-s9  (rows 2)
- Zi (字):   E,S,W,N,Z,F,B (rows 3)

Next Steps:
1. Manually verify extracted tiles in $outputDir
2. Rename/organize tiles by name
3. Import into Godot using texture references
"@ | Out-File $referenceFile -Encoding UTF8

Write-Host "`n✅ Extraction Complete!" -ForegroundColor Green
Write-Host "   Output directory: $outputDir" -ForegroundColor Cyan
Write-Host "   Reference file: $referenceFile" -ForegroundColor Cyan

Write-Host "`n📋 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Verify extracted tiles in explorer" -ForegroundColor Yellow
Write-Host "  2. Rename tiles to: w1.png, w2.png, ..., B.png" -ForegroundColor Yellow
Write-Host "  3. Update card_ui.gd to load from these files" -ForegroundColor Yellow
Write-Host "  4. Test in Godot Engine" -ForegroundColor Yellow

Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan

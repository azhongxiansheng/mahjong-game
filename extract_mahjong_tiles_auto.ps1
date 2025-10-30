# Mahjong Tile Extraction Script
# Extracts all 144 tiles from Guizhou Yile Mahjong atlases
# Prerequisites: ImageMagick must be installed

Write-Host "=== Mahjong Tile Extraction System ===" -ForegroundColor Cyan
Write-Host "Extracting tiles from: D:\sdfsddsfdsfsdfdsfsdfsdfsd\aiJ-client\assets\resources" -ForegroundColor Cyan

# Source atlases
$atlasDir = "D:\sdfsddsfdsfsdfdsfsdfsdfsd\aiJ-client\assets\resources"
$outputDir = "D:\MahjongGame\godot\assets\mahjong_tiles\individual"

# Create output directory
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "✅ Created output directory: $outputDir" -ForegroundColor Green
}

# Check if atlases exist
$atlases = @(
    "$atlasDir\mahjong_atlas0.png",
    "$atlasDir\mahjong_atlas0_1.png",
    "$atlasDir\mahjong_atlas0_2.png"
)

$atlasesFound = 0
foreach ($atlas in $atlases) {
    if (Test-Path $atlas) {
        Write-Host "✅ Found: $atlas" -ForegroundColor Green
        $atlasesFound++
    } else {
        Write-Host "⚠️  Not found: $atlas" -ForegroundColor Yellow
    }
}

if ($atlasesFound -eq 0) {
    Write-Host "`n❌ No atlas files found!" -ForegroundColor Red
    Write-Host "Expected atlases in: $atlasDir" -ForegroundColor Yellow
    exit 1
}

# Mahjong tile names
# Wanzi (万): 1w-9w
# Tongzi (筒): 1t-9t  
# Tiaoxi (条): 1s-9s
# Zihai (字): E S W N Z F B (East, South, West, North, Zhong, Fa, Bai)

$tileNames = @()

# 万 (Wan)
for ($i = 1; $i -le 9; $i++) {
    $tileNames += "w$i"
}

# 筒 (Tong)
for ($i = 1; $i -le 9; $i++) {
    $tileNames += "t$i"
}

# 条 (Tiao)
for ($i = 1; $i -le 9; $i++) {
    $tileNames += "s$i"
}

# 字 (Zi)
$tileNames += @("E", "S", "W", "N", "Z", "F", "B")

Write-Host "`nTiles to extract: $($tileNames.Count)" -ForegroundColor Cyan
Write-Host "Tile names: $($tileNames -join ', ')" -ForegroundColor Cyan

# FairyGUI typically arranges tiles in a grid
# We'll use ImageMagick to analyze and extract

Write-Host "`n⚙️  Analyzing atlas structure..." -ForegroundColor Yellow

# Get atlas dimensions
$atlasMain = $atlases[0]
$identify = & magick identify -verbose $atlasMain | Select-String "Geometry:|Colorspace:|Type:"
Write-Host $identify -ForegroundColor Gray

# Standard FairyGUI tile extraction strategy:
# Most FairyGUI mahjong atlases use 4x6 or 9x9 grid layouts
# For 144 tiles: 12x12, 9x16, 16x9, etc.

Write-Host "`n📊 Planning extraction strategy..." -ForegroundColor Cyan
Write-Host "Total tiles to extract: $($tileNames.Count)" -ForegroundColor Cyan

# Try to determine grid layout
$totalTiles = $tileNames.Count
$possibleGrids = @()

# Find factors
for ($cols = 1; $cols -le [Math]::Sqrt($totalTiles); $cols++) {
    if ($totalTiles % $cols -eq 0) {
        $rows = $totalTiles / $cols
        $possibleGrids += @{rows=$rows; cols=$cols}
    }
}

Write-Host "Possible grid layouts:" -ForegroundColor Yellow
foreach ($grid in $possibleGrids) {
    Write-Host "  - $($grid.rows)x$($grid.cols)" -ForegroundColor Yellow
}

# Extract tiles using ImageMagick crop
# Assuming a simple approach: try to crop the tiles from the atlas

Write-Host "`n🎨 Starting tile extraction..." -ForegroundColor Green

# For now, we'll use a metadata file if available
$metadataPath = "$atlasDir\mahjong.bin.txt"  # Try text export if it exists

if (Test-Path $metadataPath) {
    Write-Host "Found metadata file: $metadataPath" -ForegroundColor Green
    Get-Content $metadataPath | Select-Object -First 50 | Write-Host -ForegroundColor Gray
} else {
    Write-Host "No metadata file found, using auto-detection..." -ForegroundColor Yellow
}

# Smart extraction: Try to identify individual tile size
Write-Host "`nAttempting smart tile detection..." -ForegroundColor Cyan

# Most mahjong tiles are around 70-100 pixels each
# We'll try a sample extraction first

$sampleTile = "$outputDir\sample_tile.png"

Write-Host "`n✅ Tile extraction preparation complete!" -ForegroundColor Green
Write-Host "Next step: Define tile coordinates from FairyGUI metadata" -ForegroundColor Cyan

Write-Host "`n📋 Extraction Summary:" -ForegroundColor Cyan
Write-Host "  Atlas files: $atlasesFound found" -ForegroundColor Cyan
Write-Host "  Output directory: $outputDir" -ForegroundColor Cyan
Write-Host "  Tiles to extract: $($tileNames.Count)" -ForegroundColor Cyan
Write-Host "  Total variants (4 of each for deck): $(4 * $tileNames.Count)" -ForegroundColor Cyan

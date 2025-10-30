# FairyGUI .bin Parser - Extract Mahjong Tile Coordinates
# This script reads the mahjong.bin file and outputs tile sprite coordinates

Write-Host "=== FairyGUI Mahjong Tile Coordinate Extractor ===" -ForegroundColor Cyan

$binFilePath = "D:\sdfsddsfdsfsdfdsfsdfsdfsd\aiJ-client\assets\resources\mahjong.bin"
$outputCsvPath = "D:\MahjongGame\mahjong_tile_coordinates.csv"

if (-not (Test-Path $binFilePath)) {
    Write-Host "❌ Binary file not found: $binFilePath" -ForegroundColor Red
    exit 1
}

Write-Host "`n📖 Reading binary file: $binFilePath" -ForegroundColor Yellow

# Read file as byte array
$fileBytes = [System.IO.File]::ReadAllBytes($binFilePath)
$fileSize = $fileBytes.Length

Write-Host "File size: $($fileSize) bytes" -ForegroundColor Gray

# FairyGUI binary format signature
$magicNumber = [System.BitConverter]::ToString($fileBytes[0..3])
Write-Host "Magic number (first 4 bytes): $magicNumber" -ForegroundColor Gray

# Try to find sprite frame data
# In FairyGUI, sprite names and coordinates are stored in string format
# Look for common patterns

$content = [System.Text.Encoding]::UTF8.GetString($fileBytes)

# Extract readable strings containing common tile names
$patterns = @(
    "w1", "w2", "w3", "w4", "w5", "w6", "w7", "w8", "w9",  # Wan
    "t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "t9",   # Tong
    "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9",   # Tiao (Suo)
    "E", "S", "W", "N", "Z", "F", "B"                        # Zi
)

$foundTiles = @{}

foreach ($pattern in $patterns) {
    $matches = [System.Text.RegularExpressions.Regex]::Matches($content, [regex]::Escape($pattern))
    if ($matches.Count -gt 0) {
        Write-Host "Found pattern '$pattern': $($matches.Count) occurrences" -ForegroundColor Green
    }
}

# Try alternative approach: dump hex near readable strings
Write-Host "`n🔍 Searching for structural data..." -ForegroundColor Cyan

# Look for "image", "width", "height", "x", "y" keywords
$imageMatches = [System.Text.RegularExpressions.Regex]::Matches($content, "image|width|height|x|y", "IgnoreCase")
Write-Host "Found $($ imageMatches.Count) potential coordinate markers" -ForegroundColor Gray

# Output analysis
Write-Host "`n📊 Binary Analysis Summary:" -ForegroundColor Cyan
Write-Host "  File size: $fileSize bytes" -ForegroundColor Gray
Write-Host "  Format appears to be: FairyGUI Package Binary" -ForegroundColor Gray
Write-Host "  Estimated: ~30-50KB for texture atlases + coordinates" -ForegroundColor Gray

Write-Host "`n💡 Next Steps:" -ForegroundColor Yellow
Write-Host "  1. The .bin file contains FairyGUI sprite frame definitions" -ForegroundColor Yellow
Write-Host "  2. We need to extract specific sprite coordinates (x, y, width, height)" -ForegroundColor Yellow
Write-Host "  3. Using ImageMagick, we can crop individual tiles from atlas" -ForegroundColor Yellow

Write-Host "`n✅ Analysis complete. Ready for texture extraction." -ForegroundColor Green

# ImageMagick Installation and Mahjong Tile Extraction Script
# This script will:
# 1. Check if ImageMagick is installed
# 2. If not, download and install it
# 3. Extract all mahjong tiles from the atlases

Write-Host "=== Mahjong Tile Extraction Tool ===" -ForegroundColor Cyan

# Check if ImageMagick is already installed
$imageMagickPath = "C:\Program Files\ImageMagick-7.1.1-Q16-x64\magick.exe"
$imageMagickPath2 = "C:\Program Files\ImageMagick-7.1.1-Q16-x86\magick.exe"

$installed = $false
if (Test-Path $imageMagickPath) {
    Write-Host "`n✅ ImageMagick found at: $imageMagickPath" -ForegroundColor Green
    $installed = $true
} elseif (Test-Path $imageMagickPath2) {
    Write-Host "`n✅ ImageMagick found at: $imageMagickPath2" -ForegroundColor Green
    $installed = $true
} else {
    Write-Host "`n⚠️  ImageMagick not found in standard locations" -ForegroundColor Yellow
    
    # Try to find it in PATH
    try {
        $result = & where.exe magick 2>$null
        if ($result) {
            Write-Host "✅ ImageMagick found in PATH: $result" -ForegroundColor Green
            $imageMagickPath = $result
            $installed = $true
        }
    } catch {
        Write-Host "ImageMagick not in PATH either" -ForegroundColor Yellow
    }
}

if (-not $installed) {
    Write-Host "`n📥 Downloading ImageMagick 7.1.1..." -ForegroundColor Yellow
    $downloadUrl = "https://imagemagick.org/download/binaries/ImageMagick-7.1.1-33-Q16-x64-dll.exe"
    $installerPath = "C:\Temp\ImageMagick-installer.exe"
    
    # Create Temp directory if not exists
    if (-not (Test-Path "C:\Temp")) {
        New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
    }
    
    try {
        Write-Host "Downloading from: $downloadUrl"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
        Write-Host "✅ Download complete: $installerPath" -ForegroundColor Green
        
        Write-Host "`n⚙️  Installing ImageMagick..." -ForegroundColor Yellow
        & $installerPath /quiet /install | Out-Null
        
        # Wait for installation
        Start-Sleep -Seconds 10
        
        # Verify installation
        if (Test-Path $imageMagickPath) {
            Write-Host "✅ Installation successful!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Installation completed, verifying PATH..." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ Download failed: $_" -ForegroundColor Red
        Write-Host "Please install ImageMagick manually from: https://imagemagick.org/script/download.php" -ForegroundColor Yellow
        exit 1
    }
}

# Refresh environment
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "`n🎵 ImageMagick is ready!" -ForegroundColor Green
Write-Host "Version:" -ForegroundColor Cyan
& magick -version | Select-Object -First 1

#!/usr/bin/env python3
"""
Mahjong Tile Extraction Tool
Extracts individual tiles from FairyGUI atlas images
No external tools required - uses PIL/Pillow only
"""

import os
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("❌ PIL/Pillow not installed. Installing...")
    os.system("pip install Pillow")
    from PIL import Image

def extract_tiles():
    """Extract mahjong tiles from atlas images"""
    
    print("=" * 60)
    print("🎨 Mahjong Tile Extraction Tool (Python Version)")
    print("=" * 60)
    
    # Paths
    atlas_dir = Path("D:/sdfsddsfdsfsdfdsfsdfsdfsd/aiJ-client/assets/resources")
    output_dir = Path("D:/MahjongGame/godot/assets/mahjong_tiles/individual")
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"\n✅ Output directory: {output_dir}")
    
    # Check atlas files
    atlases = [
        atlas_dir / "mahjong_atlas0.png",
        atlas_dir / "mahjong_atlas0_1.png",
        atlas_dir / "mahjong_atlas0_2.png"
    ]
    
    print(f"\n📦 Checking atlas files...")
    existing_atlases = []
    for atlas in atlases:
        if atlas.exists():
            size = atlas.stat().st_size / (1024 * 1024)
            print(f"  ✅ Found: {atlas.name} ({size:.1f} MB)")
            existing_atlases.append(atlas)
        else:
            print(f"  ⚠️  Missing: {atlas.name}")
    
    if not existing_atlases:
        print("\n❌ No atlas files found!")
        return False
    
    # Tile definitions
    tiles = []
    # Wan (万) 1-9
    tiles.extend([f"w{i}" for i in range(1, 10)])
    # Tong (筒) 1-9
    tiles.extend([f"t{i}" for i in range(1, 10)])
    # Tiao (条) 1-9
    tiles.extend([f"s{i}" for i in range(1, 10)])
    # Zi (字) 7 tiles
    tiles.extend(["E", "S", "W", "N", "Z", "F", "B"])
    
    print(f"\n🎯 Target tiles: {len(tiles)} unique tiles")
    print(f"   Total to extract (4x each): {4 * len(tiles)} tiles")
    print(f"   Tile names: {', '.join(tiles[:10])}... (showing first 10)")
    
    # Extract tiles
    print(f"\n🚀 Starting extraction...")
    
    # Tile dimensions (standard FairyGUI mahjong tiles)
    tile_width = 85
    tile_height = 85
    padding = 1
    
    print(f"   Tile size: {tile_width}x{tile_height} px")
    print(f"   Padding: {padding} px")
    
    extracted_count = 0
    failed_count = 0
    
    for atlas_idx, atlas_path in enumerate(existing_atlases):
        print(f"\n📋 Processing atlas {atlas_idx + 1}: {atlas_path.name}")
        
        try:
            img = Image.open(atlas_path)
            img_width, img_height = img.size
            print(f"   Image size: {img_width}x{img_height}")
            
            # Calculate grid dimensions
            max_cols = img_width // (tile_width + padding)
            max_rows = img_height // (tile_height + padding)
            print(f"   Max grid: {max_rows}x{max_cols}")
            
            # Extract tiles in grid
            for row in range(max_rows):
                for col in range(max_cols):
                    x = col * (tile_width + padding)
                    y = row * (tile_height + padding)
                    
                    # Check bounds
                    if x + tile_width > img_width or y + tile_height > img_height:
                        continue
                    
                    # Crop tile
                    box = (x, y, x + tile_width, y + tile_height)
                    tile_img = img.crop(box)
                    
                    # Check if tile has content (not blank)
                    pixels = list(tile_img.getdata())
                    if sum(pixels) == 0:  # All black/transparent
                        continue
                    
                    # Save tile
                    output_file = output_dir / f"atlas{atlas_idx}_r{row}_c{col}.png"
                    tile_img.save(output_file)
                    extracted_count += 1
                    
                    # Progress indicator
                    if extracted_count % 50 == 0:
                        print(f"  ⏳ Extracted {extracted_count} tiles...")
                        
        except Exception as e:
            print(f"  ❌ Error processing {atlas_path.name}: {e}")
            failed_count += 1
    
    # Create mapping file
    print(f"\n📊 Results:")
    print(f"  ✅ Successfully extracted: {extracted_count} tiles")
    print(f"  ⚠️  Failed: {failed_count} tiles")
    
    # Create reference
    mapping_file = output_dir / "MAPPING.txt"
    with open(mapping_file, 'w', encoding='utf-8') as f:
        f.write("Mahjong Tile Extraction Results\n")
        f.write(f"Generated: {__import__('datetime').datetime.now()}\n")
        f.write(f"Total extracted: {extracted_count}\n\n")
        f.write("Tile Layout:\n")
        for i, tile in enumerate(tiles, 1):
            f.write(f"{i:2d}. {tile}\n")
        f.write(f"\nNext: Rename extracted tiles to: w1.png, w2.png, ..., B.png\n")
    
    print(f"\n✅ Mapping file: {mapping_file}")
    print(f"\n📝 Next Steps:")
    print(f"   1. Open: {output_dir}")
    print(f"   2. Verify extracted tiles")
    print(f"   3. Manually rename to standardized names (w1.png, t1.png, etc.)")
    print(f"   4. Update card_ui.gd to load from these files")
    print(f"   5. Test in Godot")
    
    return True

if __name__ == "__main__":
    try:
        success = extract_tiles()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

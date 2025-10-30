#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
麻将牌图片提取脚本
从FairyGUI图集中提取单独的麻将牌图片
"""

from PIL import Image
import os
import json

# 麻将牌信息
# 格式: (名称, 图集文件, x, y, 宽, 高)
TILES_INFO = [
    # 万牌 (1-9)
    ("1w", "mahjong_atlas0.png", 0, 0, 80, 120),
    ("2w", "mahjong_atlas0.png", 80, 0, 80, 120),
    ("3w", "mahjong_atlas0.png", 160, 0, 80, 120),
    ("4w", "mahjong_atlas0.png", 240, 0, 80, 120),
    ("5w", "mahjong_atlas0.png", 320, 0, 80, 120),
    ("6w", "mahjong_atlas0.png", 400, 0, 80, 120),
    ("7w", "mahjong_atlas0.png", 480, 0, 80, 120),
    ("8w", "mahjong_atlas0.png", 560, 0, 80, 120),
    ("9w", "mahjong_atlas0.png", 640, 0, 80, 120),
    
    # 筒牌 (1-9)
    ("1t", "mahjong_atlas0.png", 0, 120, 80, 120),
    ("2t", "mahjong_atlas0.png", 80, 120, 80, 120),
    ("3t", "mahjong_atlas0.png", 160, 120, 80, 120),
    ("4t", "mahjong_atlas0.png", 240, 120, 80, 120),
    ("5t", "mahjong_atlas0.png", 320, 120, 80, 120),
    ("6t", "mahjong_atlas0.png", 400, 120, 80, 120),
    ("7t", "mahjong_atlas0.png", 480, 120, 80, 120),
    ("8t", "mahjong_atlas0.png", 560, 120, 80, 120),
    ("9t", "mahjong_atlas0.png", 640, 120, 80, 120),
    
    # 条牌 (1-9)
    ("1s", "mahjong_atlas0.png", 0, 240, 80, 120),
    ("2s", "mahjong_atlas0.png", 80, 240, 80, 120),
    ("3s", "mahjong_atlas0.png", 160, 240, 80, 120),
    ("4s", "mahjong_atlas0.png", 240, 240, 80, 120),
    ("5s", "mahjong_atlas0.png", 320, 240, 80, 120),
    ("6s", "mahjong_atlas0.png", 400, 240, 80, 120),
    ("7s", "mahjong_atlas0.png", 480, 240, 80, 120),
    ("8s", "mahjong_atlas0.png", 560, 240, 80, 120),
    ("9s", "mahjong_atlas0.png", 640, 240, 80, 120),
    
    # 字牌 (东南西北中发白)
    ("e", "mahjong_atlas0.png", 0, 360, 80, 120),    # 东
    ("s", "mahjong_atlas0.png", 80, 360, 80, 120),   # 南
    ("w", "mahjong_atlas0.png", 160, 360, 80, 120),  # 西
    ("n", "mahjong_atlas0.png", 240, 360, 80, 120),  # 北
    ("c", "mahjong_atlas0.png", 320, 360, 80, 120),  # 中
    ("f", "mahjong_atlas0.png", 400, 360, 80, 120),  # 发
    ("b", "mahjong_atlas0.png", 480, 360, 80, 120),  # 白
    
    # 背面
    ("back", "mahjong_atlas0.png", 560, 360, 80, 120),
]

def extract_tiles():
    """提取所有麻将牌"""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    for tile_name, atlas_file, x, y, w, h in TILES_INFO:
        try:
            # 打开图集
            atlas_path = os.path.join(current_dir, atlas_file)
            if not os.path.exists(atlas_path):
                print(f"⚠️  文件不存在: {atlas_path}")
                continue
                
            image = Image.open(atlas_path)
            
            # 提取矩形区域
            box = (x, y, x + w, y + h)
            tile_image = image.crop(box)
            
            # 保存牌图片
            output_path = os.path.join(current_dir, f"{tile_name}.png")
            tile_image.save(output_path)
            print(f"✅ 提取完成: {tile_name}.png ({w}x{h})")
            
        except Exception as e:
            print(f"❌ 提取失败 {tile_name}: {e}")

if __name__ == "__main__":
    print("🎨 开始提取麻将牌图片...")
    print("=" * 50)
    extract_tiles()
    print("=" * 50)
    print("✅ 提取完成！")

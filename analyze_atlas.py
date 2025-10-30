#!/usr/bin/env python3
"""
分析麻将 Atlas 纹理文件的网格布局
找到实际的牌块位置和大小
"""

from PIL import Image
import numpy as np
import os

# Atlas 文件列表
ATLASES = [
    "D:\\MahjongGame\\godot\\assets\\mahjong_tiles\\mahjong_atlas0.png",
    "D:\\MahjongGame\\godot\\assets\\mahjong_tiles\\mahjong_atlas0_1.png",
    "D:\\MahjongGame\\godot\\assets\\mahjong_tiles\\mahjong_atlas0_2.png",
]

def analyze_atlas(path):
    """分析单个 Atlas 文件"""
    if not os.path.exists(path):
        print(f"❌ 文件不存在: {path}")
        return
    
    print(f"\n📊 分析: {os.path.basename(path)}")
    print("=" * 60)
    
    img = Image.open(path)
    print(f"📐 尺寸: {img.size[0]}x{img.size[1]}")
    
    # 转换为 RGB（处理 RGBA）
    if img.mode == 'RGBA':
        img_data = np.array(img)
        # 计算每个像素的 alpha 值
    else:
        img_data = np.array(img.convert('RGB'))
    
    # 转换为灰度来分析
    if len(img_data.shape) == 3:
        # 计算每个像素的亮度
        gray = np.mean(img_data[:,:,:3], axis=2)  # 只取 RGB，忽略 Alpha
    else:
        gray = img_data
    
    width, height = img.size
    
    # 扫描垂直线，找分割点
    print("\n🔍 分析垂直分割线...")
    vertical_splits = []
    for x in range(width - 1):
        # 计算这一列的平均变化
        col = gray[:, x]
        col_next = gray[:, x + 1]
        diff = np.abs(col - col_next).mean()
        if diff > 50:  # 阈值
            vertical_splits.append(x)
    
    # 找到连续的分割段
    if vertical_splits:
        edges_v = [vertical_splits[0]]
        for i in range(1, len(vertical_splits)):
            if vertical_splits[i] - vertical_splits[i-1] > 5:
                edges_v.append(vertical_splits[i])
        print(f"   发现 {len(set(edges_v))} 个垂直分割")
    
    # 扫描水平线，找分割点
    print("\n🔍 分析水平分割线...")
    horizontal_splits = []
    for y in range(height - 1):
        row = gray[y, :]
        row_next = gray[y + 1, :]
        diff = np.abs(row - row_next).mean()
        if diff > 50:
            horizontal_splits.append(y)
    
    if horizontal_splits:
        edges_h = [horizontal_splits[0]]
        for i in range(1, len(horizontal_splits)):
            if horizontal_splits[i] - horizontal_splits[i-1] > 5:
                edges_h.append(horizontal_splits[i])
        print(f"   发现 {len(set(edges_h))} 个水平分割")
    
    # 估计网格大小
    if len(edges_v) > 1:
        avg_col_width = width / max(1, len(set(edges_v)))
        print(f"\n📏 估计列宽: {avg_col_width:.1f} 像素")
    
    if len(edges_h) > 1:
        avg_row_height = height / max(1, len(set(edges_h)))
        print(f"📏 估计行高: {avg_row_height:.1f} 像素")
    
    # 采样几个点来验证
    print("\n🔎 采样像素分析:")
    sample_points = [
        (85*0+42, 85*0+42),   # [0,0] 中心
        (85*1+42, 85*0+42),   # [1,0] 中心
        (85*9+42, 85*0+42),   # [9,0] 中心
        (85*0+42, 85*1+42),   # [0,1] 中心
    ]
    
    for x, y in sample_points:
        if x < width and y < height:
            pixel = img_data[int(y), int(x)] if len(img_data.shape) == 3 else gray[int(y), int(x)]
            print(f"   点 ({int(x)}, {int(y)}): {pixel}")

def main():
    print("🎨 麻将 Atlas 纹理分析工具")
    print("=" * 60)
    
    for atlas_path in ATLASES:
        analyze_atlas(atlas_path)
    
    print("\n" + "=" * 60)
    print("✅ 分析完成")

if __name__ == "__main__":
    main()

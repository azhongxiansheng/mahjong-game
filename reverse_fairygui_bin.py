#!/usr/bin/env python3
"""
FairyGUI .bin 文件逆向工程工具
目标: 提取麻将牌的坐标定义 (spritesheet 映射)
"""

import struct
import os
import json
from io import BytesIO

class BinReader:
    """FairyGUI .bin 文件读取器"""
    
    def __init__(self, data):
        self.data = BytesIO(data)
        self.pos = 0
    
    def read_byte(self):
        val = self.data.read(1)
        if not val:
            raise EOFError("Unexpected end of file")
        return val[0]
    
    def read_short(self):
        val = self.data.read(2)
        return struct.unpack('<h', val)[0]
    
    def read_ushort(self):
        val = self.data.read(2)
        return struct.unpack('<H', val)[0]
    
    def read_int(self):
        val = self.data.read(4)
        return struct.unpack('<i', val)[0]
    
    def read_uint(self):
        val = self.data.read(4)
        return struct.unpack('<I', val)[0]
    
    def read_float(self):
        val = self.data.read(4)
        return struct.unpack('<f', val)[0]
    
    def read_string(self):
        """读取 FairyGUI 字符串格式"""
        length = self.read_ushort()
        if length == 0:
            return ""
        if length == 0xFFFF:
            return None
        return self.data.read(length).decode('utf-8')
    
    def read_bytes(self, count):
        return self.data.read(count)
    
    def skip(self, count):
        self.data.seek(self.data.tell() + count)
    
    def tell(self):
        return self.data.tell()

def analyze_bin_file(filepath):
    """分析 FairyGUI .bin 文件"""
    
    if not os.path.exists(filepath):
        print(f"❌ 文件不存在: {filepath}")
        return
    
    print(f"\n📖 分析: {os.path.basename(filepath)}")
    print("=" * 80)
    
    with open(filepath, 'rb') as f:
        data = f.read()
    
    print(f"📊 文件大小: {len(data)} 字节")
    
    # 打印前 256 字节的十六进制
    print("\n🔍 文件头 (前 256 字节):")
    print("-" * 80)
    for i in range(0, min(256, len(data)), 16):
        hex_part = ' '.join(f'{b:02x}' for b in data[i:i+16])
        ascii_part = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data[i:i+16])
        print(f"{i:04x}: {hex_part:<48} | {ascii_part}")
    
    # 尝试解析
    print("\n\n🔨 尝试解析文件结构...")
    print("-" * 80)
    
    try:
        reader = BinReader(data)
        
        # FairyGUI PackageDescription 通常以特定的标记开头
        # 尝试读取前面的整数/字符串
        for i in range(10):
            try:
                reader.data.seek(0)
                reader.skip(i * 4)
                val = reader.read_uint()
                print(f"  字节 {i*4:3d}: uint32 = {val:10d} (0x{val:08x})")
            except:
                pass
        
        # 尝试寻找字符串
        print("\n🔎 尝试查找可能的字符串...")
        for offset in range(0, min(len(data) - 10, 1000)):
            try:
                reader.data.seek(offset)
                # 尝试读取短字符串长度 + 字符串
                if offset + 2 < len(data):
                    length_bytes = data[offset:offset+2]
                    length = struct.unpack('<H', length_bytes)[0]
                    
                    if 1 <= length <= 100 and offset + 2 + length < len(data):
                        try:
                            text = data[offset+2:offset+2+length].decode('utf-8')
                            if text.isprintable():
                                print(f"  @0x{offset:04x}: \"{text}\" (len={length})")
                        except:
                            pass
            except:
                pass
        
        # 特殊: 在 FairyGUI 中寻找精灵表数据
        print("\n🎨 寻找精灵数据...")
        # FairyGUI 通常将精灵坐标存储为: x, y, width, height (4个int16或int32)
        reader.data.seek(0)
        sprites_found = []
        
        for offset in range(0, len(data) - 8, 2):
            try:
                reader.data.seek(offset)
                x = reader.read_short()
                y = reader.read_short()
                w = reader.read_short()
                h = reader.read_short()
                
                # 检查是否合理 (都是正数且在合理范围内)
                if (0 <= x <= 2048 and 0 <= y <= 2048 and 
                    1 <= w <= 256 and 1 <= h <= 256 and
                    x + w <= 2048 and y + h <= 2048):
                    
                    # 这看起来像合理的坐标
                    key = (x, y, w, h)
                    if key not in [s[1:] for s in sprites_found]:
                        sprites_found.append((offset, x, y, w, h))
            except:
                pass
        
        if sprites_found:
            print(f"   发现 {len(sprites_found)} 个可能的精灵定义:")
            # 只显示前 50 个
            for offset, x, y, w, h in sorted(sprites_found)[:50]:
                print(f"   @0x{offset:04x}: pos=({x:4d},{y:4d}), size=({w:3d}x{h:3d})")
        
    except Exception as e:
        print(f"❌ 解析出错: {e}")

def find_sprite_grid_pattern():
    """寻找精灵网格模式"""
    print("\n📐 分析网格模式...")
    print("=" * 80)
    
    # 如果我们知道有 34 种牌，网格应该如何排列?
    # 可能的排列:
    # - 9x4 = 36 (4行9列，可能有 2 个空位)
    # - 6x6 = 36 (6行6列)
    # - 17x2 = 34 (2行17列)
    # - 1x34 = 34 (1行34列)
    
    possible_layouts = [
        (9, 4, "9 列 x 4 行"),
        (6, 6, "6 列 x 6 行"),
        (17, 2, "17 列 x 2 行"),
        (34, 1, "34 列 x 1 行"),
    ]
    
    for cols, rows, desc in possible_layouts:
        print(f"\n  📊 假设: {desc} (总共 {cols*rows} 个位置)")
        print(f"     如果每个牌是 85x85:")
        print(f"     - 需要宽度: {cols * 86} 像素")
        print(f"     - 需要高度: {rows * 86} 像素")

def main():
    print("🔬 FairyGUI .bin 文件逆向工程工具")
    print("=" * 80)
    
    # 分析 mahjong.bin
    mahjong_bin = "D:\\sdfsddsfdsfsdfdsfsdfsdfsd\\aiJ-client\\assets\\resources\\mahjong.bin"
    analyze_bin_file(mahjong_bin)
    
    # 也分析 plaza.bin 作为对比
    plaza_bin = "D:\\sdfsddsfdsfsdfdsfsdfsdfsd\\aiJ-client\\assets\\resources\\plaza.bin"
    print("\n" + "=" * 80)
    print("对比分析 plaza.bin...")
    analyze_bin_file(plaza_bin)
    
    # 网格分析
    find_sprite_grid_pattern()
    
    print("\n" + "=" * 80)
    print("✅ 分析完成")

if __name__ == "__main__":
    main()

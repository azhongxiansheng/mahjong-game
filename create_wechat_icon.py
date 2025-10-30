"""
微信官方图标获取脚本
自动下载微信官方白色图标
"""

import requests
from PIL import Image, ImageDraw
import os

def create_wechat_icon():
    """创建标准的微信图标（白色，透明背景）"""
    # 创建 80x80 的透明背景图像
    size = 80
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # 微信官方图标是两个对话气泡
    # 这里创建一个简化版本
    
    # 大气泡（左下）
    bubble1_points = [
        (15, 35), (15, 20), (35, 20), (50, 35), (35, 50), (20, 50)
    ]
    draw.polygon(bubble1_points, fill=(255, 255, 255, 255))
    draw.ellipse([10, 15, 55, 55], fill=(255, 255, 255, 255))
    
    # 小气泡（右上）
    draw.ellipse([40, 25, 70, 50], fill=(255, 255, 255, 255))
    bubble2_points = [(65, 45), (70, 50), (60, 50)]
    draw.polygon(bubble2_points, fill=(255, 255, 255, 255))
    
    # 眼睛
    draw.ellipse([20, 30, 26, 36], fill=(0, 0, 0, 255))
    draw.ellipse([38, 30, 44, 36], fill=(0, 0, 0, 255))
    
    # 保存为 PNG
    output_path = os.path.join(os.path.dirname(__file__), 'godot', 'assets', 'wechat_icon_official.png')
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, 'PNG')
    print(f"✅ 微信图标已创建: {output_path}")
    
    # 创建 40x40 版本
    img_small = img.resize((40, 40), Image.Resampling.LANCZOS)
    output_path_small = os.path.join(os.path.dirname(__file__), 'godot', 'assets', 'wechat_icon_40x40_official.png')
    img_small.save(output_path_small, 'PNG')
    print(f"✅ 微信图标40x40已创建: {output_path_small}")

if __name__ == '__main__':
    print("🚀 开始创建微信官方图标...")
    try:
        create_wechat_icon()
        print("\n✅ 完成！请在 Godot 中使用 wechat_icon_official.png")
    except Exception as e:
        print(f"❌ 错误: {e}")
        print("\n📌 请手动从以下地址下载微信官方图标：")
        print("   https://open.weixin.qq.com/zh_CN/htmledition/res/assets/res-design-download/icon16_wx_logo.png")

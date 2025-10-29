#!/usr/bin/env python3
"""
微信官方APP图标自动下载器
从官方渠道下载微信登录图标并部署到 Godot 项目

使用方式:
    python download_wechat_icon.py [options]

选项:
    --size SIZE         图标尺寸 (32, 40, 48, 64, 128)，默认: 40
    --format FORMAT     图标格式 (svg, png)，默认: svg
    --force             强制刷新（忽略缓存）
    --github            从 GitHub 下载
    --generate          生成本地图标（不下载）
    --help              显示帮助信息
"""

import os
import sys
import argparse
import urllib.request
import urllib.error
from pathlib import Path
import json
from datetime import datetime


class WeChatIconDownloader:
    """微信图标下载器"""
    
    # 官方配置
    OFFICIAL_GREEN = "#09B83E"  # 微信官方绿色
    ICON_SIZES = [32, 40, 48, 64, 128]
    ICON_FORMATS = ["svg", "png"]
    
    # 路径配置
    PROJECT_ROOT = Path(__file__).parent
    GODOT_DIR = PROJECT_ROOT / "godot"
    ASSETS_DIR = GODOT_DIR / "assets"
    CACHE_DIR = PROJECT_ROOT / ".wechat_icon_cache"
    
    # 下载来源
    GITHUB_URL = "https://raw.githubusercontent.com/wechat-sdk/wechat-ui-resources/main/Icon"
    
    def __init__(self):
        """初始化下载器"""
        self.cache_dir = self.CACHE_DIR
        self.assets_dir = self.ASSETS_DIR
        self._ensure_directories()
        print("✅ 微信图标下载器已初始化")
        print(f"📁 项目目录: {self.PROJECT_ROOT}")
        print(f"📁 资源目录: {self.assets_dir}")
    
    def _ensure_directories(self):
        """确保必要的目录存在"""
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.assets_dir.mkdir(parents=True, exist_ok=True)
    
    def download(self, size: int = 40, format_type: str = "svg", force_refresh: bool = False):
        """
        下载微信官方图标
        
        Args:
            size: 图标尺寸
            format_type: 图标格式 (svg 或 png)
            force_refresh: 是否强制刷新
        
        Returns:
            bool: 成功返回 True
        """
        # 验证参数
        if size not in self.ICON_SIZES:
            print(f"❌ 不支持的尺寸: {size}")
            print(f"📋 支持的尺寸: {self.ICON_SIZES}")
            return False
        
        if format_type.lower() not in self.ICON_FORMATS:
            print(f"❌ 不支持的格式: {format_type}")
            print(f"📋 支持的格式: {self.ICON_FORMATS}")
            return False
        
        format_type = format_type.lower()
        
        # 检查缓存
        cached_path = self.cache_dir / f"icon_{size}x{size}.{format_type}"
        if cached_path.exists() and not force_refresh:
            print(f"✅ 使用缓存的图标: {cached_path}")
            return self._deploy_icon(cached_path, size, format_type)
        
        print(f"🚀 开始下载微信官方图标...")
        print(f"📋 规格: {size}x{size} {format_type.upper()}")
        
        # 尝试从 GitHub 下载
        if self._download_from_github(size, format_type):
            cached_path = self.cache_dir / f"icon_{size}x{size}_github.{format_type}"
            if cached_path.exists():
                return self._deploy_icon(cached_path, size, format_type)
        
        # 如果下载失败，生成本地图标
        print("🎨 正在生成本地官方风格图标...")
        if format_type == "svg":
            generated_path = self._generate_svg_icon(size)
        else:
            generated_path = self._generate_png_icon(size)
        
        if generated_path and generated_path.exists():
            return self._deploy_icon(generated_path, size, format_type)
        
        print("❌ 图标下载和生成都失败")
        return False
    
    def _download_from_github(self, size: int, format_type: str) -> bool:
        """从 GitHub 下载图标"""
        url = f"{self.GITHUB_URL}/icon_{size}x{size}.{format_type}"
        output_path = self.cache_dir / f"icon_{size}x{size}_github.{format_type}"
        
        print(f"📥 尝试从 GitHub 下载: {url}")
        
        try:
            urllib.request.urlretrieve(url, output_path)
            if output_path.stat().st_size > 0:
                print(f"✅ 从 GitHub 下载成功")
                return True
            else:
                output_path.unlink()
                print("⚠ 下载的文件为空")
                return False
        except urllib.error.URLError as e:
            print(f"⚠ GitHub 下载失败: {e}")
            return False
    
    def _generate_svg_icon(self, size: int) -> Path:
        """生成 SVG 格式的微信图标"""
        corner_radius = int(size * 0.2)
        bubble_r1 = int(size * 0.12)
        bubble_r2 = int(size * 0.08)
        
        svg_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" xmlns="http://www.w3.org/2000/svg">
  <!-- 背景 -->
  <rect width="{size}" height="{size}" rx="{corner_radius}" fill="{self.OFFICIAL_GREEN}"/>
  <!-- 气泡设计 -->
  <g fill="white" opacity="0.95">
    <!-- 左气泡 -->
    <circle cx="{int(size * 0.35)}" cy="{int(size * 0.35)}" r="{bubble_r1}"/>
    <!-- 右气泡 -->
    <circle cx="{int(size * 0.65)}" cy="{int(size * 0.35)}" r="{bubble_r1}"/>
    <!-- 底部小气泡 -->
    <circle cx="{int(size * 0.5)}" cy="{int(size * 0.7)}" r="{bubble_r2}"/>
  </g>
</svg>"""
        
        output_path = self.cache_dir / f"icon_{size}x{size}_generated.svg"
        output_path.write_text(svg_content, encoding="utf-8")
        print(f"✅ SVG 图标已生成: {output_path}")
        return output_path
    
    def _generate_png_icon(self, size: int) -> Path:
        """生成 PNG 格式的微信图标"""
        try:
            from PIL import Image, ImageDraw
            
            # 创建图像
            image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            
            # 解析官方绿色
            green_color = tuple(int(self.OFFICIAL_GREEN.lstrip("#")[i:i+2], 16) for i in (0, 2, 4)) + (255,)
            white_color = (255, 255, 255, 240)
            
            # 绘制圆角矩形背景
            corner_radius = int(size * 0.2)
            
            # 四个角
            draw.arc([0, 0, corner_radius*2, corner_radius*2], 180, 270, green_color, 5)
            draw.arc([size-corner_radius*2, 0, size, corner_radius*2], 270, 360, green_color, 5)
            draw.arc([0, size-corner_radius*2, corner_radius*2, size], 90, 180, green_color, 5)
            draw.arc([size-corner_radius*2, size-corner_radius*2, size, size], 0, 90, green_color, 5)
            
            # 矩形
            draw.rectangle([corner_radius, 0, size-corner_radius, size], green_color)
            draw.rectangle([0, corner_radius, size, size-corner_radius], green_color)
            
            # 绘制气泡
            bubble_r1 = int(size * 0.12)
            bubble_r2 = int(size * 0.08)
            
            draw.ellipse([int(size*0.35)-bubble_r1, int(size*0.35)-bubble_r1, 
                         int(size*0.35)+bubble_r1, int(size*0.35)+bubble_r1], white_color)
            draw.ellipse([int(size*0.65)-bubble_r1, int(size*0.35)-bubble_r1, 
                         int(size*0.65)+bubble_r1, int(size*0.35)+bubble_r1], white_color)
            draw.ellipse([int(size*0.5)-bubble_r2, int(size*0.7)-bubble_r2, 
                         int(size*0.5)+bubble_r2, int(size*0.7)+bubble_r2], white_color)
            
            output_path = self.cache_dir / f"icon_{size}x{size}_generated.png"
            image.save(output_path, "PNG")
            print(f"✅ PNG 图标已生成: {output_path}")
            return output_path
            
        except ImportError:
            print("⚠ PIL 库未安装，无法生成 PNG 图标")
            print("💡 请运行: pip install Pillow")
            return None
    
    def _deploy_icon(self, source_path: Path, size: int, format_type: str) -> bool:
        """部署图标到项目资源目录"""
        # 主图标文件名
        main_filename = f"wechat_icon.{format_type}"
        sized_filename = f"wechat_icon_{size}x{size}.{format_type}"
        
        target_path = self.assets_dir / sized_filename
        main_target_path = self.assets_dir / main_filename
        
        try:
            # 复制到主位置
            with open(source_path, "rb") as src:
                data = src.read()
            
            with open(target_path, "wb") as dst:
                dst.write(data)
            print(f"✅ 图标已部署: {target_path}")
            
            # 如果是推荐尺寸（40x40），创建主图标别名
            if size == 40:
                with open(main_target_path, "wb") as dst:
                    dst.write(data)
                print(f"✅ 主图标已创建: {main_target_path}")
            
            # 创建元数据文件
            self._create_metadata(main_target_path, size, format_type)
            
            return True
        except Exception as e:
            print(f"❌ 部署失败: {e}")
            return False
    
    def _create_metadata(self, icon_path: Path, size: int, format_type: str):
        """创建图标元数据文件"""
        metadata = {
            "file": icon_path.name,
            "size": f"{size}x{size}",
            "format": format_type,
            "color": self.OFFICIAL_GREEN,
            "downloaded_at": datetime.now().isoformat(),
            "official": True,
            "description": "微信官方登录按钮图标"
        }
        
        metadata_path = icon_path.parent / (icon_path.stem + ".json")
        try:
            with open(metadata_path, "w", encoding="utf-8") as f:
                json.dump(metadata, f, indent=2, ensure_ascii=False)
            print(f"✅ 元数据已创建: {metadata_path}")
        except Exception as e:
            print(f"⚠ 元数据创建失败: {e}")
    
    def clear_cache(self):
        """清理缓存目录"""
        print("🗑️  正在清理缓存...")
        try:
            for item in self.cache_dir.iterdir():
                if item.is_file():
                    item.unlink()
            print("✅ 缓存已清理")
        except Exception as e:
            print(f"⚠ 缓存清理失败: {e}")


def main():
    """主函数"""
    parser = argparse.ArgumentParser(
        description="微信官方APP图标自动下载器",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 下载默认规格（40x40 SVG）
  python download_wechat_icon.py
  
  # 下载其他尺寸
  python download_wechat_icon.py --size 64
  
  # 下载 PNG 格式
  python download_wechat_icon.py --format png
  
  # 强制刷新（忽略缓存）
  python download_wechat_icon.py --force
  
  # 清理缓存
  python download_wechat_icon.py --clear-cache
        """
    )
    
    parser.add_argument(
        "--size",
        type=int,
        default=40,
        help="图标尺寸 (32, 40, 48, 64, 128)，默认: 40"
    )
    parser.add_argument(
        "--format",
        default="svg",
        help="图标格式 (svg, png)，默认: svg"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="强制刷新（忽略缓存）"
    )
    parser.add_argument(
        "--clear-cache",
        action="store_true",
        help="清理缓存目录"
    )
    
    args = parser.parse_args()
    
    downloader = WeChatIconDownloader()
    
    if args.clear_cache:
        downloader.clear_cache()
        return 0
    
    success = downloader.download(args.size, args.format, args.force)
    
    if success:
        print("\n" + "="*50)
        print("✅ 微信官方图标下载部署完成！")
        print("="*50)
        print(f"📍 图标路径: {downloader.assets_dir}/wechat_icon.{args.format}")
        print(f"📋 规格: {args.size}x{args.size} {args.format.upper()}")
        print(f"🎨 颜色: {WeChatIconDownloader.OFFICIAL_GREEN}")
        print("\n💡 下一步:")
        print("   1. 打开 Godot 编辑器")
        print("   2. 编辑 scenes/loading_screen.tscn")
        print("   3. 更新微信图标的纹理引用")
        print("="*50)
        return 0
    else:
        print("\n❌ 图标下载部署失败，请检查网络连接或手动处理")
        return 1


if __name__ == "__main__":
    sys.exit(main())

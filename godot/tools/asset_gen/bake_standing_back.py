#!/usr/bin/env python3
"""烘焙「站立牌背」贴图(T3d,spec 2026-06-11 G3)。

对手手牌的视角是"从后上方看一排立着的牌":顶部一条白色牌面棱 +
灰白倒角 + 牌背主体。对标参考作 .hand--top .tile--back 的渐变结构。
SeatPanel 的手牌行在本地坐标横排、由面板旋转定向,所以一张贴图四家通用。

用法:
    python3 godot/tools/asset_gen/bake_standing_back.py
    godot --headless --path godot --import
"""
from PIL import Image, ImageDraw

W, H = 120, 180
OUT = "godot/assets/tile_back_standing.png"

IVORY_TOP = (250, 248, 238)
IVORY_BOT = (216, 214, 200)
BEVEL = (138, 136, 120)
BACK_TOP = (44, 91, 62)    # #2c5b3e
BACK_BOT = (26, 58, 38)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# 左右家侧视体块(参考截图:白色厚牌身 + 绿色窄顶,绿顶朝桌心):
# 白身 68% + 倒角 + 绿顶 27%,牌"躺着看是厚的"。
def bake_side() -> None:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cap_h = int(H * 0.27)
    bevel_h = int(H * 0.05)
    for y in range(cap_h):
        c = lerp(BACK_TOP, BACK_BOT, y / max(1, cap_h - 1) * 0.6)
        d.line([(0, y), (W, y)], fill=c + (255,))
    for y in range(cap_h, cap_h + bevel_h):
        t = (y - cap_h) / max(1, bevel_h - 1)
        c = lerp(BEVEL, IVORY_TOP, t)
        d.line([(0, y), (W, y)], fill=c + (255,))
    for y in range(cap_h + bevel_h, H):
        t = (y - cap_h - bevel_h) / max(1, H - cap_h - bevel_h - 1)
        c = lerp(IVORY_TOP, IVORY_BOT, t)
        d.line([(0, y), (W, y)], fill=c + (255,))
    d.rectangle([0, 0, 1, H - 1], fill=(60, 58, 50, 255))
    d.rectangle([W - 2, 0, W - 1, H - 1], fill=(60, 58, 50, 255))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=10, fill=255)
    img.putalpha(mask)
    out = "godot/assets/tile_back_side.png"
    img.save(out)
    print(f"done: {out} ({W}x{H})")


def bake() -> None:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    face_h = int(H * 0.13)   # 白色牌面棱
    bevel_h = int(H * 0.045)  # 灰白倒角
    # 牌面棱(顶部圆角)
    for y in range(face_h):
        c = lerp(IVORY_TOP, IVORY_BOT, y / max(1, face_h - 1))
        d.line([(0, y), (W, y)], fill=c + (255,))
    # 倒角
    for y in range(face_h, face_h + bevel_h):
        t = (y - face_h) / max(1, bevel_h - 1)
        c = lerp(BEVEL, BACK_TOP, t)
        d.line([(0, y), (W, y)], fill=c + (255,))
    # 牌背主体(纵向渐变)
    for y in range(face_h + bevel_h, H):
        t = (y - face_h - bevel_h) / max(1, H - face_h - bevel_h - 1)
        c = lerp(BACK_TOP, BACK_BOT, t)
        d.line([(0, y), (W, y)], fill=c + (255,))
    # 左右 2px 暗边 + 1px 内高光,制造圆柱体侧光
    d.rectangle([0, 0, 1, H - 1], fill=(10, 22, 14, 255))
    d.rectangle([W - 2, 0, W - 1, H - 1], fill=(10, 22, 14, 255))
    d.line([(2, face_h + bevel_h), (2, H - 3)], fill=(255, 255, 255, 28))
    # 圆角裁切
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=10, fill=255)
    img.putalpha(mask)
    img.save(OUT)
    print(f"done: {OUT} ({W}x{H})")


if __name__ == "__main__":
    bake()
    bake_side()

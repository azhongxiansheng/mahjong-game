#!/usr/bin/env python3
"""烘焙麻将桌面:毛毡纹理 + 木质边框(T3,spec 2026-06-11 G3)。

对标参考作的 .table-felt(#1f5132 + feTurbulence 噪声)与 .table-rail
(木纹渐变 + 暖白高光线)。输出单张 1080×720 PNG,FourPlayerTable 的
TableFelt TextureRect 直接整图贴,无需布局代码改动。

用法:
    python3 godot/tools/asset_gen/bake_table_felt.py
    godot --headless --path godot --import
"""
import random
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

W, H = 1080, 720
FRAME = 26          # 木框宽
# 参考作 #1f5132 压暗 ~20%(我们无 3D 暗场,Akagi 氛围靠基色自己扛)
FELT = (24, 64, 40)
OUT = "godot/assets/table_felt.png"

# 木纹色带(外→内):深红褐 → 焦黑
WOOD = [(78, 29, 17), (62, 23, 9), (42, 14, 7), (14, 4, 2)]


def _noise_layer(w: int, h: int, sigma: int, scale: int) -> Image.Image:
    small = Image.effect_noise((max(1, w // scale), max(1, h // scale)), sigma)
    return small.resize((w, h), Image.BILINEAR)


def bake() -> None:
    random.seed(20260611)
    img = Image.new("RGB", (W, H), FELT)

    # 毛毡噪声:高频细绒 + 低频布纹两个 octave
    fine = _noise_layer(W, H, 24, 1)
    coarse = _noise_layer(W, H, 32, 5)
    img = Image.composite(
        ImageEnhance.Brightness(img).enhance(1.10), img, fine.point(lambda v: (v - 118) if v > 118 else 0))
    img = Image.composite(
        ImageEnhance.Brightness(img).enhance(0.92), img, coarse.point(lambda v: (118 - v) if v < 118 else 0))

    # 中心提亮 + 四角暗角(径向渐变蒙版)
    radial = Image.radial_gradient("L").resize((W, H), Image.BILINEAR)  # 中心 0 → 边缘 255
    bright = ImageEnhance.Brightness(img).enhance(1.12)
    img = Image.composite(img, bright, radial.point(lambda v: min(255, int(v * 1.35))))
    dark = ImageEnhance.Brightness(img).enhance(0.62)
    img = Image.composite(dark, img, radial.point(lambda v: max(0, int((v - 135) * 2.2))))

    # 木框:四边渐变色带 + 内缘暖白高光线 + 外缘压黑
    draw = ImageDraw.Draw(img)
    band = FRAME / float(len(WOOD))
    for i, color in enumerate(WOOD):
        inset = int(i * band)
        draw.rectangle([inset, inset, W - 1 - inset, H - 1 - inset],
                       outline=color, width=max(1, int(band) + 1))
    # 木纹细条(沿框走向的随机深浅线)
    grain = ImageDraw.Draw(img, "RGBA")
    for _ in range(260):
        side = random.randint(0, 3)
        v = random.randint(-14, 14)
        a = random.randint(14, 38)
        if side in (0, 1):  # 上/下
            y0 = random.randint(2, FRAME - 4) if side == 0 else H - 1 - random.randint(2, FRAME - 4)
            x0 = random.randint(0, W - 90)
            grain.line([(x0, y0), (x0 + random.randint(30, 90), y0)],
                       fill=(78 + v, 29 + v // 2, 17, a), width=1)
        else:  # 左/右
            x0 = random.randint(2, FRAME - 4) if side == 2 else W - 1 - random.randint(2, FRAME - 4)
            y0 = random.randint(0, H - 90)
            grain.line([(x0, y0), (x0, y0 + random.randint(30, 90))],
                       fill=(78 + v, 29 + v // 2, 17, a), width=1)
    # 内缘暖白高光线(参考作 .table-rail:before)
    hl = ImageDraw.Draw(img, "RGBA")
    hl.rectangle([FRAME - 2, FRAME - 2, W - FRAME + 1, H - FRAME + 1],
                 outline=(255, 235, 215, 150), width=2)
    # 高光线内侧 1px 阴影让框"压"在毛毡上
    hl.rectangle([FRAME, FRAME, W - FRAME - 1, H - FRAME - 1],
                 outline=(0, 0, 0, 110), width=2)
    # 外缘 1px 黑
    draw.rectangle([0, 0, W - 1, H - 1], outline=(4, 2, 1), width=2)

    img = img.filter(ImageFilter.GaussianBlur(0.4))
    img.save(OUT)
    print(f"done: {OUT} ({W}x{H})")


if __name__ == "__main__":
    bake()

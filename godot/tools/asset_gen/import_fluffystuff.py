#!/usr/bin/env python3
"""把 FluffyStuff/riichi-mahjong-tiles (CC0) 的 PNG 导出合成为本项目的 38 张标准牌。

来源: https://github.com/FluffyStuff/riichi-mahjong-tiles (public domain / CC0 1.0)
该仓库的 Export/<Variant>/ 里牌面图案与牌底 (Front.png) 是分离的同尺寸
600x800 RGBA 画布;本脚本 alpha 合成 Front + 牌面,再 LANCZOS 缩放到
TextureExtractor 约定的 272x389(纵横比 0.75→0.699 有 ~7% 水平压缩,
显示尺寸 28-60px 下不可感知)。

用法:
    git clone --depth 1 https://github.com/FluffyStuff/riichi-mahjong-tiles /tmp/riichi-mahjong-tiles
    python3 godot/tools/asset_gen/import_fluffystuff.py \
        --src /tmp/riichi-mahjong-tiles/Export/Regular \
        --out _staging_fluffystuff
    # 人工 QA 后:
    cp _staging_fluffystuff/*.png godot/assets/mahjong_tiles_riichi/
    godot --headless --path godot --import
"""
import argparse
import os
from PIL import Image, ImageDraw

TILE_W, TILE_H = 272, 389

# 项目 key → FluffyStuff 文件名(不含 .png)
MAPPING = {
    **{f"{n}m": f"Man{n}" for n in range(1, 10)},
    **{f"{n}p": f"Pin{n}" for n in range(1, 10)},
    **{f"{n}s": f"Sou{n}" for n in range(1, 10)},
    "0m": "Man5-Dora",  # 赤五万
    "0p": "Pin5-Dora",  # 赤五筒
    "0s": "Sou5-Dora",  # 赤五索
    "1z": "Ton",    # 东
    "2z": "Nan",    # 南
    "3z": "Shaa",   # 西
    "4z": "Pei",    # 北
    "5z": "Haku",   # 白
    "6z": "Hatsu",  # 发
    "7z": "Chun",   # 中
    "back": "Back",  # 牌背(自带完整牌体,不合成 Front)
}


# Black 变体的白(Haku)是全黑空白面,与黑色牌背无法区分(白是常用役牌,
# 实战致命)。实体黑牌套装的惯例是给白刻一圈描边 — 这里画白色圆角矩形框。
def _draw_haku_frame(tile: Image.Image) -> Image.Image:
    draw = ImageDraw.Draw(tile)
    w, h = tile.size  # 600x800 源尺寸下 inset 90 / 线宽 14
    inset_x, inset_y = int(w * 0.15), int(h * 0.15)
    draw.rounded_rectangle(
        [inset_x, inset_y, w - inset_x, h - inset_y],
        radius=int(w * 0.06),
        outline=(235, 235, 235, 230),
        width=max(2, int(w * 0.023)),
    )
    return tile


def convert(src_dir: str, out_dir: str, haku_frame: bool = False) -> None:
    os.makedirs(out_dir, exist_ok=True)
    front = Image.open(os.path.join(src_dir, "Front.png")).convert("RGBA")
    for key, name in sorted(MAPPING.items()):
        face = Image.open(os.path.join(src_dir, f"{name}.png")).convert("RGBA")
        if key == "back":
            tile = face  # Back.png 是完整牌体
        else:
            if face.size != front.size:
                face = face.resize(front.size, Image.LANCZOS)
            tile = Image.alpha_composite(front, face)
        if key == "5z" and haku_frame:
            tile = _draw_haku_frame(tile)
        tile = tile.resize((TILE_W, TILE_H), Image.LANCZOS)
        path = os.path.join(out_dir, f"{key}.png")
        tile.save(path)
        print(f"[ok] {key:5s} <- {name}.png -> {path}")
    print(f"done: {len(MAPPING)} tiles -> {out_dir}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="FluffyStuff Export/Regular 或 Export/Black 目录")
    ap.add_argument("--out", default="_staging_fluffystuff")
    ap.add_argument("--haku-frame", action="store_true",
                    help="给白(5z)画描边框 — Black 变体必开,否则与黑牌背无法区分")
    args = ap.parse_args()
    convert(args.src, args.out, args.haku_frame)

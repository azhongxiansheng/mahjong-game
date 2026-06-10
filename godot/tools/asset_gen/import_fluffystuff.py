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
from PIL import Image

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


def convert(src_dir: str, out_dir: str) -> None:
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
        tile = tile.resize((TILE_W, TILE_H), Image.LANCZOS)
        path = os.path.join(out_dir, f"{key}.png")
        tile.save(path)
        print(f"[ok] {key:5s} <- {name}.png -> {path}")
    print(f"done: {len(MAPPING)} tiles -> {out_dir}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="FluffyStuff Export/Regular 或 Export/Black 目录")
    ap.add_argument("--out", default="_staging_fluffystuff")
    args = ap.parse_args()
    convert(args.src, args.out)

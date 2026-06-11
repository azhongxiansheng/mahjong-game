#!/usr/bin/env python3
"""把 Kenney Fantasy UI Borders (CC0) 烘焙成本项目主题色的九宫格面板/按钮贴图。

来源: https://kenney.nl/assets/fantasy-ui-borders (CC0 1.0)
输入: 解压包的 PNG/Double/Transparent center/panel-transparent-center-XXX.png
      (96×96,白色描边 + 透明中心,专为染色设计)
处理: 白边乘以主题色 + 垫深色圆角中心 → 输出成品 9-slice PNG。
      run_theme.tres 的 StyleBoxTexture 以 texture_margin=32 切九宫格。

用法:
    curl -sL -o /tmp/kenney_fantasy_ui.zip \
        "https://kenney.nl/media/pages/assets/fantasy-ui-borders/ab29cd0165-1701602367/kenney_fantasy-ui-borders.zip"
    unzip -q /tmp/kenney_fantasy_ui.zip -d /tmp/kenney_fantasy_ui
    python3 godot/tools/asset_gen/bake_ui_borders.py \
        --src "/tmp/kenney_fantasy_ui/PNG/Double/Transparent center" \
        --out godot/assets/ui
    godot --headless --path godot --import
"""
import argparse
import os
from PIL import Image, ImageDraw

# 设计选型:008 = 回纹角(中式纹样,面板用);014 = 简洁双线(按钮用)
PANEL_DESIGN = "panel-transparent-center-008.png"
BUTTON_DESIGN = "panel-transparent-center-014.png"

# (输出名, 设计, 边框色 RGB 0-1, 中心色 RGBA 0-1) — 与 run_theme.tres 旧 Flat 色一致
RECIPES = [
    ("panel_ornate", PANEL_DESIGN, (0.62, 0.18, 0.19), (0.10, 0.09, 0.12, 0.97)),
    ("btn_normal", BUTTON_DESIGN, (0.55, 0.15, 0.16), (0.15, 0.14, 0.17, 1.0)),
    ("btn_hover", BUTTON_DESIGN, (0.88, 0.22, 0.24), (0.25, 0.18, 0.20, 1.0)),
    ("btn_pressed", BUTTON_DESIGN, (0.98, 0.36, 0.28), (0.42, 0.10, 0.12, 1.0)),
    ("btn_disabled", BUTTON_DESIGN, (0.30, 0.30, 0.32), (0.11, 0.11, 0.12, 1.0)),
]


# 素材 alpha 结构(已验证纯三档,无抗锯齿):
#   255 = 描边线条 → 染 border_rgb
#   127 = 中心半透明白填充 → 替换为 center_rgba(这是"Transparent center"
#         的真实含义;直接染色会让中心被边框色污染成酱红)
#   0   = 外部 → 保持透明
def bake(src_dir: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for name, design, border_rgb, center_rgba in RECIPES:
        img = Image.open(os.path.join(src_dir, design)).convert("RGBA")
        br, bg_, bb = (int(c * 255) for c in border_rgb)
        cr, cg, cb, ca = (int(c * 255) for c in center_rgba)
        px = img.load()
        for y in range(img.height):
            for x in range(img.width):
                _, _, _, pa = px[x, y]
                if pa == 255:
                    px[x, y] = (br, bg_, bb, 255)
                elif pa > 0:
                    px[x, y] = (cr, cg, cb, ca)
        path = os.path.join(out_dir, f"{name}.png")
        img.save(path)
        print(f"[ok] {name} <- {design}")
    print(f"done: {len(RECIPES)} -> {out_dir}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="Kenney PNG/Double/Transparent center 目录")
    ap.add_argument("--out", default="godot/assets/ui")
    args = ap.parse_args()
    bake(args.src, args.out)

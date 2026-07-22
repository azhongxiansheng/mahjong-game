#!/usr/bin/env python3
"""Generate roguelike item icons (and optional character drafts) via gpt-image-2.

Character portraits MUST default to an explicit staging subdirectory under
godot/tools/asset_gen/_staging/ — never the production assets/roguelike tree.

Usage:
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --all
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --characters
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --relics
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --consumables
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --check-char-out DIR
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# 道具等非角色图标：仍可写 roguelike 子目录（生产可审）
OUT_DIR = Path(__file__).resolve().parent.parent.parent / "assets" / "roguelike"

# 角色立绘默认只进 staging 明确子目录（gitignore），禁止污染生产
CHAR_STAGING_DIR = Path(__file__).resolve().parent / "_staging" / "characters"

STYLE_PREFIX = (
    "Original 2D anime game character portrait, modern urban supernatural "
    "mahjong club aesthetic, dramatic contour lighting, chunibyo stylish energy, "
    "clean dark gradient background, no text, no watermark, no logo, "
    "no hexagrams, no yin-yang, no traditional fortune symbols. "
)

# 原创角色草稿：文件名与生产 id 对齐；仅写入 CHAR_STAGING_DIR
CHARACTERS = {
    "char_lin_yeche": {
        "prompt": (
            STYLE_PREFIX
            + "Young man, sharp night-reader, deep indigo coat, thin glasses, "
            "cold calculating expression, semi-transparent tile silhouettes near hand. "
            "Half-body portrait."
        ),
        "size": "1024x1536",
    },
    "char_qiu_jue": {
        "prompt": (
            STYLE_PREFIX
            + "Young man, messy black hair, small bandages, zipper jacket, "
            "orange-red adversity flame aura, wild grin while nearly losing. "
            "Short straight nose, original face. Half-body portrait."
        ),
        "size": "1024x1536",
    },
    "char_bai_touli": {
        "prompt": (
            STYLE_PREFIX
            + "Young woman, silver-white long hair, glass-like modern robe, "
            "cool white and lavender light, polite pressure. "
            "Clear ordinary mahjong tiles or plain translucent rectangles only. "
            "Half-body portrait."
        ),
        "size": "1024x1536",
    },
}

RELICS = {
    "relic_lucky_cat": {
        "prompt": (
            "Game icon, Japanese lucky cat (maneki-neko) figurine glowing with golden aura, "
            "one paw raised, sitting on a mahjong tile. Dark background, anime RPG item style. "
            "Clean edges, suitable for game UI icon."
        ),
    },
    "relic_iron_will": {
        "prompt": (
            "Game icon, a small iron shield with Japanese kanji engraved, "
            "glowing blue defensive aura. Dark background, anime RPG item style. "
            "Clean edges, suitable for game UI icon."
        ),
    },
    "relic_soul_mirror": {
        "prompt": (
            "Game icon, a cracked hand mirror reflecting a ghostly mahjong tile, "
            "purple ethereal glow. Dark background, anime RPG item style. "
            "Clean edges, suitable for game UI icon."
        ),
    },
    "relic_wall_eye": {
        "prompt": (
            "Game icon, a mystical floating eye with a mahjong wall pattern in the iris, "
            "green supernatural glow. Dark background, anime RPG item style. "
            "Clean edges, suitable for game UI icon."
        ),
    },
}

CONSUMABLES = {
    "consumable_iron_shield": {
        "prompt": (
            "Game icon, a temporary magical shield made of translucent blue energy, "
            "with a mahjong tile pattern. One-use item aesthetic with cracks. "
            "Dark background, anime RPG consumable style."
        ),
    },
    "consumable_wall_peek": {
        "prompt": (
            "Game icon, a glowing crystal ball showing tiny mahjong tiles inside, "
            "golden divination energy. Dark background, anime RPG consumable style. "
            "Clean edges, suitable for game UI icon."
        ),
    },
    "consumable_double_payout": {
        "prompt": (
            "Game icon, a golden ticket or voucher with '×2' written in bold, "
            "surrounded by sparkling coins and mahjong tiles. "
            "Dark background, anime RPG consumable style."
        ),
    },
    "consumable_dora_charm": {
        "prompt": (
            "Game icon, a red charm bag with a dora mahjong tile peeking out, "
            "golden thread embroidery, mystical red glow. "
            "Dark background, anime RPG consumable style."
        ),
    },
}


def production_characters_dir() -> Path:
    return (OUT_DIR / "characters").resolve()


def is_forbidden_character_output_dir(
    out_dir: Path | str,
    *,
    prod_characters: Path | str | None = None,
) -> bool:
    """True if out_dir is production characters root or any nested path under it.

    Uses pathlib resolve + relative_to so Windows backslashes cannot bypass.
    """
    target = Path(out_dir).expanduser().resolve()
    prod = (
        Path(prod_characters).expanduser().resolve()
        if prod_characters is not None
        else production_characters_dir()
    )
    if target == prod:
        return True
    try:
        target.relative_to(prod)
        return True
    except ValueError:
        return False


def validate_character_output_dir(
    out_dir: Path | str,
    *,
    prod_characters: Path | str | None = None,
) -> None:
    """Require character drafts to stay inside the dedicated staging tree."""
    if is_forbidden_character_output_dir(out_dir, prod_characters=prod_characters):
        raise RuntimeError(
            "refusing to write characters into production assets/roguelike/characters "
            f"(or nested): {out_dir}"
        )

    target = Path(out_dir).expanduser().resolve()
    staging = CHAR_STAGING_DIR.resolve()
    if target != staging:
        try:
            target.relative_to(staging)
        except ValueError as exc:
            raise RuntimeError(
                "character drafts must stay inside tools/asset_gen/_staging/characters: "
                f"{out_dir}"
            ) from exc


def generate_one(name: str, prompt: str, size: str, out_dir: Path) -> Path | None:
    import gen_client  # lazy: --check-char-out 不触发付费客户端

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{name}.png"
    print(f"  Generating {name}...")
    try:
        blobs = gen_client.generate(
            prompt=prompt,
            size=size,
            background="transparent",
            quality="high",
        )
        out_path.write_bytes(blobs[0])
        print(f"  -> {out_path} ({len(blobs[0])} bytes)")
        return out_path
    except Exception as e:
        print(f"  ERROR: {name}: {e}")
        return None


def generate_characters(out_dir: Path | None = None) -> None:
    """Write character drafts only after pathlib production-tree rejection."""
    print("=== Generating character portraits (staging only) ===")
    char_dir = CHAR_STAGING_DIR if out_dir is None else Path(out_dir)
    validate_character_output_dir(char_dir)
    for name, spec in CHARACTERS.items():
        generate_one(name, spec["prompt"], spec.get("size", "1024x1536"), char_dir)


def generate_relics(out_dir: Path) -> None:
    print("=== Generating relic icons ===")
    relic_dir = out_dir / "relics"
    for name, spec in RELICS.items():
        generate_one(name, spec["prompt"], "1024x1024", relic_dir)


def generate_consumables(out_dir: Path) -> None:
    print("=== Generating consumable icons ===")
    cons_dir = out_dir / "consumables"
    for name, spec in CONSUMABLES.items():
        generate_one(name, spec["prompt"], "1024x1024", cons_dir)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate roguelike game assets")
    parser.add_argument("--all", action="store_true", help="Generate all assets")
    parser.add_argument("--characters", action="store_true", help="Character portraits (staging)")
    parser.add_argument("--relics", action="store_true", help="Relic icons")
    parser.add_argument("--consumables", action="store_true", help="Consumable icons")
    parser.add_argument(
        "--check-char-out",
        metavar="DIR",
        help="Validate character output dir only (exit 0 allow / 1 forbid); no generation",
    )
    args = parser.parse_args(argv)

    if args.check_char_out is not None:
        try:
            validate_character_output_dir(args.check_char_out)
        except RuntimeError as e:
            print(str(e), file=sys.stderr)
            return 1
        print("OK")
        return 0

    # 无显式目标：只打印帮助，绝不默认 --all（防止覆盖生产 relic/consumable）
    if not (args.all or args.characters or args.relics or args.consumables):
        parser.print_help()
        print(
            "\nerror: specify at least one of --characters / --relics / "
            "--consumables / --all / --check-char-out",
            file=sys.stderr,
        )
        return 2

    if args.all or args.characters:
        generate_characters(CHAR_STAGING_DIR)
    if args.all or args.relics:
        generate_relics(OUT_DIR)
    if args.all or args.consumables:
        generate_consumables(OUT_DIR)

    print("\nDone. Characters staging:", CHAR_STAGING_DIR)
    print("Item icons at:", OUT_DIR)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

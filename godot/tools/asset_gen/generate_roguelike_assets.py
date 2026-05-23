#!/usr/bin/env python3
"""Generate roguelike character portraits + item icons via gpt-image-2.

Usage:
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --all
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --characters
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --relics
    python3 godot/tools/asset_gen/generate_roguelike_assets.py --consumables
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import gen_client

OUT_DIR = Path(__file__).resolve().parent.parent.parent / "assets" / "roguelike"

STYLE_PREFIX = (
    "Anime art style inspired by Nobuyuki Fukumoto (Akagi/Kaiji) manga. "
    "Dark dramatic lighting, high contrast shadows, intense expressions. "
)

CHARACTERS = {
    "char_akagi": {
        "prompt": (
            STYLE_PREFIX +
            "Portrait of a young Japanese man with sharp eyes, silver-white spiky hair, "
            "wearing a dark high-collar coat. Cold, calculating expression. "
            "He is a legendary mahjong genius nicknamed 'the demon'. "
            "Background: dark red abstract swirls. Half-body portrait, facing slightly left."
        ),
        "size": "1024x1536",
    },
    "char_kaiji": {
        "prompt": (
            STYLE_PREFIX +
            "Portrait of a young Japanese man with distinctive long pointed nose, "
            "messy dark hair, wearing a worn grey hoodie. Desperate but determined expression, "
            "tears streaming. He is a gambler who thrives in adversity. "
            "Background: dark blue abstract with gambling chips. Half-body portrait."
        ),
        "size": "1024x1536",
    },
    "char_washizu": {
        "prompt": (
            STYLE_PREFIX +
            "Portrait of an elderly Japanese man, bald head, sharp sunken eyes, "
            "wearing a traditional dark kimono. Menacing aristocratic aura. "
            "He is a wealthy yakuza boss who plays mahjong with transparent tiles. "
            "Background: dark purple with gold accents. Half-body portrait."
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
            "Game icon, a small iron shield with Japanese kanji '鉄' engraved, "
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
            "Game icon, a red Japanese omamori charm bag with a dora mahjong tile peeking out, "
            "golden thread embroidery, mystical red glow. "
            "Dark background, anime RPG consumable style."
        ),
    },
}


def generate_one(name: str, prompt: str, size: str, out_dir: Path) -> Path:
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


def generate_characters(out_dir: Path) -> None:
    print("=== Generating character portraits ===")
    char_dir = out_dir / "characters"
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


def main():
    parser = argparse.ArgumentParser(description="Generate roguelike game assets")
    parser.add_argument("--all", action="store_true", help="Generate all assets")
    parser.add_argument("--characters", action="store_true", help="Character portraits")
    parser.add_argument("--relics", action="store_true", help="Relic icons")
    parser.add_argument("--consumables", action="store_true", help="Consumable icons")
    args = parser.parse_args()

    if not (args.all or args.characters or args.relics or args.consumables):
        args.all = True

    if args.all or args.characters:
        generate_characters(OUT_DIR)
    if args.all or args.relics:
        generate_relics(OUT_DIR)
    if args.all or args.consumables:
        generate_consumables(OUT_DIR)

    print("\nDone! Assets at:", OUT_DIR)


if __name__ == "__main__":
    main()

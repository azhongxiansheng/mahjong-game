"""CLI: generate mahjong tiles as per-suit ROW SHEETS, then slice them.

Instead of 38 separate API calls (slow, style drifts tile-to-tile), each suit
is generated as ONE image — a horizontal row of all its tiles — so the whole
suit shares identical lighting/palette. The row is then sliced into individual
tiles by detecting the transparent column gaps between them.

A single 38-tile sheet would make the model garble pip counts / kanji, so the
unit is one sheet per suit (9 m / 9 p / 9 s / 7 honors / 4 extras).

Usage:
  python3 generate_sheets.py --all              # all 5 sheets
  python3 generate_sheets.py --sheet man,sou    # specific sheets
"""
from __future__ import annotations

import argparse
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import gen_client
import postprocess

HERE = Path(__file__).resolve().parent
STAGING_DIR = HERE / "_staging_sheets"
RAW_DIR = HERE / "_raw_sheets"

_DRAMA_STYLE = (
    "Each tile is an upright aged ivory-bone rectangle with rounded corners "
    "and a subtle bevel, crisply carved engraving, strong directional "
    "shading, gritty 1990s seinen-manga gambling aesthetic. All tiles "
    "identical in size. CRITICAL LAYOUT: the tiles are spread out across the "
    "full width of a wide landscape image, widely separated, with a large "
    "empty transparent gap — at least half a tile wide — between every pair "
    "of adjacent tiles. The tiles must NEVER touch or overlap. Fully "
    "transparent background, no drop shadows, no connecting strip or shelf "
    "under the tiles. No text outside the tile faces, no watermark, no extra "
    "tiles."
)

_MAX_TRIES = 4

# (sheet_key, [tile keys left->right], prompt body)
_SHEETS: dict[str, tuple[list[str], str]] = {
    "man": (
        [f"{n}m" for n in range(1, 10)],
        "A single horizontal row of exactly NINE traditional riichi mahjong "
        "tiles, the manzu suit, left to right 1-man through 9-man. Each tile "
        "shows its Chinese numeral (一, 二, 三, 四, 五, 六, 七, 八, 九 "
        "respectively) above a large 萬 character, carved in black ink.",
    ),
    "pin": (
        [f"{n}p" for n in range(1, 10)],
        "A single horizontal row of exactly NINE traditional riichi mahjong "
        "tiles, the pinzu (circles) suit, left to right 1-pin through 9-pin. "
        "Each tile face shows that many flat concentric-ring circular dot "
        "symbols: the 1st tile 1 dot, 2nd 2 dots, 3rd 3 dots, 4th 4 dots, 5th "
        "5 dots, 6th 6 dots, 7th 7 dots, 8th 8 dots, 9th 9 dots.",
    ),
    "sou": (
        [f"{n}s" for n in range(1, 10)],
        "A single horizontal row of exactly NINE traditional riichi mahjong "
        "tiles, the souzu (bamboo) suit, left to right 1-sou through 9-sou. "
        "The 1st tile shows a single ornate green bird perched on bamboo. "
        "Every other tile shows that many bright GREEN bamboo-stalk symbols, "
        "each stalk clearly drawn as a short segmented bamboo cane with "
        "visible nodes and tapered ends, in the classic mahjong souzu style "
        "(2nd tile 2 stalks, 3rd 3, 4th 4, 5th 5, 6th 6, 7th 7, 8th 8, 9th "
        "9). The bamboo must look like real bamboo stalks, never abstract "
        "slots or empty rectangles.",
    ),
    "honor": (
        [f"{n}z" for n in range(1, 8)],
        "A single horizontal row of exactly SEVEN traditional riichi mahjong "
        "honor tiles, left to right: East wind 東 (black), South wind 南 "
        "(black), West wind 西 (black), North wind 北 (black), White dragon "
        "(a clean blue rectangular double-line frame, blank inside), Green "
        "dragon 發 (green), Red dragon 中 (red).",
    ),
    "extra": (
        ["0m", "0p", "0s", "back"],
        "A single horizontal row of exactly FOUR traditional riichi mahjong "
        "tiles, left to right: a red-five-man tile (五萬 with the 五 numeral "
        "in vermilion red), a red-five-pin tile (5 circular dots with the "
        "center dot vermilion red), a red-five-sou tile (5 green bamboo "
        "sticks with the center stick vermilion red), and a plain tile BACK "
        "(solid deep jade-green surface, no symbols at all).",
    ),
}


def _slice_and_save(sheet_key: str, raw: bytes, out_dir: Path) -> list[str]:
    keys, _ = _SHEETS[sheet_key]
    out_dir.mkdir(parents=True, exist_ok=True)
    crops = postprocess.slice_row(raw, len(keys))
    if len(crops) != len(keys):
        print(f"  WARN {sheet_key}: sliced {len(crops)} tiles, expected "
              f"{len(keys)} — sheet needs regen", file=sys.stderr)
        return keys
    for key, crop in zip(keys, crops):
        fitted = postprocess.fit_image_to_box(
            crop, postprocess.TILE_SIZE, pad_ratio=0.04, trim_thresh=80)
        postprocess.save_png(fitted, str(out_dir / f"{key}.png"))
        print(f"  ok  {key}.png")
    return []


def _gen_sheet(sheet_key: str, out_dir: Path) -> list[str]:
    """Generate one suit sheet, retrying until it slices cleanly.

    A sheet is only usable if it slices into exactly the expected tile count;
    a cramped layout where tiles touch is regenerated (up to _MAX_TRIES).
    """
    keys, body = _SHEETS[sheet_key]
    prompt = body + " " + _DRAMA_STYLE
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, _MAX_TRIES + 1):
        blobs = gen_client.generate(prompt, size="1536x1024",
                                    background="transparent")
        raw = blobs[0]
        crops = postprocess.slice_row(raw, len(keys))
        if len(crops) == len(keys):
            (RAW_DIR / f"{sheet_key}.png").write_bytes(raw)
            for key, crop in zip(keys, crops):
                fitted = postprocess.fit_image_to_box(
                    crop, postprocess.TILE_SIZE, pad_ratio=0.04, trim_thresh=80)
                postprocess.save_png(fitted, str(out_dir / f"{key}.png"))
            print(f"  ok  {sheet_key}: {len(keys)} tiles (attempt {attempt})")
            return []
        print(f"  retry {sheet_key}: sliced {len(crops)}/{len(keys)} "
              f"(attempt {attempt})", file=sys.stderr)
    print(f"  FAIL {sheet_key}: unsliceable after {_MAX_TRIES} tries",
          file=sys.stderr)
    return keys


def _reslice(sheet_key: str, out_dir: Path) -> list[str]:
    """Re-slice an already-generated raw sheet (no API call)."""
    raw_path = RAW_DIR / f"{sheet_key}.png"
    if not raw_path.exists():
        print(f"  FAIL {sheet_key}: no raw sheet at {raw_path}", file=sys.stderr)
        return _SHEETS[sheet_key][0]
    return _slice_and_save(sheet_key, raw_path.read_bytes(), out_dir)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--reslice", action="store_true",
                    help="re-slice existing raw sheets, no API call")
    args = ap.parse_args()

    if args.all:
        sheets = list(_SHEETS.keys())
    elif args.sheet:
        sheets = [s.strip() for s in args.sheet.split(",") if s.strip()]
    else:
        ap.error("pick --all or --sheet <name,...>")
        return 2
    bad = [s for s in sheets if s not in _SHEETS]
    if bad:
        print(f"unknown sheets: {bad}", file=sys.stderr)
        return 2

    out_dir = Path(args.out) if args.out else STAGING_DIR
    verb = "re-slicing" if args.reslice else "generating"
    print(f"{verb} {len(sheets)} suit sheet(s) -> {out_dir}")
    failures: list[str] = []

    def _worker(s: str) -> list[str]:
        try:
            if args.reslice:
                return _reslice(s, out_dir)
            return _gen_sheet(s, out_dir)
        except Exception as e:  # noqa: BLE001
            print(f"  FAIL {s}: {e}", file=sys.stderr)
            return _SHEETS[s][0]

    with ThreadPoolExecutor(max_workers=min(5, len(sheets))) as pool:
        for failed_keys in pool.map(_worker, sheets):
            failures.extend(failed_keys)

    if failures:
        print(f"\n{len(failures)} tile(s) failed: {failures}", file=sys.stderr)
        return 1
    print("\ndone: all sheets sliced")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

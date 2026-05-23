"""CLI: generate non-tile assets — backgrounds, run-node icons, HUD icons, logo.

斗牌传说 / Akagi art direction — dramatic high-contrast, hard ink shadows,
gritty 1990s seinen gambling-den mood.

Usage:
  python3 generate_misc.py --table        # battle table felt background
  python3 generate_misc.py --runbg        # run-flow screen background
  python3 generate_misc.py --icons        # 6 run-node icons
  python3 generate_misc.py --hud          # HP / gold HUD icons
  python3 generate_misc.py --logo         # game logo
  python3 generate_misc.py --all          # everything
"""
from __future__ import annotations

import argparse
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import gen_client
import postprocess

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent.parent / "assets"
ICON_DIR = ASSETS / "run_icons"
RAW_DIR = HERE / "_raw_misc"

_AKAGI = (
    "Dramatic high-contrast lighting, hard ink shadows, sharp angular linework, "
    "monochrome-leaning palette with selective deep crimson, gritty 1990s "
    "Akagi seinen-manga gambling-den aesthetic, tense and ominous mood."
)

# (key, prompt, size, background) for the run-node icons — transparent 256x256.
_ICONS: dict[str, str] = {
    "node_normal": "a pair of crossed mahjong tiles emblem",
    "node_elite": "a mahjong tile emblem crowned with a sharp golden laurel",
    "node_camp": "a small campfire emblem with a folding stool",
    "node_shop": "a stack of gambling chips and a coin emblem",
    "node_event": "an ornate question-mark emblem over a fanned pair of dice",
    "node_boss": "a menacing oni demon mask emblem with horns",
}

TABLE_PROMPT = (
    "A top-down view of a traditional Japanese mahjong gambling table surface, "
    "dark green felt with a faint worn texture, a subtle darker border frame, "
    "empty center, no tiles, no text. Heavy vignette darkening the edges. "
    + _AKAGI
    + " Seamless even surface suitable as a full-screen game background."
)

# Run-flow screen background: an atmospheric underground gambling den, kept
# dark and uncluttered so UI panels overlaid on top stay readable.
RUNBG_PROMPT = (
    "A dark, atmospheric underground Japanese gambling den interior, empty, "
    "seen straight on: dim hanging lights, deep shadows, worn wooden walls, "
    "a heavy vignette, mostly very dark with faint warm light, no people, no "
    "furniture in the center, no text. Uncluttered and dim so UI panels can "
    "be overlaid on top. " + _AKAGI
)

# (key, prompt, out_path) for HUD icons — transparent, small.
_HUD_ICONS: dict[str, str] = {
    "icon_hp": "a stylised heart symbol, deep crimson",
    "icon_gold": "a stack of two old gambling coins, tarnished gold",
}

LOGO_PROMPT = (
    "A bold game logo emblem for a mahjong roguelike titled 麻将王 (Mahjong "
    "King): a single dramatic mahjong tile rendered as a throne or crown motif, "
    "isolated on a transparent background, sharp angular design. "
    + _AKAGI
)


def _icon_prompt(desc: str) -> str:
    return (
        f"A game UI icon: {desc}, isolated on a fully transparent background, "
        "centered, filling most of the frame, bold and readable as a small "
        "icon. " + _AKAGI + " No text, no caption, no watermark."
    )


def _gen(key: str, prompt: str, out_path: Path, size: str,
         background: str, target: tuple[int, int] | None) -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    blobs = gen_client.generate(prompt, size=size, background=background)
    raw = blobs[0]
    (RAW_DIR / f"{key}.png").write_bytes(raw)
    if target is not None:
        raw = postprocess.fit_to_box(raw, target, pad_ratio=0.06)
    postprocess.save_png(raw, str(out_path))
    print(f"  ok  {out_path}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", action="store_true")
    ap.add_argument("--runbg", action="store_true")
    ap.add_argument("--icons", action="store_true")
    ap.add_argument("--hud", action="store_true")
    ap.add_argument("--logo", action="store_true")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    do_table = args.table or args.all
    do_runbg = args.runbg or args.all
    do_icons = args.icons or args.all
    do_hud = args.hud or args.all
    do_logo = args.logo or args.all
    if not (do_table or do_runbg or do_icons or do_hud or do_logo):
        ap.error("pick --table / --runbg / --icons / --hud / --logo / --all")
        return 2

    jobs: list = []
    if do_table:
        jobs.append(("table", lambda: _gen(
            "mahjong_table_bg", TABLE_PROMPT, ASSETS / "mahjong_table_bg.png",
            "1536x1024", "opaque", None)))
    if do_runbg:
        jobs.append(("runbg", lambda: _gen(
            "run_bg", RUNBG_PROMPT, ASSETS / "run_bg.png",
            "1536x1024", "opaque", None)))
    if do_logo:
        jobs.append(("logo", lambda: _gen(
            "feifan_logo_transparent", LOGO_PROMPT,
            ASSETS / "feifan_logo_transparent.png", "1024x1024", "transparent",
            (512, 512))))
    if do_icons:
        for key, desc in _ICONS.items():
            jobs.append((key, (lambda k=key, d=desc: _gen(
                k, _icon_prompt(d), ICON_DIR / f"{k}.png", "1024x1024",
                "transparent", postprocess.ICON_SIZE))))
    if do_hud:
        for key, desc in _HUD_ICONS.items():
            jobs.append((key, (lambda k=key, d=desc: _gen(
                k, _icon_prompt(d), ICON_DIR / f"{k}.png", "1024x1024",
                "transparent", (128, 128)))))

    print(f"generating {len(jobs)} misc asset(s)")
    failures: list[str] = []

    def _run(job) -> str | None:
        name, fn = job
        try:
            fn()
            return None
        except Exception as e:  # noqa: BLE001
            print(f"  FAIL {name}: {e}", file=sys.stderr)
            return name

    with ThreadPoolExecutor(max_workers=min(6, len(jobs))) as pool:
        for bad in pool.map(_run, jobs):
            if bad:
                failures.append(bad)

    if failures:
        print(f"\n{len(failures)} failed: {failures}", file=sys.stderr)
        return 1
    print(f"\ndone: {len(jobs)} asset(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

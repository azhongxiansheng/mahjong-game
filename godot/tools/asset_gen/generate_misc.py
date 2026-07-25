"""CLI: generate non-tile assets — table background and logo.

Original dramatic high-contrast art direction — hard ink shadows,
gritty 1990s seinen gambling-den mood (no third-party IP).

Usage:
  python3 generate_misc.py --table        # battle table felt background
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
RAW_DIR = HERE / "_raw_misc"

_DRAMA_STYLE = (
    "Dramatic high-contrast lighting, hard ink shadows, sharp angular linework, "
    "monochrome-leaning palette with selective deep crimson, gritty 1990s "
    "seinen-manga gambling-den aesthetic, tense and ominous mahjong-table mood."
)

TABLE_PROMPT = (
    "A top-down view of a traditional Japanese mahjong gambling table surface, "
    "dark green felt with a faint worn texture, a subtle darker border frame, "
    "empty center, no tiles, no text. Heavy vignette darkening the edges. "
    + _DRAMA_STYLE
    + " Seamless even surface suitable as a full-screen game background."
)

LOGO_PROMPT = (
    "A bold game logo emblem for a competitive mahjong game titled 麻将王 (Mahjong "
    "King): a single dramatic mahjong tile rendered as a throne or crown motif, "
    "isolated on a transparent background, sharp angular design. "
    + _DRAMA_STYLE
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
    # 透明背景资产兜底:gpt-image-2 经常把"transparent"画成灰白棋盘格
    # (RGB 棋盘 + alpha=255),只有四角真透明。flood-fill 抠掉,主体保留。
    if background == "transparent":
        try:
            postprocess.strip_checkerboard(str(out_path))
        except Exception as e:
            print(f"  warn strip_checkerboard failed: {e}")
    print(f"  ok  {out_path}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", action="store_true")
    ap.add_argument("--logo", action="store_true")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    do_table = args.table or args.all
    do_logo = args.logo or args.all
    if not (do_table or do_logo):
        ap.error("pick --table / --logo / --all")
        return 2

    jobs: list = []
    if do_table:
        jobs.append(("table", lambda: _gen(
            "mahjong_table_bg", TABLE_PROMPT, ASSETS / "mahjong_table_bg.png",
            "1536x1024", "opaque", None)))
    if do_logo:
        jobs.append(("logo", lambda: _gen(
            "feifan_logo_transparent", LOGO_PROMPT,
            ASSETS / "feifan_logo_transparent.png", "1024x1024", "transparent",
            (512, 512))))
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

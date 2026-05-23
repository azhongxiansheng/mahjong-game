"""CLI: generate riichi mahjong tile assets with gpt-image-2.

Usage:
  python3 generate_tiles.py --smoke              # 4 sample tiles -> _samples/
  python3 generate_tiles.py --all                # all 38 tiles -> riichi dir
  python3 generate_tiles.py --only 3p,7s,5z      # regenerate specific tiles
  python3 generate_tiles.py --all --out /tmp/x   # custom output dir

Generated images are kept raw alongside the post-processed result so a bad
tile can be re-inspected without another API call.
"""
from __future__ import annotations

import argparse
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import gen_client
import postprocess
import tile_specs

HERE = Path(__file__).resolve().parent
RIICHI_DIR = HERE.parent.parent / "assets" / "mahjong_tiles_riichi"
RAW_DIR = HERE / "_raw"
SAMPLE_DIR = HERE / "_samples"


def _gen_one(key: str, prompt: str, out_dir: Path, raw_dir: Path) -> None:
    raw_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)
    blobs = gen_client.generate(prompt, size="1024x1536", background="transparent")
    raw = blobs[0]
    (raw_dir / f"{key}.png").write_bytes(raw)
    fitted = postprocess.fit_to_box(raw, postprocess.TILE_SIZE, pad_ratio=0.04)
    postprocess.save_png(fitted, str(out_dir / f"{key}.png"))
    print(f"  ok  {key}.png -> {out_dir}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--smoke", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--workers", type=int, default=5)
    args = ap.parse_args()

    specs = tile_specs.all_specs()
    if args.smoke:
        keys = list(tile_specs.SMOKE_KEYS)
        out_dir = SAMPLE_DIR
    elif args.only:
        keys = [k.strip() for k in args.only.split(",") if k.strip()]
        out_dir = Path(args.out) if args.out else RIICHI_DIR
    elif args.all:
        keys = list(specs.keys())
        out_dir = Path(args.out) if args.out else RIICHI_DIR
    else:
        ap.error("pick one of --smoke / --all / --only")
        return 2

    bad = [k for k in keys if k not in specs]
    if bad:
        print(f"unknown tile keys: {bad}", file=sys.stderr)
        return 2

    workers = max(1, min(args.workers, len(keys)))
    print(f"generating {len(keys)} tile(s) -> {out_dir} ({workers} workers)")
    failures: list[str] = []

    def _worker(key: str) -> str | None:
        try:
            _gen_one(key, specs[key], out_dir, RAW_DIR)
            return None
        except Exception as e:  # noqa: BLE001 - report and continue batch
            print(f"  FAIL {key}: {e}", file=sys.stderr)
            return key

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for bad_key in pool.map(_worker, keys):
            if bad_key:
                failures.append(bad_key)

    if failures:
        print(f"\n{len(failures)} failed: {failures}", file=sys.stderr)
        return 1
    print(f"\ndone: {len(keys)} tile(s) generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

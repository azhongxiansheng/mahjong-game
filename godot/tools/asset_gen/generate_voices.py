"""Generate Japanese mahjong announcement voice lines.

Output:
  godot/assets/sfx/voice/<seat>/<line>.mp3   # 4 seats × ~8 lines = 32 mp3s

Each seat gets its own voice (different gender / timbre) so the player can
distinguish who's calling. Filenames match VoiceLine keys used by AudioManager.

Usage:
  python3 godot/tools/asset_gen/generate_voices.py --all
  python3 godot/tools/asset_gen/generate_voices.py --only riichi,tsumo
  python3 godot/tools/asset_gen/generate_voices.py --seats 0,1
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from audio_gen import VOICE_BY_SEAT, synthesize


# Japanese mahjong announcement phrases. Each phrase is short (1-3 mora) so tts
# stays punchy. Speed bumped slightly above 1.0 for crisper announcements.
LINES: dict[str, tuple[str, float]] = {
    "riichi":   ("リーチ!",   1.05),
    "tsumo":    ("ツモ!",     1.10),
    "ron":      ("ロン!",     1.10),
    "chii":     ("チー!",     1.10),
    "pon":      ("ポン!",     1.10),
    "kan":      ("カン!",     1.10),
    "ryukyoku": ("流局です。", 0.95),  # 流局 - slower, somber
    "double_riichi": ("ダブルリーチ!", 1.05),
}

REPO_ROOT = Path(__file__).resolve().parents[3]
OUT_ROOT = REPO_ROOT / "godot" / "assets" / "sfx" / "voice"


def gen_one(seat: int, voice: str, line_key: str, text: str, speed: float) -> str:
    out_dir = OUT_ROOT / f"seat{seat}"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{line_key}.mp3"
    audio = synthesize(text, voice=voice, speed=speed)
    out_path.write_bytes(audio)
    return f"seat{seat}/{line_key}.mp3 ({len(audio)} bytes)"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--only", default="",
                        help="comma-list of line keys, e.g. riichi,tsumo")
    parser.add_argument("--seats", default="0,1,2,3",
                        help="comma-list of seat ids 0..3")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    keys = list(LINES.keys()) if args.all else [k.strip() for k in args.only.split(",") if k.strip()]
    if not keys:
        parser.error("supply --all or --only key,key,...")
    seats = [int(s) for s in args.seats.split(",") if s.strip()]

    tasks: list[tuple[int, str, str, str, float]] = []
    for seat in seats:
        voice = VOICE_BY_SEAT.get(seat, "onyx")
        for k in keys:
            text, speed = LINES[k]
            tasks.append((seat, voice, k, text, speed))

    print(f"generating {len(tasks)} voice clips → {OUT_ROOT}")
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(gen_one, s, v, k, t, sp): (s, k) for s, v, k, t, sp in tasks}
        for f in as_completed(futs):
            s, k = futs[f]
            try:
                print(f"  ✓ {f.result()}")
            except Exception as e:
                print(f"  ✗ seat{s}/{k}: {e}")


if __name__ == "__main__":
    main()

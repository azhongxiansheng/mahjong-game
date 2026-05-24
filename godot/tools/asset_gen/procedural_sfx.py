"""Procedural SFX generator for 麻将王.

Both available OpenAI-compatible gateways currently lack tts-1 / audio-speech
models, so voice / SFX generation via API is blocked. Instead we synthesize a
compact SFX library deterministically with numpy + the stdlib 'wave' module.

All sounds are short (50-1500ms), 22050 Hz, mono, 16-bit PCM. They cover the
core mahjong UX events:

  tile_click       - sharp percussive click when tile is discarded / placed
  tile_draw        - softer slide for drawing from wall
  riichi_stick     - wooden tap when 1000-point stick lands on the table
  button_click     - generic UI button feedback
  win_chime        - 5-note ascending bell for WIN_DECLARED
  yakuman_chime    - longer/grander chime for yakuman tier
  draw_chime       - sad descending tone for EXHAUSTIVE_DRAW
  abortive_chime   - whoosh+thud for ABORTIVE_DRAW (途中流局)
  chi_tap          - chi/pon/kan claim feedback (3 quick taps)
  riichi_chime     - shimmer + rising fifth for RIICHI_DECLARED
  dora_flip        - reveal twinkle for dora indicator flip
  game_begin       - intro chord at hand start

Output: godot/assets/sfx/<name>.wav
"""
from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
OUT_DIR = REPO_ROOT / "godot" / "assets" / "sfx"
SR = 22050  # sample rate


# ---------- waveform primitives ----------

def _sine(freq: float, duration: float, amp: float = 0.5,
          phase: float = 0.0) -> np.ndarray:
    t = np.linspace(0, duration, int(SR * duration), endpoint=False)
    return amp * np.sin(2 * math.pi * freq * t + phase)


def _noise(duration: float, amp: float = 0.5) -> np.ndarray:
    n = int(SR * duration)
    rng = np.random.default_rng(seed=42)
    return amp * (rng.random(n) * 2 - 1)


def _adsr(samples: np.ndarray, attack: float = 0.005, decay: float = 0.05,
          sustain: float = 0.7, release: float = 0.1) -> np.ndarray:
    n = len(samples)
    env = np.ones(n)
    a = max(1, int(SR * attack))
    d = max(1, int(SR * decay))
    r = max(1, int(SR * release))
    if a < n:
        env[:a] = np.linspace(0, 1, a)
    if a + d < n:
        env[a:a + d] = np.linspace(1, sustain, d)
    if n - r > 0:
        env[n - r:] = np.linspace(env[max(0, n - r - 1)], 0, r)
    return samples * env


def _lowpass(samples: np.ndarray, cutoff_hz: float) -> np.ndarray:
    """Simple one-pole RC lowpass, cheap and good enough for SFX."""
    if cutoff_hz <= 0:
        return samples
    rc = 1.0 / (2 * math.pi * cutoff_hz)
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    out = np.empty_like(samples)
    prev = 0.0
    for i, x in enumerate(samples):
        prev = prev + alpha * (x - prev)
        out[i] = prev
    return out


def _mix(*streams: np.ndarray) -> np.ndarray:
    """Sum streams (zero-pad shorter ones) then clip to [-1, 1]."""
    max_len = max(s.size for s in streams)
    out = np.zeros(max_len)
    for s in streams:
        out[:s.size] += s
    return np.clip(out, -1.0, 1.0)


def _concat(*streams: np.ndarray, gap_ms: float = 0.0) -> np.ndarray:
    gap_samples = int(SR * gap_ms / 1000)
    pieces: list[np.ndarray] = []
    for s in streams:
        pieces.append(s)
        if gap_samples > 0:
            pieces.append(np.zeros(gap_samples))
    if pieces and gap_samples > 0:
        pieces.pop()  # don't add trailing gap
    return np.concatenate(pieces)


def _write_wav(name: str, samples: np.ndarray) -> str:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{name}.wav"
    # convert float [-1,1] to int16
    pcm = (samples * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return f"{name}.wav ({len(pcm) / SR * 1000:.0f}ms, {path.stat().st_size}B)"


# ---------- individual SFX recipes ----------

def make_tile_click() -> np.ndarray:
    # 短促击打:高频咔嗒(2 ~ 3kHz noise burst) + 低频木质回响(~150 Hz sine)
    click = _noise(0.04, amp=0.55)
    click = _lowpass(click, 4000)
    click = _adsr(click, attack=0.001, decay=0.01, sustain=0.3, release=0.025)
    thud = _sine(160, 0.08, amp=0.35)
    thud = _adsr(thud, attack=0.002, decay=0.03, sustain=0.2, release=0.05)
    return _mix(click, thud)


def make_tile_draw() -> np.ndarray:
    # 拉滑:中频 noise 经低通滤波 + 短上升
    swoosh = _noise(0.12, amp=0.4)
    swoosh = _lowpass(swoosh, 1800)
    swoosh = _adsr(swoosh, attack=0.04, decay=0.04, sustain=0.5, release=0.04)
    return swoosh


def make_riichi_stick() -> np.ndarray:
    # 木条触桌:200 Hz 低频 + 短噪声触发
    tap = _mix(
        _adsr(_noise(0.03, amp=0.5), attack=0.001, decay=0.015,
              sustain=0.2, release=0.015),
        _adsr(_sine(220, 0.18, amp=0.5), attack=0.001, decay=0.04,
              sustain=0.3, release=0.14),
    )
    return tap


def make_button_click() -> np.ndarray:
    # 干净的 UI 点击:中频带通般的 800 Hz 短爆 + tiny noise
    body = _sine(720, 0.05, amp=0.45)
    body = _adsr(body, attack=0.001, decay=0.012, sustain=0.4, release=0.025)
    noise = _noise(0.018, amp=0.25)
    noise = _adsr(noise, attack=0.001, decay=0.005, sustain=0.1, release=0.012)
    return _mix(body, noise)


def make_win_chime() -> np.ndarray:
    # 上行五音(C major arpeggio):C5 E5 G5 C6 G5
    notes = [523.25, 659.25, 783.99, 1046.5, 783.99]
    pieces: list[np.ndarray] = []
    for f in notes:
        s = _sine(f, 0.18, amp=0.4) + _sine(f * 2, 0.18, amp=0.18)
        s = _adsr(s, attack=0.003, decay=0.04, sustain=0.6, release=0.12)
        pieces.append(s)
    return _concat(*pieces, gap_ms=20)


def make_yakuman_chime() -> np.ndarray:
    # 役満:7 音壮大上行 + 共鸣低音
    notes = [392.0, 523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98]
    pieces: list[np.ndarray] = []
    for f in notes:
        s = _sine(f, 0.22, amp=0.32) + _sine(f * 2, 0.22, amp=0.18) + _sine(f * 3, 0.22, amp=0.08)
        s = _adsr(s, attack=0.005, decay=0.05, sustain=0.65, release=0.16)
        pieces.append(s)
    base = _concat(*pieces, gap_ms=30)
    # 加低音垫
    bass = _sine(130, len(base) / SR, amp=0.18) + _sine(196, len(base) / SR, amp=0.12)
    bass = _adsr(bass, attack=0.05, decay=0.1, sustain=0.7, release=0.3)
    return _mix(base, bass)


def make_draw_chime() -> np.ndarray:
    # 流局:下行三音 G4 E4 C4(somber)
    notes = [392.0, 329.63, 261.63]
    pieces: list[np.ndarray] = []
    for f in notes:
        s = _sine(f, 0.32, amp=0.35) + _sine(f * 2, 0.32, amp=0.12)
        s = _adsr(s, attack=0.015, decay=0.08, sustain=0.55, release=0.22)
        pieces.append(s)
    return _concat(*pieces, gap_ms=40)


def make_abortive_chime() -> np.ndarray:
    # 途中流局:急停感 — 短 whoosh + 重 thud
    swoosh = _noise(0.18, amp=0.4)
    swoosh = _lowpass(swoosh, 1200)
    swoosh = _adsr(swoosh, attack=0.005, decay=0.08, sustain=0.55, release=0.09)
    thud = _sine(95, 0.32, amp=0.45)
    thud = _adsr(thud, attack=0.01, decay=0.08, sustain=0.5, release=0.22)
    return _concat(swoosh, thud, gap_ms=15)


def make_chi_tap() -> np.ndarray:
    # 鸣牌(chi/pon/kan):3 快 tap
    tap = make_tile_click()
    return _concat(tap, tap, tap, gap_ms=60)


def make_riichi_chime() -> np.ndarray:
    # 立直:闪烁 shimmer + 上升五度(C5 G5)
    shimmer = _noise(0.18, amp=0.18)
    shimmer = _lowpass(shimmer, 6000)
    shimmer = _adsr(shimmer, attack=0.02, decay=0.05, sustain=0.5, release=0.1)
    c5 = _sine(523.25, 0.22, amp=0.42) + _sine(1046.5, 0.22, amp=0.18)
    c5 = _adsr(c5, attack=0.005, decay=0.04, sustain=0.65, release=0.14)
    g5 = _sine(783.99, 0.28, amp=0.42) + _sine(1567.98, 0.28, amp=0.18)
    g5 = _adsr(g5, attack=0.005, decay=0.04, sustain=0.65, release=0.2)
    return _mix(shimmer, _concat(c5, g5, gap_ms=10))


def make_dora_flip() -> np.ndarray:
    # 翻 dora 指示牌:短闪烁(高频 sine 衰减 + 噪声尾)
    fl = _sine(2200, 0.06, amp=0.32) + _sine(3300, 0.06, amp=0.18) + _sine(4400, 0.06, amp=0.1)
    fl = _adsr(fl, attack=0.002, decay=0.015, sustain=0.45, release=0.045)
    tail = _noise(0.04, amp=0.15)
    tail = _lowpass(tail, 5000)
    tail = _adsr(tail, attack=0.001, decay=0.005, sustain=0.2, release=0.035)
    return _mix(fl, tail)


def make_game_begin() -> np.ndarray:
    # 开局:C major chord(C E G)200ms 软淡入
    c = _sine(261.63, 0.55, amp=0.25)
    e = _sine(329.63, 0.55, amp=0.2)
    g = _sine(392.0, 0.55, amp=0.2)
    chord = _mix(c, e, g)
    chord = _adsr(chord, attack=0.05, decay=0.1, sustain=0.7, release=0.35)
    return chord


RECIPES: dict[str, callable] = {
    "tile_click": make_tile_click,
    "tile_draw": make_tile_draw,
    "riichi_stick": make_riichi_stick,
    "button_click": make_button_click,
    "win_chime": make_win_chime,
    "yakuman_chime": make_yakuman_chime,
    "draw_chime": make_draw_chime,
    "abortive_chime": make_abortive_chime,
    "chi_tap": make_chi_tap,
    "riichi_chime": make_riichi_chime,
    "dora_flip": make_dora_flip,
    "game_begin": make_game_begin,
}


def main() -> None:
    print(f"Generating {len(RECIPES)} SFX → {OUT_DIR}")
    for name, fn in RECIPES.items():
        samples = fn()
        msg = _write_wav(name, samples)
        print(f"  ✓ {msg}")


if __name__ == "__main__":
    main()

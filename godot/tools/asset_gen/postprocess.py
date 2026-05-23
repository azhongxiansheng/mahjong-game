"""Pillow post-processing: trim transparent margin, fit to a box, slice rows.

gpt-image-2 returns a PNG with the subject(s) floating in transparent space.
For single assets we trim to the opaque bounding box then scale to a target.
For tile SHEETS (a horizontal row of N tiles) we slice into N images: first by
detecting transparent column gaps at a HIGH alpha threshold (so the faint
connecting shadows the model often draws between tiles are treated as gaps),
falling back to even division of the row extent when the gap count is wrong.
"""
from __future__ import annotations

import io
from PIL import Image

# Match the existing mahjong_tiles_riichi assets so no UI layout shifts.
TILE_SIZE = (272, 389)
ICON_SIZE = (256, 256)


def _trim_alpha(img: Image.Image, alpha_thresh: int = 12) -> Image.Image:
    img = img.convert("RGBA")
    alpha = img.getchannel("A")
    mask = alpha.point(lambda a: 255 if a > alpha_thresh else 0)
    bbox = mask.getbbox()
    return img.crop(bbox) if bbox else img


def fit_image_to_box(img: Image.Image, target: tuple[int, int],
                     pad_ratio: float = 0.0, trim_thresh: int = 12) -> bytes:
    """Trim transparent margin, scale to fit `target`, center on transparent."""
    img = _trim_alpha(img, trim_thresh)
    tw, th = target
    inner_w = int(tw * (1.0 - pad_ratio))
    inner_h = int(th * (1.0 - pad_ratio))
    scale = min(inner_w / img.width, inner_h / img.height)
    new_w = max(1, round(img.width * scale))
    new_h = max(1, round(img.height * scale))
    img = img.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", target, (0, 0, 0, 0))
    canvas.paste(img, ((tw - new_w) // 2, (th - new_h) // 2), img)
    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def fit_to_box(png_bytes: bytes, target: tuple[int, int],
               pad_ratio: float = 0.0) -> bytes:
    return fit_image_to_box(Image.open(io.BytesIO(png_bytes)), target, pad_ratio)


def _column_alpha_max(img: Image.Image) -> list[int]:
    """Per-column max alpha (sampled every 2 rows for speed)."""
    w, h = img.size
    px = img.getchannel("A").load()
    out: list[int] = []
    for x in range(w):
        m = 0
        for y in range(0, h, 2):
            v = px[x, y]
            if v > m:
                m = v
                if m == 255:
                    break
        out.append(m)
    return out


def _runs(cols: list[int], thresh: int, min_px: int) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    n = len(cols)
    x = 0
    while x < n:
        if cols[x] > thresh:
            start = x
            while x < n and cols[x] > thresh:
                x += 1
            if x - start >= min_px:
                runs.append((start, x))
        else:
            x += 1
    return runs


def slice_row(png_bytes: bytes, expected: int) -> list[Image.Image]:
    """Slice a horizontal row of tiles by detecting transparent column gaps.

    Returns one trimmed crop per detected tile, left to right. The caller MUST
    check len(result) == expected: a mismatch means the sheet's tiles touched
    (no gap) and the sheet should be regenerated rather than sliced blindly —
    guessing tile boundaries produces garbage crops.
    """
    img = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    w, h = img.size
    cols = _column_alpha_max(img)
    runs = _runs(cols, thresh=60, min_px=max(24, w // (expected * 5)))
    return [_trim_alpha(img.crop((s, 0, e, h)), 90) for s, e in runs]


def save_png(png_bytes: bytes, path: str) -> None:
    with open(path, "wb") as f:
        f.write(png_bytes)

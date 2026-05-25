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
from collections import deque
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


def strip_checkerboard(path: str, gray_lo: int = 200, gray_hi: int = 255,
                       channel_tol: int = 6) -> tuple[int, int]:
    """Flood-fill kill gpt-image-2's fake transparent checkerboard pixels.

    The image generator often "draws" a Photoshop-style gray checkerboard into
    pixels it thinks should be transparent — RGB is checker, but alpha=255.
    Only the corners get true alpha=0. Real Godot rendering then shows the
    fake checkerboard instead of the layer behind.

    Fix: from every existing alpha=0 pixel, BFS into 4-connected neighbors that
    are also checker-colored (R≈G≈B in [gray_lo, gray_hi]) and set their alpha
    to 0. Bounded by the subject's opaque pixels so it never eats into art.

    Returns (pixels_before, pixels_after) — alpha=0 counts before/after.
    Safe no-op if image is fully opaque (no seed) or has no checker pixels.
    """
    try:
        import numpy as np
    except ImportError as e:
        raise RuntimeError("strip_checkerboard needs numpy") from e

    img = Image.open(path).convert("RGBA")
    arr = np.array(img)
    h, w, _ = arr.shape
    r = arr[..., 0].astype(int)
    g = arr[..., 1].astype(int)
    b = arr[..., 2].astype(int)
    alpha = arr[..., 3]
    is_check = ((np.abs(r - g) < channel_tol)
                & (np.abs(g - b) < channel_tol)
                & (r >= gray_lo) & (r <= gray_hi))
    before = int((alpha == 0).sum())
    visited = (alpha == 0).copy()
    q: deque[tuple[int, int]] = deque()
    ys, xs = np.where(alpha == 0)
    for y, x in zip(ys, xs):
        q.append((int(y), int(x)))
    while q:
        y, x = q.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_check[ny, nx]:
                visited[ny, nx] = True
                alpha[ny, nx] = 0
                q.append((ny, nx))
    arr[..., 3] = alpha
    after = int((alpha == 0).sum())
    if after > before:
        Image.fromarray(arr).save(path)
    return before, after

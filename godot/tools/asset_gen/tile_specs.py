"""Tile face specs + prompt builder for the 38 riichi mahjong tile assets.

Style: original dramatic high-contrast mahjong tile art — hard ink shadows,
gritty 1990s seinen gambling-den mood. Tile FACES stay highly legible (aged
ivory ground, crisp black/vermilion engraving); the style shows only in texture
and lighting, never by obscuring the suit/number.
"""
from __future__ import annotations

# Shared opening + closing wrapped around every tile-face description.
_FACE_PREFIX = (
    "A single traditional Japanese riichi mahjong tile, photographed perfectly "
    "straight-on, isolated on a fully transparent background. The tile is an "
    "aged ivory-bone rectangle, standing upright (portrait), with slightly "
    "rounded corners and a subtle 3D bevel on the edges. "
)
_FACE_SUFFIX = (
    " The engraving is crisp, deeply carved and cleanly filled. Strong "
    "directional surface shading across the ivory gives a high-contrast, "
    "gritty seinen-manga gambling-den mood, tense 1990s anime table aesthetic, "
    "slightly worn and aged ivory surface. The tile stands upright, is "
    "centered and fills the entire frame edge to edge. No drop shadow, no "
    "cast shadow outside the tile. No other objects, no background, no "
    "caption, no watermark, no text outside the tile face itself."
)

_MAN_KANJI = {1: "一", 2: "二", 3: "三", 4: "四", 5: "五",
              6: "六", 7: "七", 8: "八", 9: "九"}


def _man(n: int, red: bool = False) -> str:
    ink = ("the upper number drawn in crisp vermilion-red ink"
           if red else "both characters in crisp black ink")
    return (f"The tile face shows the Chinese numeral 「{_MAN_KANJI[n]}」 in the "
            f"upper half and the large character 「萬」 in the lower half, "
            f"{ink}. This is the {n}-man (manzu) tile.")


def _pin(n: int, red: bool = False) -> str:
    layout = {
        1: "one large ornate circular dot centered",
        2: "two circular dots stacked vertically",
        3: "three circular dots on a diagonal line",
        4: "four circular dots in a 2-by-2 square",
        5: "five circular dots: four in the corners and one in the center",
        6: "six circular dots in two columns of three",
        7: "seven circular dots: a slanted row of three on top and a 2-by-2 below",
        8: "eight circular dots in two columns of four",
        9: "nine circular dots in a 3-by-3 grid",
    }[n]
    extra = ""
    if red and n == 5:
        extra = " The single central dot is drawn in vermilion red."
    return (f"The tile face shows exactly {n} flat concentric-ring dot symbols "
            f"({layout}), the pinzu (circles) suit.{extra} Exactly {n} dots, "
            f"no more and no fewer.")


def _sou(n: int, red: bool = False) -> str:
    if n == 1:
        return ("The tile face shows a single ornate stylised bird (a peacock "
                "perched on a bamboo stalk), the 1-sou tile of the souzu "
                "(bamboo) suit.")
    layout = {
        2: "two vertical bamboo sticks side by side",
        3: "three vertical bamboo sticks in a row",
        4: "four vertical bamboo sticks in a row",
        5: "five bamboo sticks: a row of three with two crossed below",
        6: "six vertical bamboo sticks in two rows of three",
        7: "seven bamboo sticks: one on top and two rows of three below",
        8: "eight bamboo sticks in a fanned 'V' arrangement",
        9: "nine vertical bamboo sticks in three rows of three",
    }[n]
    extra = ""
    if red and n == 5:
        extra = " The central bamboo stick is drawn in vermilion red."
    return (f"The tile face shows exactly {n} bright emerald-GREEN "
            f"bamboo-stick symbols ({layout}), the souzu (bamboo) suit. "
            f"The bamboo sticks are vivid green, never brown or wooden.{extra} "
            f"Exactly {n} green sticks.")


def _honor(kind: str) -> str:
    mapping = {
        "1z": ("the large black character 「東」 (East wind) centered", ),
        "2z": ("the large black character 「南」 (South wind) centered", ),
        "3z": ("the large black character 「西」 (West wind) centered", ),
        "4z": ("the large black character 「北」 (North wind) centered", ),
        "5z": ("a clean rectangular blue double-line frame and nothing inside "
               "it (the White Dragon, haku)", ),
        "6z": ("the large character 「發」 carved and filled in deep green "
               "(the Green Dragon, hatsu)", ),
        "7z": ("the large character 「中」 carved and filled in vivid "
               "vermilion red (the Red Dragon, chun)", ),
    }
    return f"The tile face shows {mapping[kind][0]}."


# (asset_key, face description) — 37 faces + back, generated portrait then
# trimmed/resized to 272x389 to match the existing mahjong_tiles_riichi set.
def all_specs() -> dict[str, str]:
    specs: dict[str, str] = {}
    for n in range(1, 10):
        specs[f"{n}m"] = _FACE_PREFIX + _man(n) + _FACE_SUFFIX
        specs[f"{n}p"] = _FACE_PREFIX + _pin(n) + _FACE_SUFFIX
        specs[f"{n}s"] = _FACE_PREFIX + _sou(n) + _FACE_SUFFIX
    for z in range(1, 8):
        specs[f"{z}z"] = _FACE_PREFIX + _honor(f"{z}z") + _FACE_SUFFIX
    specs["0m"] = _FACE_PREFIX + _man(5, red=True) + _FACE_SUFFIX
    specs["0p"] = _FACE_PREFIX + _pin(5, red=True) + _FACE_SUFFIX
    specs["0s"] = _FACE_PREFIX + _sou(5, red=True) + _FACE_SUFFIX
    specs["back"] = (
        "The back of a traditional riichi mahjong tile, isolated on a fully "
        "transparent background, standing upright (portrait), rounded corners "
        "and a subtle 3D bevel. The back is a solid deep jade-green surface "
        "with a faint inset border, no symbols, no characters. Strong "
        "directional surface shading, gritty high-contrast 1990s anime table "
        "aesthetic. The tile stands upright, centered and fills the entire "
        "frame edge to edge. No drop shadow, no cast shadow outside the tile. "
        "No other objects, no caption, no watermark.")
    return specs


SMOKE_KEYS = ["1m", "5p", "9s", "1z"]

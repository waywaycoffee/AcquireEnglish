"""Generate oak / cloth textures for the 3D bookshelf (assets/img/bookshelf/).

Colors are sampled from design/exports/reading_bookshelf/shelf-3d-target.jpg.
Pure Pillow so it runs without numpy:  python gen_bookshelf_textures.py
"""

from __future__ import annotations

import random
from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageOps

OUT = Path(__file__).resolve().parents[2] / "assets" / "img" / "bookshelf"


def _streaks(w: int, h: int, *, along: str, squash: int, sigma: float, seed: int) -> Image.Image:
    random.seed(seed)
    if along == "v":
        small = Image.effect_noise((w, max(2, h // squash)), sigma)
        return small.resize((w, h), Image.BICUBIC)
    small = Image.effect_noise((max(2, w // squash), h), sigma)
    return small.resize((w, h), Image.BICUBIC)


def _grain(w: int, h: int, *, along: str, seed: int) -> Image.Image:
    fine = _streaks(w, h, along=along, squash=60, sigma=60, seed=seed)
    mid = _streaks(w // 3, h // 3, along=along, squash=30, sigma=70, seed=seed + 1).resize((w, h), Image.BICUBIC)
    broad = _streaks(w // 12, h // 12, along=along, squash=12, sigma=80, seed=seed + 2).resize((w, h), Image.BICUBIC)
    mix = ImageChops.blend(ImageChops.blend(fine, mid, 0.45), broad, 0.35)
    mix = ImageOps.autocontrast(mix, cutoff=1)
    blur = (0.6, 0) if along == "v" else (0, 0.6)
    return mix.filter(ImageFilter.GaussianBlur(radius=max(blur) or 0.6))


def oak(w: int, h: int, *, along: str, dark: str, light: str, seed: int, contrast: float) -> Image.Image:
    g = _grain(w, h, along=along, seed=seed)
    g = ImageEnhance.Contrast(g).enhance(contrast)
    return ImageOps.colorize(g, black=dark, white=light, mid=None).convert("RGB")


def cloth(size: int = 256, seed: int = 9) -> Image.Image:
    """Neutral-gray bookcloth weave; used with BlendMode.overlay on covers."""
    random.seed(seed)
    n = Image.effect_noise((size, size), 38).filter(ImageFilter.GaussianBlur(0.5))
    weave = Image.new("L", (size, size), 128)
    px = weave.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = 128 + (10 if (x % 3 == 0) else 0) - (8 if (y % 3 == 0) else 0)
    out = ImageChops.blend(n, weave, 0.55)
    return ImageEnhance.Contrast(out).enhance(0.45)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # Back panel / posts: vertical grain light oak (darkened in-app per shelf).
    oak(512, 1024, along="v", dark="#9A6A3E", light="#C99B6B", seed=1, contrast=1.1).save(
        OUT / "oak_vertical.jpg", quality=88
    )
    # Planks, top rail, base: horizontal grain, slightly lighter.
    oak(1024, 256, along="h", dark="#A67547", light="#D2AC80", seed=4, contrast=1.15).save(
        OUT / "oak_horizontal.jpg", quality=88
    )
    cloth().save(OUT / "bookcloth.png")
    for p in sorted(OUT.iterdir()):
        print(p.name, p.stat().st_size)


if __name__ == "__main__":
    main()

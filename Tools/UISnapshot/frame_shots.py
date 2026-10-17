#!/usr/bin/env python3
"""Put the raw probe captures on a backdrop and save them as README images.

    Tools/UISnapshot/frame_shots.py <raw-dir> <out-dir>

`cacheDisplay` hands back a flat rectangle of pixels. A rectangle of pixels is
not what a window looks like: a real one has rounded corners, a shadow, and
something behind it. This adds those three things, then writes a JPEG.

JPEG rather than PNG because the content is photographic (icons, gradients) and
PNG would be five times the size for no visible gain at README scale.
"""

from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter

# Point sizes, multiplied by the capture's backing scale.
CORNER_RADIUS = 11.0
SHADOW_BLUR = 26.0
SHADOW_OFFSET_Y = 14.0
SHADOW_ALPHA = 0.30
PADDING = 44.0
JPEG_QUALITY = 90

BACKDROP_TOP = (247, 248, 250)
BACKDROP_BOTTOM = (233, 236, 241)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        [0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255
    )
    return mask


def backdrop(size: tuple[int, int]) -> Image.Image:
    """A vertical gradient, so the image does not read as a white slab."""
    gradient = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        gradient.putpixel(
            (0, y),
            tuple(round(BACKDROP_TOP[i] + (BACKDROP_BOTTOM[i] - BACKDROP_TOP[i]) * t)
                  for i in range(3)),
        )
    return gradient.resize(size, Image.BILINEAR)


def frame(raw: pathlib.Path, target: pathlib.Path, scale: float) -> None:
    image = Image.open(raw).convert("RGBA")

    alpha = image.split()[-1]
    transparent = alpha.getextrema()[0] < 250
    if transparent:
        # The capture already knows its own shape (a sheet has a shadow inset,
        # for example). Trust it rather than inventing a rectangle.
        mask = alpha
    else:
        mask = rounded_mask(image.size, round(CORNER_RADIUS * scale))

    box = mask.getbbox()
    if box is None:
        sys.exit("%s is fully transparent" % raw)
    image = image.crop(box)
    mask = mask.crop(box)

    pad = round(PADDING * scale)
    width, height = image.size
    canvas_size = (width + pad * 2, height + pad * 2)

    # Shadow: the same silhouette, blurred, nudged down, drawn at low alpha.
    shadow = Image.new("L", canvas_size, 0)
    shadow.paste(mask, (pad, pad + round(SHADOW_OFFSET_Y * scale)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(round(SHADOW_BLUR * scale)))
    shadow = shadow.point(lambda v: round(v * SHADOW_ALPHA))

    canvas = backdrop(canvas_size).convert("RGBA")
    canvas.paste(Image.new("RGBA", canvas_size, (0, 0, 0, 255)), (0, 0), shadow)
    canvas.paste(image, (pad, pad), mask)

    # A hairline keeps the window edge legible where it meets the backdrop.
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        [pad, pad, pad + width - 1, pad + height - 1],
        radius=round(CORNER_RADIUS * scale),
        outline=(0, 0, 0, 26),
        width=max(1, round(scale)),
    )

    canvas.convert("RGB").save(target, "JPEG", quality=JPEG_QUALITY,
                               subsampling=0, optimize=True)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    raw_dir, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    # Capture width in points, used to recover the backing scale.
    logical_width = {"main": 1040, "editor": 760}

    for state, points in logical_width.items():
        for lang in ("en", "zh"):
            source = raw_dir / f"{state}-{lang}.png"
            if not source.exists():
                sys.exit("missing %s" % source)
            with Image.open(source) as probe:
                scale = probe.width / points
            target = out_dir / f"screenshot-{state}-{lang}.jpg"
            frame(source, target, scale)
            print("%s  %dx%d  %d KB" % (
                target.name,
                *Image.open(target).size,
                target.stat().st_size // 1024,
            ))


if __name__ == "__main__":
    main()

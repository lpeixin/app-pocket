#!/usr/bin/env python3
"""Flatten probe snapshots and build a contact sheet for review."""
import sys
from pathlib import Path
from PIL import Image

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/apppocket-probe/shots-zh-Hans")
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "/tmp/apppocket-probe/contact-sheet.png")

shots = sorted(SRC.glob("*.png"))
print(f"{len(shots)} snapshots in {SRC}")

flat = []
for path in shots:
    img = Image.open(path).convert("RGBA")
    alpha = img.getchannel("A").getextrema()
    rgb = Image.new("RGB", img.size, (255, 255, 255))
    rgb.paste(img, mask=img.getchannel("A"))
    flat.append((path.stem, rgb))
    print(f"  {path.stem:26s} {img.width}x{img.height}  alpha={alpha}")

# Contact sheet: 3 columns, each cell scaled to a fixed width.
COLS = 3
CELL_W = 620
GAP = 14
LABEL_H = 22

cells = []
for name, img in flat:
    scale = CELL_W / img.width
    cells.append((name, img.resize((CELL_W, int(img.height * scale)), Image.LANCZOS)))

rows = (len(cells) + COLS - 1) // COLS
row_heights = []
for r in range(rows):
    band = cells[r * COLS:(r + 1) * COLS]
    row_heights.append(max(c[1].height for c in band) + LABEL_H)

sheet = Image.new(
    "RGB",
    (COLS * CELL_W + (COLS + 1) * GAP, sum(row_heights) + (rows + 1) * GAP),
    (245, 245, 247),
)

from PIL import ImageDraw
draw = ImageDraw.Draw(sheet)

y = GAP
for r in range(rows):
    band = cells[r * COLS:(r + 1) * COLS]
    x = GAP
    for name, img in band:
        draw.text((x + 4, y + 4), name, fill=(30, 30, 30))
        sheet.paste(img, (x, y + LABEL_H))
        x += CELL_W + GAP
    y += row_heights[r] + GAP

sheet.save(OUT)
print(f"wrote {OUT} ({sheet.width}x{sheet.height})")

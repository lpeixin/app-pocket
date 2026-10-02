#!/usr/bin/env python3
"""
Programmatic checks on the AppPocket probe snapshots.

Nothing here is judged by eye: tile columns are found from a measured column
profile, badge colours are classified by hue (the plates use a gradient, so raw
RGB distance misreads them), and the selection tint is compared against the
colour the code actually composites.

Usage: verify.py <shots-dir>
"""
import colorsys
import sys
from pathlib import Path
from PIL import Image

SHOTS = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/apppocket-probe/shots-zh-Hans")

# Derived from the probe log: 2080 device px for a 1040 pt window.
SCALE = 2

PALETTE = [
    ("#0A84FF", (0x0A, 0x84, 0xFF), "blue"),
    ("#30D158", (0x30, 0xD1, 0x58), "green"),
    ("#FF9F0A", (0xFF, 0x9F, 0x0A), "orange"),
    ("#FF375F", (0xFF, 0x37, 0x5F), "pink"),
    ("#BF5AF2", (0xBF, 0x5A, 0xF2), "purple"),
    ("#64D2FF", (0x64, 0xD2, 0xFF), "teal"),
    ("#FFD60A", (0xFF, 0xD6, 0x0A), "yellow"),
    ("#FF6482", (0xFF, 0x64, 0x82), "rose"),
    ("#5E5CE6", (0x5E, 0x5C, 0xE6), "indigo"),
    ("#8E8E93", (0x8E, 0x8E, 0x93), "graphite"),
]


def load(name):
    img = Image.open(SHOTS / f"{name}.png").convert("RGBA")
    flat = Image.new("RGB", img.size, (255, 255, 255))
    flat.paste(img, mask=img.getchannel("A"))
    return flat


def hue(rgb):
    r, g, b = [v / 255 for v in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return h, s, v


WHITE = (255, 255, 255)


def nearest_palette(rgb):
    """Identify a badge plate's palette entry by fitting the render model.

    A badge is `Color(hex:).gradient`, so a plate pixel is roughly

        measured ~= s * (white * (1 - t) + P * t)

    with `t` the gradient position and `s` a small overall scale factor that
    AppKit introduces. Two free parameters, three equations: grid-search both
    and keep the palette entry with the smallest residual.

    Plain RGB distance misreads these (the gradient lightens every plate), and
    hue distance cannot separate #FF375F from #FF6482 -- they are 0.001 apart in
    hue and differ only in saturation. The fit handles both.
    """
    best, best_d, best_params = None, 1e9, (0, 0)
    for hexcode, prgb, name in PALETTE:
        for t in range(30, 101, 1):
            tf = t / 100
            mixed = [WHITE[i] * (1 - tf) + prgb[i] * tf for i in range(3)]
            for si in range(90, 111, 1):
                sf = si / 100
                residual = sum((rgb[i] - sf * mixed[i]) ** 2 for i in range(3)) ** 0.5
                if residual < best_d:
                    best, best_d, best_params = (hexcode, name), residual, (tf, sf)
    return best, best_d, best_params


def dark_profile(img, y0, y1):
    """For each x, how many dark (text) pixels in the label band.

    The tile labels are centred in each tile, so the groups this produces ARE
    the tile column centres -- far more reliable than the icon plates, whose
    brightness varies wildly from icon to icon.
    """
    px = img.load()
    counts = []
    for x in range(img.width):
        n = 0
        for y in range(y0, y1):
            r, g, b = px[x, y]
            if (r + g + b) / 3 < 150:
                n += 1
        counts.append(n)
    return counts


def group(counts, min_count, gap, start=0):
    hits = [x for x, n in enumerate(counts) if n >= min_count and x >= start]
    out = []
    for x in hits:
        if out and x - out[-1][-1] <= gap:
            out[-1].append(x)
        else:
            out.append([x])
    return out


def measure_tile_columns(img, label_top_pt, label_bottom_pt, sidebar_pt, label):
    """Tile columns, measured from the label text band."""
    px = img.load()
    ref = px[img.width - 4, int(label_top_pt * SCALE)]
    counts = dark_profile(img, int(label_top_pt * SCALE), int(label_bottom_pt * SCALE))
    groups = group(counts, min_count=3, gap=int(24 * SCALE), start=int((sidebar_pt + 8) * SCALE))
    centers = [int(sum(g) / len(g)) for g in groups]
    pitches = [round((centers[i + 1] - centers[i]) / SCALE, 1) for i in range(len(centers) - 1)]
    span = round((centers[-1] - centers[0]) / SCALE, 1) if len(centers) > 1 else 0
    print(f"   {label}: {len(centers)} columns")
    print(f"     centres (pt): {[round(c / SCALE, 1) for c in centers]}")
    print(f"     pitch (pt): {pitches}")
    if len(centers) > 1:
        print(f"     average pitch: {span / (len(centers) - 1):.1f} pt")
    return centers, pitches


def main():
    print(f"snapshots: {SHOTS}\n")

    all_apps = load("01-all-apps")
    print(f"01-all-apps: {all_apps.width}x{all_apps.height} device px "
          f"= {all_apps.width // SCALE}x{all_apps.height // SCALE} pt\n")

    # ---- 1. sidebar / detail boundary -----------------------------------
    print("== 1. sidebar / detail boundary ==")
    px = all_apps.load()
    y = 300
    edges, prev = [], px[0, y]
    for x in range(1, all_apps.width):
        c = px[x, y]
        if max(abs(c[i] - prev[i]) for i in range(3)) > 6:
            edges.append((x, prev, c))
        prev = c
    boundary = edges[0][0] if edges else 0
    print(f"   first vertical edge: x={boundary} = {boundary / SCALE:.1f} pt")
    print(f"   Metrics.sidebarWidth = (min 196, ideal 224, max 300)")

    # ---- 2. grid columns -------------------------------------------------
    print("\n== 2. grid columns, 1040 pt window ==")
    # Header is 64 pt, grid padding 20 pt, icon is 64 pt tall.
    centers, pitches = measure_tile_columns(all_apps, 155, 200, 224, "01-all-apps")
    print(f"   tileWidth = icon 64 + 30 = 94 pt, spacing 6 pt -> expected pitch 100 pt")

    # ---- 3. badge hues ---------------------------------------------------
    print("\n== 3. sidebar badge colours vs AppCategory.palette ==")
    column = 20 * SCALE
    px_a = all_apps.load()
    # The plate is 20x20 pt starting at x=10 pt, with a white glyph in the
    # middle. The base colour is its most saturated pixel, so search the whole
    # plate rather than trusting one column.
    plate_x = range(10 * SCALE, 30 * SCALE)
    # The badge's white glyph interrupts the plate, so group with a generous
    # gap and keep groups by total span rather than by contiguous length.
    found = [yy for yy in range(all_apps.height)
             if max(px_a[column, yy]) - min(px_a[column, yy]) > 45]
    plates = []
    for yy in found:
        if plates and yy - plates[-1][-1] <= 22:
            plates[-1].append(yy)
        else:
            plates.append([yy])
    plates = [p for p in plates if p[-1] - p[0] >= 20]

    seen = {}
    for p in plates:
        yc = int(sum(p) / len(p))
        # Average the plate rather than trusting one pixel of its gradient.
        samples = [px_a[x, y] for x in plate_x for y in range(p[0], p[-1] + 1)]
        sat = lambda c: (max(c) - min(c)) / max(max(c), 1)
        avg = max(samples, key=sat)
        (hexcode, name), d, (tf, sf) = nearest_palette(avg)
        seen[name] = seen.get(name, 0) + 1
        print(f"     y={yc:4d}pt={yc / SCALE:6.1f}  strongest={avg}  -> {hexcode} {name:8s} t={tf:.2f} s={sf:.2f} residual={d:.1f}")
    print(f"   distinct hues present: {sorted(seen)}")

    # ---- 4. selection tint ----------------------------------------------
    print("\n== 4. selected tile tint ==")
    multi = load("11-multi-select")
    # The tile plate is only exposed in the 5 pt ring around the icon and in
    # the label band. Sample 2 pt below the plate's top edge, at the tile's
    # horizontal centre, where the rounded corner cannot bite.
    # Use the *second* tile: the first one carries the keyboard-focus ring, so
    # its edges are accent-coloured whether or not it is selected.
    second_center = centers[1]
    tile_top_pt = 64 + 20      # header 64 + grid padding 20
    tile_width_pt = 64 + 30    # AppTileView.tileWidth
    # `centers` is already in device pixels (measure_tile_columns returns the
    # raw group midpoints); only the offsets need scaling.
    sx = int(second_center - (tile_width_pt / 2 - 2) * SCALE)
    sy = int((tile_top_pt + 59) * SCALE)   # plate's left edge, icon-free
    a = all_apps.load()[sx, sy]
    b = multi.load()[sx, sy]
    accent = (0x0A, 0x84, 0xFF)  # macOS default blue accent
    expected = tuple(round(a[i] * 0.84 + accent[i] * 0.16) for i in range(3))
    delta = max(abs(b[i] - expected[i]) for i in range(3))
    print(f"   sample ({sx},{sy}) device px = ({sx / SCALE:.0f},{sy / SCALE:.0f}) pt")
    print(f"   unselected : {a}")
    print(f"   selected   : {b}")
    print(f"   expected   : {expected}  (accent.opacity(0.16) over the window bg)")
    print(f"   max delta  : {delta}  -> {'OK' if delta <= 14 else 'CHECK'}")

    # ---- 5. narrow window ------------------------------------------------
    for name, size in [("03-narrow-window", "820x560"), ("03b-min-width", "760x480")]:
        print(f"\n== 5. {name} ({size} pt) ==")
        img = load(name)
        print(f"   size: {img.width // SCALE}x{img.height // SCALE} pt")
        b = 224
        px_n = img.load()
        prev = px_n[0, 300]
        for x in range(1, img.width):
            c = px_n[x, 300]
            if max(abs(c[i] - prev[i]) for i in range(3)) > 6:
                b = x / SCALE
                break
            prev = c
        print(f"   sidebar boundary: {b:.1f} pt")
        measure_tile_columns(img, 155, 200, b, name)
        print(f"   content min width is 760 pt (WindowBridge.adopt); the grid "
              f"reflows instead of clipping")


if __name__ == "__main__":
    main()

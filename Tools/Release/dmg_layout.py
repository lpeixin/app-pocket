#!/usr/bin/env python3
"""Write the Finder window layout for a disk image into a staging folder.

`make_dmg.sh` stages the app bundle and an `/Applications` symlink in a plain
folder and hands that folder to the image builder. Finder reads `.DS_Store`
from the root of the mounted volume, so putting the table in the staging folder
is enough — every key written here is keyed by *entry name*, not by volume, so
nothing in it goes stale when the folder becomes a read-only image.

Requires `ds_store` (pure Python, no compilation):

    pip install ds_store

Exit codes: 0 wrote the table, 3 `ds_store` is unavailable. The caller treats
3 as "carry on with Finder's default arrangement", not as a failure.
"""

from __future__ import annotations

import argparse
import os
import sys

# A 620x400 window with 128 pt icons is the shape every drag-to-install image
# uses: two large targets side by side, nothing else on screen.
WINDOW_ORIGIN = (200, 160)
WINDOW_SIZE = (620, 400)
ICON_SIZE = 128.0
TEXT_SIZE = 13.0
GRID_SPACING = 100.0

# Left and right of centre. The gap is what the user's eye follows, so it is
# the number to keep when either icon's size changes.
APP_POSITION = (160, 180)
LINK_POSITION = (460, 180)

UNAVAILABLE = 3


def build_window_settings() -> dict:
    return {
        "ShowStatusBar": False,
        "WindowBounds": "{{%d, %d}, {%d, %d}}"
        % (WINDOW_ORIGIN[0], WINDOW_ORIGIN[1], WINDOW_SIZE[0], WINDOW_SIZE[1]),
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 180,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
    }


def build_icon_view_settings() -> dict:
    return {
        "viewOptionsVersion": 1,
        # 0 is the "Default" background, which follows the system appearance.
        # 1 would pin an explicit colour and look wrong in the other mode.
        "backgroundType": 0,
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": GRID_SPACING,
        "arrangeBy": "none",
        "showIconPreview": False,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": TEXT_SIZE,
        "iconSize": ICON_SIZE,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", help="staging folder that will become the image")
    parser.add_argument("--app", default="AppPocket.app", help="name of the .app bundle")
    parser.add_argument("--link", default="Applications", help="name of the symlink")
    args = parser.parse_args()

    try:
        from ds_store import DSStore
    except ImportError:
        print("ds_store not installed — using Finder's default layout", file=sys.stderr)
        return UNAVAILABLE

    missing = [n for n in (args.app, args.link) if not os.path.exists(os.path.join(args.stage, n))]
    if missing:
        print("staging folder is missing: %s" % ", ".join(missing), file=sys.stderr)
        return 1

    table = os.path.join(args.stage, ".DS_Store")
    with DSStore.open(table, "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = build_window_settings()
        store["."]["icvp"] = build_icon_view_settings()
        # b"type" b"icnv" selects icon view, so the positions below are the
        # ones Finder actually draws from.
        store["."]["icvl"] = (b"type", b"icnv")
        store[args.app]["Iloc"] = APP_POSITION
        store[args.link]["Iloc"] = LINK_POSITION

    print("wrote Finder layout to %s" % table)
    return 0


if __name__ == "__main__":
    sys.exit(main())

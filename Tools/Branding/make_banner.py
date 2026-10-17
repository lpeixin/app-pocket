#!/usr/bin/env python3
"""Render the README banners.

    Tools/Branding/make_banner.py [--lang en|zh-Hans] [--out docs/images]

Why a browser and not an image generator: the banners are almost entirely
typography. Diffusion models still mangle letterforms, and a Chinese banner
needs PingFang with the tracking a headline wants. Laying the banner out in
HTML and letting headless Chrome rasterise it at 2x gives correct glyphs,
correct kerning and a crisp result at any size.

The design is deliberately plain: a near-black slab, a faint grid, one warm
glow behind the app icon. No bevels, no lens flares, no gradients on the text.

Output is JPEG rather than PNG. A dark gradient with a soft glow is exactly the
content PNG compresses badly — the same image is ~800 KB as a PNG, 340 KB
quantised to 256 colours (with visible contouring in the icon), and ~170 KB as
a quality-88 JPEG with no artefact you can see at the size GitHub renders it.
"""

from __future__ import annotations

import argparse
import base64
import pathlib
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
ICON = REPO / "AppPocket/AppPocket/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
JPEG_QUALITY = 88

# 1280x320 is 4:1. GitHub's README column is about 880 pt wide, so the banner is
# displayed downscaled and the 2x raster keeps it sharp on a Retina display.
WIDTH, HEIGHT = 1280, 320
SCALE = 2

COPY = {
    "en": {
        "eyebrow": "macOS 26 &nbsp;·&nbsp; Application launcher",
        "title": "AppPocket",
        "subtitle": "Every app on your Mac, sorted the way you think.",
        "chips": ["Local only", "No account", "No network"],
    },
    "zh-Hans": {
        "eyebrow": "macOS 26 &nbsp;·&nbsp; 应用启动器",
        "title": "AppPocket",
        "subtitle": "把 Mac 上的每个应用，按你的想法归类。",
        "chips": ["本地运行", "无需账号", "不联网"],
    },
}

TEMPLATE = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<style>
  * {{ box-sizing: border-box; }}
  html, body {{ margin: 0; padding: 0; }}
  body {{
    width: {width}px; height: {height}px; overflow: hidden;
    background: #0B0F14;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display",
                 "PingFang SC", "Hiragino Sans GB", sans-serif;
    -webkit-font-smoothing: antialiased;
  }}
  .stage {{
    position: relative; width: 100%; height: 100%;
    display: flex; align-items: center; justify-content: center;
    padding: 0 60px;
    background:
      radial-gradient(760px 400px at 34% 52%, rgba(242,145,63,.20), transparent 66%),
      linear-gradient(158deg, #0C1117 0%, #131C26 52%, #0A0E13 100%);
  }}
  /* A 32px grid, vignetted so it never competes with the text. */
  .grid {{
    position: absolute; inset: 0;
    background-image:
      linear-gradient(rgba(255,255,255,.030) 1px, transparent 1px),
      linear-gradient(90deg, rgba(255,255,255,.030) 1px, transparent 1px);
    background-size: 32px 32px;
    -webkit-mask-image: radial-gradient(ellipse 62% 130% at 46% 50%,
      rgba(0,0,0,.85) 0%, rgba(0,0,0,.35) 55%, transparent 78%);
  }}
  .rule {{
    position: absolute; left: 0; right: 0; bottom: 0; height: 1px;
    background: linear-gradient(90deg,
      rgba(242,145,63,.55) 0%, rgba(242,145,63,.08) 40%, transparent 72%);
  }}
  .icon {{
    position: relative; flex: none;
    width: 178px; height: 178px;
    filter: drop-shadow(0 18px 36px rgba(0,0,0,.55));
  }}
  .icon img {{ width: 100%; height: 100%; display: block; }}
  .text {{ position: relative; margin-left: 46px; }}
  .eyebrow {{
    font-size: 13px; font-weight: 600; letter-spacing: 2.2px;
    color: #E9A063; margin-bottom: 13px;
  }}
  .title {{
    font-size: 72px; font-weight: 600; letter-spacing: -1.6px;
    line-height: 1; color: #FFFFFF;
  }}
  .subtitle {{
    margin-top: 15px;
    font-size: 24px; font-weight: 400; letter-spacing: .1px;
    color: #A6B2C0;
  }}
  .chips {{ display: flex; gap: 10px; margin-top: 24px; }}
  .chip {{
    font-size: 14px; font-weight: 500; letter-spacing: .3px;
    color: #C3CDD9;
    padding: 7px 14px; border-radius: 999px;
    border: 1px solid rgba(255,255,255,.13);
    background: rgba(255,255,255,.035);
  }}
</style>
</head>
<body>
  <div class="stage">
    <div class="grid"></div>
    <div class="icon"><img src="data:image/png;base64,{icon}" alt=""></div>
    <div class="text">
      <div class="eyebrow">{eyebrow}</div>
      <div class="title">{title}</div>
      <div class="subtitle">{subtitle}</div>
      <div class="chips">{chips}</div>
    </div>
    <div class="rule"></div>
  </div>
</body>
</html>
"""


def render(lang: str, out_dir: pathlib.Path) -> pathlib.Path:
    copy = COPY[lang]
    icon = base64.b64encode(ICON.read_bytes()).decode("ascii")
    chips = "".join(f'<span class="chip">{c}</span>' for c in copy["chips"])

    html = TEMPLATE.format(
        lang=lang,
        width=WIDTH,
        height=HEIGHT,
        icon=icon,
        eyebrow=copy["eyebrow"],
        title=copy["title"],
        subtitle=copy["subtitle"],
        chips=chips,
    )

    out_dir.mkdir(parents=True, exist_ok=True)
    suffix = "en" if lang == "en" else "zh"
    target = out_dir / f"banner-{suffix}.jpg"

    with tempfile.TemporaryDirectory() as tmp:
        page = pathlib.Path(tmp) / "banner.html"
        page.write_text(html, encoding="utf-8")
        png = pathlib.Path(tmp) / "banner.png"

        subprocess.run(
            [
                CHROME,
                "--headless",
                "--disable-gpu",
                "--hide-scrollbars",
                "--force-device-scale-factor=%d" % SCALE,
                "--window-size=%d,%d" % (WIDTH, HEIGHT),
                "--screenshot=%s" % png,
                page.as_uri(),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        if not png.exists():
            sys.exit("Chrome reported success but %s does not exist" % png)

        # sips ships with macOS, so this needs no Python imaging library.
        subprocess.run(
            ["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(JPEG_QUALITY),
             str(png), "--out", str(target)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    if not target.exists():
        sys.exit("sips reported success but %s does not exist" % target)
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the README banners.")
    parser.add_argument("--lang", choices=sorted(COPY), action="append")
    parser.add_argument(
        "--out", type=pathlib.Path, default=REPO / "docs/images", help="output directory"
    )
    args = parser.parse_args()

    if not pathlib.Path(CHROME).exists():
        sys.exit("Google Chrome is not installed at %s" % CHROME)
    if not ICON.exists():
        sys.exit("app icon not found at %s" % ICON)

    for lang in args.lang or ["en", "zh-Hans"]:
        path = render(lang, args.out)
        try:
            shown = path.relative_to(REPO)
        except ValueError:
            shown = path
        print("%s  %d bytes" % (shown, path.stat().st_size))


if __name__ == "__main__":
    main()

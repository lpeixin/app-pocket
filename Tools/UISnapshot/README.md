# Offscreen UI snapshots

Renders the real SwiftUI views into real `NSWindow`s that are never ordered front,
snapshots them with `NSView.cacheDisplay(in:to:)`, and then **checks the pixels
programmatically** instead of eyeballing thumbnails.

```
./run.sh            # Chinese, the default
./run.sh en         # English
```

Output goes to `docs/ui-snapshots/` (generated; the PNGs and `verify.txt` are
gitignored). The whole run takes a couple of minutes, most of it in `xcodebuild`.

## README images

The two screenshots in `README.md` come from the same probe, in a smaller run:

```
./readme_shots.sh
```

It builds and compiles once, then renders `all` and `editor` in both languages
(`APPPOCKET_UI_PROBE_SEED_LANG` picks the language of the seeded category names,
because the probe cannot read it from `Locale` — see the `-AppleLanguages` note
below). `frame_shots.py` then adds rounded corners, a shadow and a light backdrop,
and writes `docs/images/screenshot-{main,editor}-{en,zh}.jpg`.

Two things differ from `run.sh`, both deliberate:

- **Content only, not the theme frame.** Capturing the window frame also captures
  the empty toolbar well and macOS 26's scroll-edge fade at the top of the content,
  neither of which belongs to the app. The rounded corners in the README image are
  drawn by `frame_shots.py` instead.
- **JPEG, not PNG.** These are photographic (app icons, gradients); PNG is five
  times the size for no visible gain at the width GitHub renders them.

The banners are separate and live in `Tools/Branding/make_banner.py` — they are
typography, so they are laid out in HTML and rasterised by headless Chrome.

## Requirements

- **Xcode command line tools** — the script builds the app, then compiles the probe
  against the app's own sources.
- **A Python with Pillow**, for `verify.py` and `contact_sheet.py`. The system
  `python3` on macOS does not ship Pillow. The script probes, in order,
  `~/.workbuddy-ai/binaries/python/envs/default/bin/python` and then
  `python3` / `python3.13` / `python3.12`, and takes the first one where
  `import PIL` succeeds. Override with:

  ```
  APPPOCKET_PYTHON=/path/to/python ./run.sh
  ```

  It exits with a message rather than a traceback if none qualifies.

Environment overrides: `APPPOCKET_DERIVED_DATA` (default `/tmp/AppPocketDD`),
`APPPOCKET_SNAPSHOT_DIR` (default `/tmp/apppocket-probe`), `APPPOCKET_PYTHON`.

## Why not the obvious approaches

| Attempt | Result |
|---|---|
| `screencapture` | Needs Screen Recording permission; fails without a display. |
| SwiftUI `ImageRenderer` on the whole root | `NavigationSplitView` is AppKit-hosted, so you get a yellow "forbidden" placeholder. |
| `ImageRenderer` on a leaf containing a `ScrollView` | **Renders blank** — the scroll content's height is undetermined. |
| XCUITest | Needs to attach to the window server; does not work in every environment. |

The path that works is in-process. It gives you AppKit's actual laid-out geometry,
needs no permissions, and takes no screen space.

## How the probe reaches each state

`ProbeMain.swift` is compiled against the app's own sources — everything except
`AppPocketApp.swift`, whose `@main` would collide — so it constructs the real
`LibraryStore`, `AppCatalog` and `AppUIState` and drives them the same way the UI does.

- **The store points at a temp directory**, never the real
  `~/Library/Application Support/AppPocket/library.json`. Otherwise every run would
  append to the user's library and no two runs would produce the same image.
- **`LegacyMigrator` is neutralised by pre-seeding categories.** It bails out when the
  store already has categories, which also keeps it from clearing the legacy
  `UserDefaults` key on the user's machine.
- **The hot key is switched off** before the view is built, so the probe does not
  register a system-wide shortcut or fight the user's running copy of the app.
- **The probe never activates the app.** It does not steal focus, and as a
  consequence system controls (the sidebar's selected row, the Settings tab bar)
  render in the inactive-window style. The app's own colour coding — tile selection,
  category badges, the running indicator — does not depend on activation.

The probe touches exactly two things outside its own temp directory: it copies
itself into the built `.app` so `Bundle.main` resolves the localizations, and it
swaps the root `Localizable.strings` in that same build product. Both are undone
by an exit trap, including on Ctrl-C, so an interrupted run cannot leave a probe
binary inside the bundle. Your source tree is never written to.

## What `verify.py` checks

Nothing is judged by eye, and every coordinate is derived from a measurement rather
than estimated:

1. **Sidebar / detail boundary** — first vertical edge on a scanline. 224.0 pt,
   matching `Metrics.sidebarWidth.ideal`.
2. **Grid columns** — measured from the label text band, because the labels are
   centred in each tile, so the groups *are* the column centres. Icon plates are a
   bad signal: their brightness varies from icon to icon.
3. **Category badge colours** — a badge is `Color(hex:).gradient`, so a plate pixel is
   roughly `s · (white·(1−t) + P·t)`. The checker grid-searches `t` and `s` and keeps
   the palette entry with the smallest residual. Plain RGB distance misreads every
   plate (the gradient lightens them), and hue distance cannot separate `#FF375F`
   from `#FF6482` — 0.001 apart in hue, differing only in saturation.
4. **Selected-tile tint** — compared against `accent.opacity(0.16)` composited over
   the window background. Sample the *second* tile: the first carries the
   keyboard-focus ring, so its edges are accent-coloured either way.
5. **Narrow windows** — the same measurements at 820 pt and at the 760 pt minimum.

`contact_sheet.py` flattens every snapshot onto white (a column whose background is
not explicitly drawn comes out of `cacheDisplay` transparent, which reads as black)
and tiles them into one image.

## Gotchas

- **`@main` must be `@MainActor`.** With `-default-isolation MainActor` the compiler
  rejects a `nonisolated static func main()`.
- **`-Xfrontend -disable-sandbox` is required** when building inside a sandbox.
  `swift-frontend` sandboxes the plugin server it spawns for `@State` and friends;
  a nested sandbox fails with `sandbox_apply: Operation not permitted` and every
  `@State` turns into a compile error. The same flag is needed for `xcodebuild`:
  `OTHER_SWIFT_FLAGS="-Xfrontend -disable-sandbox"`.
- **The probe must live inside the .app** (`Contents/MacOS/`) for `Bundle.main` to
  resolve the localizations. A bare binary elsewhere finds no `.lproj` and renders
  raw keys.
- **The empty toolbar is load-bearing.** `render()` attaches an `NSToolbar` even
  for views that put nothing in it. Without one, the window reports a provisional
  84 pt title bar, `setContentSize` bakes that in, and the hosting view ends up
  32 pt taller than requested — SwiftUI then draws the header under the title bar,
  where the scroll-edge effect fades it out and the top of the content is clipped.
  The same applies to the order of calls: lay the window out **before**
  `setContentSize`, or the content size is computed from the provisional chrome.
- **`-AppleLanguages '(zh-Hans)'` does not work.** It lands in `NSArgumentDomain`,
  while `CFBundle` reads the language list from the global preferences domain. The
  result is that `Locale.preferredLanguages` reports `zh-Hans` while the UI stays
  English — very confusing. `run.sh` swaps the root `Localizable.strings` in the
  *built* bundle instead, which affects only the build product.

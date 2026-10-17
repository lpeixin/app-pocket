#!/bin/zsh
#
# Render the two screenshots the README uses, in both languages.
#
#   Tools/UISnapshot/readme_shots.sh
#
# This is a cut-down sibling of run.sh: same build, same probe, but only the two
# states that go into the README, captured with the real window frame so the
# result looks like a window and not like a rectangle of pixels.
#
# Output: docs/images/screenshot-{main,editor}-{en,zh}.jpg
#
set -e

REPO=$(cd "$(dirname "$0")/../.." && pwd)
PROJECT="$REPO/AppPocket"
TOOL="$REPO/Tools/UISnapshot"
DERIVED=${APPPOCKET_DERIVED_DATA:-/tmp/AppPocketDD}
BUILD="$DERIVED/Build/Products/Debug"
APP="$BUILD/AppPocket.app"
WORK=${APPPOCKET_SNAPSHOT_DIR:-/tmp/apppocket-probe}
RAW="$WORK/readme-raw"
OUT="$REPO/docs/images"

mkdir -p "$WORK" "$RAW" "$OUT"

echo "== 1/4  build =="
# OTHER_SWIFT_FLAGS: swift-frontend sandboxes the plugin server it spawns for
# macros such as @State. Inside an already-sandboxed environment that nested
# sandbox fails to apply and every @State becomes
# "swift-plugin-server produced malformed response".
xcodebuild -project "$PROJECT/AppPocket.xcodeproj" -scheme AppPocket \
           -configuration Debug -derivedDataPath "$DERIVED" \
           OTHER_SWIFT_FLAGS="-Xfrontend -disable-sandbox" \
           CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
           build > "$WORK/build.log" 2>&1 || { grep -E "error:" "$WORK/build.log" | head -20; exit 1; }
grep -q "BUILD SUCCEEDED" "$WORK/build.log" && echo "   BUILD SUCCEEDED"

echo "== 2/4  compile the probe =="
{
  find "$PROJECT/AppPocket" -name '*.swift' ! -name 'AppPocketApp.swift' | sort
  echo "$TOOL/ProbeMain.swift"
} > "$WORK/sources.rsp"

xcrun swiftc \
  -swift-version 5 \
  -default-isolation MainActor \
  -enable-upcoming-feature ApproachableConcurrency \
  -enable-upcoming-feature MemberImportVisibility \
  -target arm64-apple-macos14.0 \
  -Onone -g -parse-as-library -Xfrontend -disable-sandbox \
  -o "$WORK/ui-probe" @"$WORK/sources.rsp"
echo "   probe built"

echo "== 3/4  render =="
cp "$WORK/ui-probe" "$APP/Contents/MacOS/ui-probe"
RES="$APP/Contents/Resources"
BACKUP="$WORK/Localizable.root.backup.strings"
[[ -f "$BACKUP" ]] || cp "$RES/Localizable.strings" "$BACKUP"

# Restore the bundle on every exit path, including Ctrl-C.
cleanup() {
    [[ -f "$BACKUP" ]] && cp "$BACKUP" "$RES/Localizable.strings"
    rm -f "$APP/Contents/MacOS/ui-probe"
}
trap cleanup EXIT INT TERM

render() {
    local state=$1 lang=$2 src=$3 dst=$4; shift 4
    env APPPOCKET_UI_PROBE="$state" APPPOCKET_UI_PROBE_OUT="$RAW" \
        "$@" "$APP/Contents/MacOS/ui-probe" 2>&1 \
        | grep -E "wrote|FAILED|unknown state|timed out" || true
    mv "$RAW/$src.png" "$RAW/$dst.png"
}

for lang in en zh-Hans; do
    if [[ "$lang" == "en" ]]; then
        cp "$BACKUP" "$RES/Localizable.strings"
    else
        cp "$RES/$lang.lproj/Localizable.strings" "$RES/Localizable.strings"
    fi
    # "zh-Hans" -> "zh". `${lang%%.*}` would not strip it: there is no dot.
    [[ "$lang" == "en" ]] && suffix=en || suffix=zh
    echo "   $lang"
    # Content only: capturing the theme frame also captures macOS's empty
    # toolbar well and the scroll-edge fade, neither of which is part of the app.
    # frame_shots.py supplies the rounded corners and the shadow instead.
    # SEED_LANG picks the language of the seeded category names: the probe
    # cannot read it from Locale, because switching language here means
    # swapping the bundle's root table, which Locale does not observe.
    render all    "$lang" 01-all-apps          "main-$suffix" \
        APPPOCKET_UI_PROBE_SEED_LANG="$suffix"
    render editor "$lang" 12-category-editor   "editor-$suffix" \
        APPPOCKET_UI_PROBE_SEED_LANG="$suffix"
done

echo "== 4/4  frame =="
PYTHON=${APPPOCKET_PYTHON:-}
if [[ -z "$PYTHON" ]]; then
    for candidate in \
        "$HOME/.workbuddy-ai/binaries/python/envs/default/bin/python" \
        python3 python3.13 python3.12
    do
        command -v "$candidate" >/dev/null 2>&1 || continue
        if "$candidate" -c 'import PIL' >/dev/null 2>&1; then PYTHON=$candidate; break; fi
    done
fi
[[ -n "$PYTHON" ]] || { echo "   no interpreter with Pillow found" >&2; exit 1; }

"$PYTHON" "$TOOL/frame_shots.py" "$RAW" "$OUT"

echo
echo "screenshots: $OUT"

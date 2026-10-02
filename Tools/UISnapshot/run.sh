#!/bin/zsh
#
# Build AppPocket, compile the offscreen UI probe against its sources, render
# every reviewable state, and check the pixels.
#
#   Tools/UISnapshot/run.sh [language]      # language defaults to zh-Hans
#
# The probe is not an Xcode target. It is compiled by hand against the app's
# own sources minus AppPocketApp.swift, whose @main would collide, and is then
# copied into the built .app so that Bundle.main still resolves the
# localizations.
#
set -e

LANGUAGE=${1:-zh-Hans}

REPO=$(cd "$(dirname "$0")/../.." && pwd)
PROJECT="$REPO/AppPocket"
TOOL="$REPO/Tools/UISnapshot"
DERIVED=${APPPOCKET_DERIVED_DATA:-/tmp/AppPocketDD}
BUILD="$DERIVED/Build/Products/Debug"
APP="$BUILD/AppPocket.app"
WORK=${APPPOCKET_SNAPSHOT_DIR:-/tmp/apppocket-probe}
OUT="$REPO/docs/ui-snapshots"

mkdir -p "$WORK" "$OUT"

echo "== 1/5  build =="
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

echo "== 2/5  compile the probe =="
# -Xfrontend -disable-sandbox: swift-frontend sandboxes the plugin server it
# spawns for macros such as @State. Under a nested sandbox that fails with
# "sandbox_apply: Operation not permitted" and every @State becomes an error.
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

echo "== 3/5  render =="
cp "$WORK/ui-probe" "$APP/Contents/MacOS/ui-probe"

RES="$APP/Contents/Resources"
BACKUP="$WORK/Localizable.root.backup.strings"
[[ -f "$BACKUP" ]] || cp "$RES/Localizable.strings" "$BACKUP"

# Both edits are to the build product only, but they are edits to a bundle that
# lives on disk. Restore them on any exit path, including Ctrl-C, so an
# interrupted run cannot leave a probe binary inside the .app.
cleanup() {
    [[ -f "$BACKUP" ]] && cp "$BACKUP" "$RES/Localizable.strings"
    rm -f "$APP/Contents/MacOS/ui-probe"
}
trap cleanup EXIT INT TERM

# The bundle has no en.lproj: English lives in the root Localizable.strings, and
# CFBundle reads AppleLanguages from the global preferences domain, which we are
# not going to touch. So to render another language, swap the root table.
cp "$RES/$LANGUAGE.lproj/Localizable.strings" "$RES/Localizable.strings"

run() {
    local state=$1; shift
    env APPPOCKET_UI_PROBE="$state" APPPOCKET_UI_PROBE_OUT="$OUT" \
        "$@" "$APP/Contents/MacOS/ui-probe" 2>&1 \
        | grep -E "wrote|FAILED|unknown state|timed out" || true
}

run all
run all-dark        APPPOCKET_UI_PROBE_APPEARANCE=dark
run narrow          APPPOCKET_UI_PROBE_WIDTH=820 APPPOCKET_UI_PROBE_HEIGHT=560
run min-width       APPPOCKET_UI_PROBE_WIDTH=760 APPPOCKET_UI_PROBE_HEIGHT=480
run category
run empty-category
run no-results
run uncategorized
run recent
run hidden
run search
run selection
run editor
run editor-new
run picker
run settings        APPPOCKET_UI_PROBE_CHROME=1
run settings-dark   APPPOCKET_UI_PROBE_CHROME=1 APPPOCKET_UI_PROBE_APPEARANCE=dark

echo "== 4/5  pixel checks =="
# The checker needs Pillow, which the system python3 does not ship. Probe the
# known candidates rather than assuming, and honour an explicit override.
if [[ -n "$APPPOCKET_PYTHON" ]]; then
    PYTHON=$APPPOCKET_PYTHON
else
    PYTHON=""
    for candidate in \
        "$HOME/.workbuddy-ai/binaries/python/envs/default/bin/python" \
        python3 python3.13 python3.12
    do
        command -v "$candidate" >/dev/null 2>&1 || continue
        if "$candidate" -c 'import PIL' >/dev/null 2>&1; then PYTHON=$candidate; break; fi
    done
    if [[ -z "$PYTHON" ]]; then
        echo "   no interpreter with Pillow found." >&2
        echo "   install it, or point APPPOCKET_PYTHON at one that has it." >&2
        exit 1
    fi
fi
echo "   python: $PYTHON"
"$PYTHON" "$TOOL/verify.py" "$OUT" | tee "$OUT/verify.txt"

echo "== 5/5  contact sheet =="
"$PYTHON" "$TOOL/contact_sheet.py" "$OUT" "$WORK/contact-sheet.png" | tail -2

echo
echo "snapshots: $OUT"
echo "sheet    : $WORK/contact-sheet.png"

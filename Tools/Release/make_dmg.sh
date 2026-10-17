#!/bin/bash
#
# make_dmg.sh — build AppPocket in Release and package it as a disk image.
#
# The image holds the app bundle and a symlink to /Applications, which is the
# drag-to-install layout macOS users expect. When the `ds_store` Python package
# is importable the icon positions and window size are written as well; without
# it the image still installs fine, it just opens with Finder's default
# arrangement.
#
# Usage:
#     Tools/Release/make_dmg.sh
#
# Output:
#     dist/AppPocket-<version>.dmg
#
# Environment:
#     SIGN_IDENTITY   codesign identity. Default "-" (ad-hoc), which is all an
#                     open-source build with no paid Apple account can do. Pass
#                     a "Developer ID Application: ..." identity to produce an
#                     image that can be notarised and shipped without a
#                     Gatekeeper warning.
#     NOTARY_PROFILE  notarytool keychain profile. When set — and SIGN_IDENTITY
#                     is a Developer ID — the image is submitted to Apple and
#                     the ticket stapled.
#     OUT_DIR         where the .dmg is written. Default "<repo>/dist".
#     DERIVED         derived data path. Default a fresh temp directory.
#     CLEAN=1         delete the Release products before building.
#     SKIP_VERIFY=1   do not mount the finished image to check what is in it.
#     ALLOW_SINGLE_ARCH=1
#                     permit an image that does not contain x86_64. Without it
#                     a non-universal build is an error, because the image would
#                     install on an Intel Mac and then refuse to launch.
#     SWIFT_DISABLE_PLUGIN_SANDBOX=1
#                     add `-Xfrontend -disable-sandbox`. Only needed when the
#                     build itself runs inside a restrictive sandbox, where the
#                     compiler-plugin host cannot start.
#
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROJECT="$REPO_ROOT/AppPocket/AppPocket.xcodeproj"
readonly SCHEME="AppPocket"
readonly APP_NAME="AppPocket"

OUT_DIR="${OUT_DIR:-$REPO_ROOT/dist}"
DERIVED="${DERIVED:-$(mktemp -d "${TMPDIR:-/tmp}/AppPocket-release.XXXXXX")}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

STAGE="$DERIVED/dmg-stage"
MOUNT="$DERIVED/dmg-mount"
MOUNTED=0

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
    if [[ "$MOUNTED" == "1" ]]; then
        diskutil unmount "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# --- 1. Build -------------------------------------------------------------

say "Building $SCHEME (Release)"
[[ "${CLEAN:-0}" == "1" ]] && rm -rf "$DERIVED/Build/Products/Release"

BUILD_SETTINGS=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGN_IDENTITY=""
    CODE_SIGNING_REQUIRED=NO
)
if [[ "${SWIFT_DISABLE_PLUGIN_SANDBOX:-0}" == "1" ]]; then
    BUILD_SETTINGS+=(OTHER_SWIFT_FLAGS="-Xfrontend -disable-sandbox")
fi

if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
        -derivedDataPath "$DERIVED" \
        -destination 'generic/platform=macOS' \
        "${BUILD_SETTINGS[@]}" build \
        > "$DERIVED/build.log" 2>&1; then
    tail -40 "$DERIVED/build.log"
    die "build failed — full log at $DERIVED/build.log"
fi
note "BUILD SUCCEEDED"

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$BUILT_APP" ]] || die "expected a bundle at $BUILT_APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUILT_APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$BUILT_APP/Contents/Info.plist")
note "$APP_NAME $VERSION (build $BUILD)"

# The destination above is not decoration. Without it xcodebuild builds only
# for the machine it is running on, even though ARCHS is "arm64 x86_64" and
# ONLY_ACTIVE_ARCH is NO — verified on Xcode 27, where the same command with
# and without `-destination 'generic/platform=macOS'` produced "arm64" and
# "x86_64 arm64" respectively. An arm64-only image installs happily on an
# Intel Mac and then refuses to launch, so this is a hard failure.
ARCHS=$(lipo -archs "$BUILT_APP/Contents/MacOS/$APP_NAME")
note "architectures: $ARCHS"
if [[ "$ARCHS" != *"x86_64"* && "${ALLOW_SINGLE_ARCH:-0}" != "1" ]]; then
    die "$ARCHS only — an Intel Mac could not run this. Set ALLOW_SINGLE_ARCH=1 to build it anyway."
fi

# --- 2. Sign --------------------------------------------------------------

say "Signing"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Ad-hoc cannot be timestamped: there is no certificate authority to ask.
    codesign --force --options runtime --timestamp=none --sign - "$BUILT_APP"
    note "ad-hoc (no Developer ID certificate in this keychain)"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$BUILT_APP"
    note "$SIGN_IDENTITY"
fi
codesign --verify --strict --verbose=2 "$BUILT_APP" 2>&1 | sed 's/^/    /'

# --- 3. Stage -------------------------------------------------------------

say "Staging"
rm -rf "$STAGE" "$MOUNT"
mkdir -p "$STAGE" "$OUT_DIR"
# ditto, not cp: it carries the extended attributes the signature depends on.
ditto "$BUILT_APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
note "$APP_NAME.app + Applications -> /Applications"

# `command -v x || true` inside an assignment looks like a guard but is not one:
# the assignment takes the status of `true`, so the branch below would be taken
# even with no interpreter at all. Find the interpreter first, then test it.
LAYOUT_PY=""
for candidate in "${APPPOCKET_PYTHON:-}" python3; do
    [[ -n "$candidate" ]] || continue
    if command -v "$candidate" > /dev/null 2>&1; then
        LAYOUT_PY=$(command -v "$candidate")
        break
    fi
done

if [[ -n "$LAYOUT_PY" ]] \
   && "$LAYOUT_PY" "$SCRIPT_DIR/dmg_layout.py" "$STAGE" --app "$APP_NAME.app" 2>&1 \
        | sed 's/^/    /'; then
    :
else
    note "continuing without a custom icon layout"
fi

# --- 4. Build the image ---------------------------------------------------

readonly VOLUME_NAME="$APP_NAME $VERSION"
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

say "Creating $APP_NAME-$VERSION.dmg"
# hdiutil first, and not for its own sake: `diskutil image create from` — the
# spelling macOS 27 recommends — silently drops .DS_Store, which is where the
# window layout above lives. Measured both ways on macOS 27. It stays as the
# fallback for the day hdiutil is finally removed.
if hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE" \
        -fs HFS+ -format UDZO -ov "$DMG" > "$DERIVED/image.log" 2>&1; then
    note "hdiutil (HFS+)"
elif diskutil image create from --format UDZO --volumeName "$VOLUME_NAME" \
        "$STAGE" "$DMG" >> "$DERIVED/image.log" 2>&1; then
    note "diskutil image (APFS) — no .DS_Store, so Finder's default layout"
else
    tail -20 "$DERIVED/image.log"
    die "could not create the disk image"
fi
[[ -f "$DMG" ]] || die "image builder reported success but $DMG does not exist"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    note "signed the image too"
fi

# --- 5. Notarise ----------------------------------------------------------

if [[ -n "$NOTARY_PROFILE" && "$SIGN_IDENTITY" != "-" ]]; then
    say "Notarising (this waits on Apple)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    note "ticket stapled"
elif [[ -n "$NOTARY_PROFILE" ]]; then
    note "NOTARY_PROFILE is set but the identity is ad-hoc — skipping notarisation"
fi

# --- 6. Verify what actually landed in the image --------------------------

if [[ "${SKIP_VERIFY:-0}" != "1" ]]; then
    say "Verifying the image"
    mkdir -p "$MOUNT"
    if hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -readonly > /dev/null 2>&1 \
       || diskutil image attach --mountPoint "$MOUNT" --mountOptions nobrowse --readOnly \
            "$DMG" > /dev/null 2>&1; then
        MOUNTED=1
        ls -A1 "$MOUNT" | sed 's/^/    /'

        MOUNTED_APP="$MOUNT/$APP_NAME.app"
        [[ -d "$MOUNTED_APP" ]] || die "$APP_NAME.app is not in the image"
        [[ -L "$MOUNT/Applications" ]] || die "the Applications symlink is not in the image"

        # Checked explicitly because one of the two image builders drops it
        # without saying so, and the only symptom is an untidy Finder window.
        if [[ -f "$MOUNT/.DS_Store" ]]; then
            note "Finder layout is in the image"
        else
            note "no .DS_Store — the image will open with Finder's default layout"
        fi

        MOUNTED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$MOUNTED_APP/Contents/Info.plist")
        [[ "$MOUNTED_VERSION" == "$VERSION" ]] \
            || die "image contains $MOUNTED_VERSION but the build was $VERSION"
        note "bundled version $MOUNTED_VERSION matches the filename"

        codesign --verify --strict "$MOUNTED_APP" \
            || die "the signature does not survive the round trip"
        note "signature verifies inside the image"

        # A quarantined copy is what a downloader actually gets. Report what
        # Gatekeeper will say about it rather than leaving it to be discovered.
        if spctl --assess --type execute "$MOUNTED_APP" 2>/dev/null; then
            note "Gatekeeper: accepted"
        else
            note "Gatekeeper: rejected (expected for an ad-hoc signature — see README)"
        fi

        cleanup
        MOUNTED=0
    else
        note "could not mount the image to verify it — skipping"
    fi
fi

# --- 7. Report ------------------------------------------------------------

readonly SIZE=$(du -h "$DMG" | cut -f1)
readonly SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

printf '\n'
say "Done"
note "version   $VERSION (build $BUILD)"
note "archs     $ARCHS"
note "image     $DMG"
note "size      $SIZE"
note "sha256    $SHA"

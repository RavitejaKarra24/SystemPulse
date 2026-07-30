#!/usr/bin/env bash
# Builds the app bundle and produces the downloadable zip committed at the repo root.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SystemPulse"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
# The zip lives outside dist/ because dist/ is ignored by git.
ZIP_PATH="$ROOT_DIR/$APP_NAME.zip"

"$ROOT_DIR/scripts/build-app.sh"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# ditto in CPIO-archive mode preserves symlinks and extended attributes, which
# `zip` drops; a bundle archived with `zip` fails to launch on Apple silicon
# because the code signature no longer validates.
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# Verify the artifact users actually download, not just the bundle it came from.
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"

UNPACKED_APP="$VERIFY_DIR/$APP_NAME.app"
test -x "$UNPACKED_APP/Contents/MacOS/$APP_NAME"
test -f "$UNPACKED_APP/Contents/Resources/AppIcon.icns"
plutil -lint "$UNPACKED_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$UNPACKED_APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$UNPACKED_APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$UNPACKED_APP/Contents/Info.plist")"
SIZE="$(du -h "$ZIP_PATH" | cut -f1 | tr -d ' ')"

echo "Packaged $APP_NAME $VERSION (build $BUILD)"
echo "  $ZIP_PATH ($SIZE)"
echo "  signature verified after unpacking"

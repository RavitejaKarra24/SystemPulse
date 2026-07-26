#!/usr/bin/env bash
# Tests the exact distributable artifact rather than only the SwiftPM executable.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/SystemPulse.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

"$ROOT_DIR/scripts/build-app.sh"

test -x "$APP_BUNDLE/Contents/MacOS/SystemPulse"
test -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
plutil -lint "$INFO_PLIST"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" = "local.systempulse.monitor"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST")" = "AppIcon"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "App bundle validation passed."

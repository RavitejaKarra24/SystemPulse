#!/usr/bin/env bash
# Checks the zip that users download: it must exist, unpack, verify, and carry
# the same version as Resources/Info.plist. Git will not tell you the committed
# artifact went stale, so this does.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SystemPulse"
ZIP_PATH="$ROOT_DIR/$APP_NAME.zip"
SOURCE_PLIST="$ROOT_DIR/Resources/Info.plist"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Missing $ZIP_PATH. Regenerate it with: make zip" >&2
  exit 1
fi

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"

UNPACKED_APP="$VERIFY_DIR/$APP_NAME.app"
test -x "$UNPACKED_APP/Contents/MacOS/$APP_NAME"
plutil -lint "$UNPACKED_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$UNPACKED_APP"

read_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1"
}
zipped_version="$(read_version "$UNPACKED_APP/Contents/Info.plist")"
source_version="$(read_version "$SOURCE_PLIST")"

if [[ "$zipped_version" != "$source_version" ]]; then
  echo "Stale download: $APP_NAME.zip is $zipped_version but Resources/Info.plist is $source_version." >&2
  echo "Regenerate it with: make zip" >&2
  exit 1
fi

echo "$APP_NAME.zip is present, valid, and matches version $source_version."

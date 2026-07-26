#!/usr/bin/env bash
# Installs a locally built SystemPulse.app in the current user's Applications folder.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="SystemPulse"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
DESTINATION_DIR="$HOME/Applications"
DESTINATION_APP="$DESTINATION_DIR/$APP_NAME.app"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift is unavailable. Install the Xcode Command Line Tools with: xcode-select --install" >&2
  exit 1
fi

"$ROOT_DIR/scripts/build-app.sh"

mkdir -p "$DESTINATION_DIR"
# Ignore the absence of a running copy; waiting avoids replacing an open bundle.
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1
rm -rf "$DESTINATION_APP"
ditto "$SOURCE_APP" "$DESTINATION_APP"

# This affects only the app that this script just built on the user's own Mac.
xattr -dr com.apple.quarantine "$DESTINATION_APP" 2>/dev/null || true
plutil -lint "$DESTINATION_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$DESTINATION_APP"
open "$DESTINATION_APP"

echo "Installed and opened $DESTINATION_APP"

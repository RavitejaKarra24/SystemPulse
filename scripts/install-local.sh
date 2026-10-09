#!/usr/bin/env bash
# Replaces ~/Applications/SystemPulse.app with the bundle in dist/.
# Every local build uses this so ordinary launches pick up the new binary.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SystemPulse"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
DESTINATION_DIR="$HOME/Applications"
DESTINATION_APP="$DESTINATION_DIR/$APP_NAME.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing $SOURCE_APP. Build it first with scripts/build-app.sh" >&2
  exit 1
fi

was_running=0
if pgrep -xq "$APP_NAME"; then
  was_running=1
  pkill -x "$APP_NAME" 2>/dev/null || true
  for _ in {1..20}; do
    pgrep -xq "$APP_NAME" || break
    sleep 0.1
  done
fi

mkdir -p "$DESTINATION_DIR"
rm -rf "$DESTINATION_APP"
ditto "$SOURCE_APP" "$DESTINATION_APP"

# Scoped to the app this script just copied onto this Mac.
xattr -dr com.apple.quarantine "$DESTINATION_APP" 2>/dev/null || true
plutil -lint "$DESTINATION_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$DESTINATION_APP"

if [[ "$was_running" -eq 1 ]]; then
  open "$DESTINATION_APP"
fi

echo "Installed $DESTINATION_APP"

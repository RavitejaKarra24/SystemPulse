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

# A termination signal bypasses the application's normal-Quit cleanup drain.
# Never interrupt a Trash call or replace the executable of a live process.
set +e
pgrep -x "$APP_NAME" >/dev/null
process_status=$?
set -e
case "$process_status" in
  0)
    echo "Quit SystemPulse normally, wait for any cleanup to finish, then run the installation again. The installed app was not changed." >&2
    exit 1 ;;
  1) ;;
  *)
    echo "Could not verify that SystemPulse is stopped. The installed app was not changed." >&2
    exit 1 ;;
esac

# Reject an incomplete or invalid source before removing a working installation.
if [[ ! -x "$SOURCE_APP/Contents/MacOS/$APP_NAME" || ! -f "$SOURCE_APP/Contents/Resources/AppIcon.icns" ]]; then
  echo "Source bundle is incomplete. The installed app was not changed." >&2
  exit 1
fi
plutil -lint "$SOURCE_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"

mkdir -p "$DESTINATION_DIR"
rm -rf "$DESTINATION_APP"
ditto "$SOURCE_APP" "$DESTINATION_APP"

# Preserve quarantine attributes; installation must not bypass Gatekeeper.
plutil -lint "$DESTINATION_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$DESTINATION_APP"

echo "Installed $DESTINATION_APP"

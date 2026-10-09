#!/usr/bin/env bash
# Read-only validation of the downloadable zip, including full source metadata.
# Optional --compare-app paths must match its entire unpacked bundle payload.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SystemPulse"
ZIP_PATH="$ROOT_DIR/$APP_NAME.zip"
SOURCE_PLIST="$ROOT_DIR/Resources/Info.plist"
VERIFY_ARGS=(--source-plist "$SOURCE_PLIST")
while (($#)); do
  case "$1" in
    --compare-app)
      if (($# < 2)) || [[ -z "$2" ]]; then
        echo 'Missing app bundle path for --compare-app' >&2
        exit 1
      fi
      VERIFY_ARGS+=(--compare-app "$2")
      shift 2 ;;
    --help|-h)
      echo 'Usage: scripts/verify-committed-zip.sh [--compare-app APP_BUNDLE]...'
      echo 'Does not build, install, launch, or modify app bundles.'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

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

python3 "$ROOT_DIR/scripts/verify-artifact-parity.py" \
  --archive-app "$UNPACKED_APP" "${VERIFY_ARGS[@]}"

source_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_PLIST")"
source_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_PLIST")"
architectures="$(lipo -archs "$UNPACKED_APP/Contents/MacOS/$APP_NAME")"
echo "$APP_NAME.zip is valid: $source_version (build $source_build), architecture(s): $architectures."

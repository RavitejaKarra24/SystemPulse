#!/usr/bin/env bash
# Regenerates the macOS icon from the version-controlled SVG source.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Assets/AppIcon.svg"
DESTINATION="$ROOT_DIR/Resources/AppIcon.icns"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SystemPulse.icon.XXXXXX")"
ICONSET="$TEMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$TEMP_DIR"' EXIT

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required to regenerate the icon (brew install librsvg)." >&2
  exit 1
fi

render() {
  local pixels="$1"
  local filename="$2"
  rsvg-convert --width "$pixels" --height "$pixels" "$SOURCE" --output "$ICONSET/$filename"
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

mkdir -p "$(dirname "$DESTINATION")"
iconutil --convert icns --output "$DESTINATION" "$ICONSET"
echo "Generated $DESTINATION"

#!/usr/bin/env bash
# Builds, packages, and ad-hoc signs the source-distributed SystemPulse app.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="SystemPulse"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"
RESOURCES_DIR="$ROOT_DIR/Resources"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift is unavailable. Install the Xcode Command Line Tools with: xcode-select --install" >&2
  exit 1
fi

cd "$ROOT_DIR"
# Prefer swiftbuild when the toolchain advertises it. Older Command Line Tools
# only accept native/xcode; newer standalone toolchains can fail looking for
# xcbuild. Detect instead of pinning one engine.
build_args=(-c release)
if swift build --help 2>/dev/null | grep -q "swiftbuild"; then
  build_args=(--build-system swiftbuild "${build_args[@]}")
fi
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
executable="$bin_dir/$APP_NAME"

if [[ ! -x "$executable" ]]; then
  echo "Expected release executable was not created: $executable" >&2
  exit 1
fi
if [[ ! -f "$INFO_PLIST" || ! -f "$ICON_FILE" ]]; then
  echo "Missing required app resource (Info.plist or AppIcon.icns)." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$executable" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Copy any future top-level app resources without accidentally copying Info.plist.
while IFS= read -r -d '' resource; do
  ditto "$resource" "$APP_BUNDLE/Contents/Resources/$(basename "$resource")"
done < <(find "$RESOURCES_DIR" -mindepth 1 -maxdepth 1 ! -name 'Info.plist' ! -name 'AppIcon.icns' -print0)

# SwiftPM can emit either a standard nested bundle or a flat resource directory.
# Normalize flat bundles so code signing recognizes them as valid macOS bundles.
while IFS= read -r -d '' source_bundle; do
  destination_bundle="$APP_BUNDLE/Contents/Resources/$(basename "$source_bundle")"
  if [[ -f "$source_bundle/Contents/Info.plist" ]]; then
    ditto "$source_bundle" "$destination_bundle"
  else
    mkdir -p "$destination_bundle/Contents/Resources"
    ditto "$source_bundle" "$destination_bundle/Contents/Resources"
    cat > "$destination_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleIdentifier</key><string>local.systempulse.resources.$(basename "$source_bundle" .bundle)</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
  fi
done < <(find "$bin_dir" -maxdepth 1 -type d -name '*.bundle' -print0)

# Nested bundles must be sealed before the outer application bundle.
while IFS= read -r -d '' nested_bundle; do
  codesign --force --sign - --timestamp=none "$nested_bundle"
done < <(find "$APP_BUNDLE/Contents/Resources" -depth -type d -name '*.bundle' -print0)
codesign --force --sign - --timestamp=none "$APP_BUNDLE"

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
test -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "Created and verified $APP_BUNDLE"

# Keep the user-owned install path in sync with this build. Ordinary launches
# should pick up the new binary without a separate install step.
if [[ "${SKIP_LOCAL_INSTALL:-}" != "1" ]]; then
  "$ROOT_DIR/scripts/install-local.sh"
fi

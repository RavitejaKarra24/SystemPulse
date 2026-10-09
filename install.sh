#!/usr/bin/env bash
# One-command source install: build, ad-hoc sign, install to ~/Applications, open.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="SystemPulse"
DESTINATION_APP="$HOME/Applications/$APP_NAME.app"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift is unavailable. Install the Xcode Command Line Tools with: xcode-select --install" >&2
  exit 1
fi

"$ROOT_DIR/scripts/build-app.sh"
open "$DESTINATION_APP"

echo "Installed and opened $DESTINATION_APP"

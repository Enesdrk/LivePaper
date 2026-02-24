#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_saver.sh"

"$PACKAGE_SCRIPT"

SRC="$ROOT_DIR/dist/LivePaper.saver"
DST="$HOME/Library/Screen Savers/LivePaper.saver"

mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$DST"
cp -R "$SRC" "$DST"

xattr -dr com.apple.quarantine "$DST" >/dev/null 2>&1 || true
codesign --verify --deep --strict --verbose=2 "$DST" >/dev/null 2>&1 || true

killall ScreenSaverEngine 2>/dev/null || true
killall "System Settings" 2>/dev/null || true

echo "Installed: $DST"
echo "Open System Settings > Screen Saver and select LivePaper."

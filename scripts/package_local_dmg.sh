#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# First build the local installer package.
"$ROOT_DIR/scripts/package_local_release.sh"

VERSION="$(
  /usr/libexec/PlistBuddy \
    -c "Print:CFBundleShortVersionString" \
    "$ROOT_DIR/SaverBundle/Info.plist" 2>/dev/null || echo "0.1.0"
)"

PKG_PATH="$ROOT_DIR/dist/Livepaper-Local-${VERSION}.pkg"
if [[ ! -f "$PKG_PATH" ]]; then
  echo "Missing package: $PKG_PATH" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d "$ROOT_DIR/.build/livepaper-dmg.XXXXXX")"
cp "$PKG_PATH" "$STAGE_DIR/"
cat > "$STAGE_DIR/Install.txt" <<'TXT'
Livepaper Local Installer

1) Double-click Livepaper-Local-*.pkg
2) Finish installer steps
3) Open Livepaper from Applications
TXT

OUT_DMG="$ROOT_DIR/dist/Livepaper-Local-${VERSION}.dmg"
rm -f "$OUT_DMG"
hdiutil create \
  -volname "Livepaper Installer" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$OUT_DMG" >/dev/null

echo "Created disk image: $OUT_DMG"
echo "Contents:"
echo "  - $(basename "$PKG_PATH")"
echo "  - Install.txt"

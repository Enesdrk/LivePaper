#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release --product LivePaperSaver

BUILD_DIR="$(swift build -c release --show-bin-path)"
SAVER_LIB=""
for candidate in \
  "$BUILD_DIR/libLivePaperSaver.dylib" \
  "$BUILD_DIR/LivePaperSaver"; do
  if [[ -f "$candidate" ]]; then
    SAVER_LIB="$candidate"
    break
  fi
done

if [[ -z "$SAVER_LIB" ]]; then
  echo "Could not find LivePaperSaver binary in $BUILD_DIR" >&2
  exit 1
fi

OUT_DIR="$ROOT_DIR/dist/LivePaper.saver"
LEGACY_OUT_DIR="$ROOT_DIR/dist/LivePaper.saver"
rm -rf "$OUT_DIR"
rm -rf "$LEGACY_OUT_DIR"
mkdir -p "$OUT_DIR/Contents/MacOS" "$OUT_DIR/Contents/Resources"

cp "$ROOT_DIR/SaverBundle/Info.plist" "$OUT_DIR/Contents/Info.plist"
cp "$SAVER_LIB" "$OUT_DIR/Contents/MacOS/LivePaperSaver"
chmod +x "$OUT_DIR/Contents/MacOS/LivePaperSaver"

codesign --force --sign - "$OUT_DIR" >/dev/null 2>&1 || true

echo "Packaged: $OUT_DIR"

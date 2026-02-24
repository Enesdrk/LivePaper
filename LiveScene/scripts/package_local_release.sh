#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Livepaper"
APP_PRODUCT="LiveSceneApp"
WORKER_PRODUCT="LiveSceneWorker"
SAVER_PRODUCT="LiveSceneSaver"
APP_ICON_BASENAME="Livepaper"

# Build each product explicitly to avoid stale binaries in the release bundle.
swift build -c release --product "$APP_PRODUCT"
swift build -c release --product "$WORKER_PRODUCT"
swift build -c release --product "$SAVER_PRODUCT"
BIN_DIR="$(swift build -c release --show-bin-path)"

APP_BIN="$BIN_DIR/$APP_PRODUCT"
WORKER_BIN="$BIN_DIR/$WORKER_PRODUCT"

if [[ ! -x "$APP_BIN" ]]; then
  echo "Missing app binary: $APP_BIN" >&2
  exit 1
fi
if [[ ! -x "$WORKER_BIN" ]]; then
  echo "Missing worker binary: $WORKER_BIN" >&2
  exit 1
fi

VERSION="$(
  /usr/libexec/PlistBuddy \
    -c "Print:CFBundleShortVersionString" \
    "$ROOT_DIR/SaverBundle/Info.plist" 2>/dev/null || echo "0.1.0"
)"
BUILD_VERSION="$(
  /usr/libexec/PlistBuddy \
    -c "Print:CFBundleVersion" \
    "$ROOT_DIR/SaverBundle/Info.plist" 2>/dev/null || echo "1"
)"

STAGE_DIR="$(mktemp -d "$ROOT_DIR/.build/livepaper-release.XXXXXX")"
APP_DIR="$STAGE_DIR/$APP_NAME.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
ICONSET_DIR="$STAGE_DIR/${APP_ICON_BASENAME}.iconset"
ICON_ICNS_PATH="$APP_DIR/Contents/Resources/${APP_ICON_BASENAME}.icns"

mkdir -p "$ICONSET_DIR"

cat > "$STAGE_DIR/generate_icon.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("Usage: generate_icon.swift <size> <output>\n", stderr)
    exit(1)
}

guard let size = Double(args[1]), size > 0 else {
    fputs("Invalid size\n", stderr)
    exit(1)
}

let output = args[2]
let width = Int(size)
let height = Int(size)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
guard let ctx = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("Failed to create CGContext\n", stderr)
    exit(1)
}

ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let iconBounds = CGRect(x: size * 0.10, y: size * 0.10, width: size * 0.80, height: size * 0.80)
let cornerRadius = max(4.0, size * 0.20)
let roundedPath = CGPath(
    roundedRect: iconBounds,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)
ctx.saveGState()
ctx.addPath(roundedPath)
ctx.clip()

let colors = [
    CGColor(red: 0.12, green: 0.56, blue: 0.95, alpha: 1.0),
    CGColor(red: 0.17, green: 0.33, blue: 0.86, alpha: 1.0),
] as CFArray
let locations: [CGFloat] = [0.0, 1.0]
guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
    fputs("Failed to create gradient\n", stderr)
    exit(1)
}
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: iconBounds.minX, y: iconBounds.maxY),
    end: CGPoint(x: iconBounds.maxX, y: iconBounds.minY),
    options: []
)
ctx.restoreGState()

let triW = iconBounds.width * 0.44
let triH = iconBounds.height * 0.52
let cx = iconBounds.midX
let cy = iconBounds.midY
let playPath = CGMutablePath()
playPath.move(to: CGPoint(x: cx - triW * 0.40, y: cy - triH * 0.50))
playPath.addLine(to: CGPoint(x: cx - triW * 0.40, y: cy + triH * 0.50))
playPath.addLine(to: CGPoint(x: cx + triW * 0.60, y: cy))
playPath.closeSubpath()
ctx.addPath(playPath)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath()

ctx.addPath(roundedPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
ctx.setLineWidth(max(1.0, size * 0.04))
ctx.strokePath()

guard let cgImage = ctx.makeImage() else {
    fputs("Failed to make CGImage\n", stderr)
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: output) as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Failed to create PNG destination\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, cgImage, nil)
if !CGImageDestinationFinalize(destination) {
    fputs("Failed to finalize PNG destination\n", stderr)
    exit(1)
}
SWIFT

swift "$STAGE_DIR/generate_icon.swift" 16   "$ICONSET_DIR/icon_16x16.png"
swift "$STAGE_DIR/generate_icon.swift" 32   "$ICONSET_DIR/icon_16x16@2x.png"
swift "$STAGE_DIR/generate_icon.swift" 32   "$ICONSET_DIR/icon_32x32.png"
swift "$STAGE_DIR/generate_icon.swift" 64   "$ICONSET_DIR/icon_32x32@2x.png"
swift "$STAGE_DIR/generate_icon.swift" 128  "$ICONSET_DIR/icon_128x128.png"
swift "$STAGE_DIR/generate_icon.swift" 256  "$ICONSET_DIR/icon_128x128@2x.png"
swift "$STAGE_DIR/generate_icon.swift" 256  "$ICONSET_DIR/icon_256x256.png"
swift "$STAGE_DIR/generate_icon.swift" 512  "$ICONSET_DIR/icon_256x256@2x.png"
swift "$STAGE_DIR/generate_icon.swift" 512  "$ICONSET_DIR/icon_512x512.png"
swift "$STAGE_DIR/generate_icon.swift" 1024 "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS_PATH"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.enes.livepaper</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_BASENAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cp "$APP_BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$WORKER_BIN" "$APP_DIR/Contents/MacOS/$WORKER_PRODUCT"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME" "$APP_DIR/Contents/MacOS/$WORKER_PRODUCT"
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

"$ROOT_DIR/scripts/package_saver.sh"
cp -R "$ROOT_DIR/dist/Livepaper.saver" "$STAGE_DIR/Livepaper.saver"

PKG_ROOT="$(mktemp -d "$ROOT_DIR/.build/livepaper-pkgroot.XXXXXX")"
mkdir -p "$PKG_ROOT/Applications" "$PKG_ROOT/Library/Screen Savers"
cp -R "$APP_DIR" "$PKG_ROOT/Applications/$APP_NAME.app"
cp -R "$STAGE_DIR/Livepaper.saver" "$PKG_ROOT/Library/Screen Savers/Livepaper.saver"

OUT_PKG="$ROOT_DIR/dist/Livepaper-Local-${VERSION}.pkg"
pkgbuild \
  --root "$PKG_ROOT" \
  --identifier "com.enes.livepaper.local" \
  --version "$VERSION" \
  "$OUT_PKG" >/dev/null

echo "Created installer package: $OUT_PKG"
echo "Install:"
echo "  Run: $OUT_PKG"

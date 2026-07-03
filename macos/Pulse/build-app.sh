#!/usr/bin/env bash
# Build Pulse.app from the SwiftPM executable — no Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/3] swift build (release)..."
swift build -c release

APP="Pulse.app"
BIN=".build/release/Pulse"
echo "[2/3] Bundling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Pulse"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Pulse</string>
  <key>CFBundleIdentifier</key><string>com.sinhaankur.pulse</string>
  <key>CFBundleExecutable</key><string>Pulse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

echo "[3/3] Code-signing (ad-hoc)..."
codesign --force --deep -s - "$APP"

echo
echo "Built: $(pwd)/$APP  —  launch with: open $APP"

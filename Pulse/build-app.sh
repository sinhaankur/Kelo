#!/usr/bin/env bash
# Build Kelo.app from the SwiftPM executable — no Xcode project needed.
#   ./build-app.sh            build + sign in place
#   ./build-app.sh --install  also copy to /Applications (Launchpad/Spotlight)
set -euo pipefail
cd "$(dirname "$0")"

# Version comes from KeloInfo.swift — one source of truth.
VERSION=$(sed -n 's/.*version = "\([^"]*\)".*/\1/p' Sources/KeloKit/KeloInfo.swift | head -1)
[[ -n "$VERSION" ]] || { echo "could not read version from KeloInfo.swift"; exit 1; }

echo "[1/4] swift build (release)..."
swift build -c release

# Bundle folder is branded (Kelo.app); the executable is now Kelo too, matching the
# product + target name; CFBundleExecutable matches the binary name.
APP="Kelo.app"
BIN=".build/release/Kelo"
echo "[2/4] Bundling $APP v$VERSION..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kelo"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/worldmap.png "$APP/Contents/Resources/worldmap.png"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Kelo</string>
  <key>CFBundleDisplayName</key><string>Kelo</string>
  <key>CFBundleIdentifier</key><string>com.sinhaankur.kelo</string>
  <key>CFBundleExecutable</key><string>Kelo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Ankur Sinha — private build, never distributed</string>
</dict></plist>
PLIST

echo "[3/4] Code-signing (ad-hoc)..."
codesign --force --deep -s - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "[4/4] Installing to /Applications..."
  rm -rf /Applications/Pulse.app          # remove the old pre-rebrand bundle
  rm -rf "/Applications/$APP"
  ditto "$APP" "/Applications/$APP"        # ditto preserves signing metadata
  echo "Installed: /Applications/$APP"
else
  echo "[4/4] Skipping install (pass --install to copy to /Applications)"
fi

echo
echo "Built: $(pwd)/$APP v$VERSION  —  launch with: open $APP"

#!/usr/bin/env bash
# Pulse — one-command install. Builds from source and (on macOS) puts the app
# in /Applications. Requires Swift 5.9+ (Xcode on macOS, or swift.org on Linux).
set -euo pipefail
cd "$(dirname "$0")"

echo "Pulse installer"
echo "==============="

if ! command -v swift >/dev/null 2>&1; then
  echo "error: Swift not found. Install Xcode (macOS) or Swift from https://swift.org/install/"
  exit 1
fi

OS="$(uname -s)"
if [[ "$OS" == "Darwin" ]]; then
  echo "Building the macOS app…"
  ( cd Pulse && ./build-app.sh --install )
  echo
  echo "Done. Pulse is in /Applications — launch it from Spotlight or Launchpad."
  echo "First launch: right-click Pulse.app > Open (Gatekeeper prompts once for"
  echo "unsigned local builds), then it opens normally."
else
  echo "Building the terminal dashboard (pulse-tui)…"
  ( cd Pulse && swift build -c release )
  echo
  echo "Done. Run it with:"
  echo "  cd Pulse && swift run -c release pulse-tui"
fi

echo
echo "Your data lives in ~/Documents/stock-tracker/ (portfolio.json, config.json)"
echo "and never leaves your machine. See README.md to get started."

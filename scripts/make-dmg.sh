#!/bin/bash
# Build a distributable DMG (Barq-<version>.dmg) from dist/Barq.app.
# Usage: scripts/make-dmg.sh [version]   (defaults to the app's CFBundleShortVersionString)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Barq.app"
[ -d "$APP" ] || { echo "Build the app first: scripts/make-app.sh <version>"; exit 1; }
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")}"

STAGE="dist/dmg-stage"
DMG="dist/Barq-${VERSION}.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▸ Building $DMG…"
hdiutil create -volname "Barq ${VERSION}" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null
rm -rf "$STAGE"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "✓ $DMG"
echo "  size: $(du -h "$DMG" | awk '{print $1}')"
echo "  sha256: $SHA"
echo
echo "Next: create a GitHub release tagged v${VERSION} and upload this DMG as an asset."
echo "Then update the Homebrew cask (packaging/barq-term.rb) version + sha256."

#!/bin/bash
# Build a distributable DMG (Barq-<version>.dmg) from dist/Barq.app.
#
# On a GUI Mac it applies a polished layout (background image + drag-to-
# Applications arrow via Finder AppleScript). On headless/CI it degrades to a
# clean plain image. Usage: scripts/make-dmg.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Barq.app"
[ -d "$APP" ] || { echo "Build the app first: scripts/make-app.sh <version>"; exit 1; }
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")}"

VOL="Barq ${VERSION}"
DMG="dist/Barq-${VERSION}.dmg"
RW="dist/barq-rw.dmg"
MNT="/Volumes/${VOL}"
rm -f "$DMG" "$RW"

# Background (generate if missing).
[ -f dist/dmg-background.png ] || swift scripts/make-dmg-bg.swift || true

echo "▸ Creating writable image…"
hdiutil create -volname "$VOL" -srcfolder "$APP" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
hdiutil detach "$MNT" >/dev/null 2>&1 || true
hdiutil attach "$RW" -mountpoint "$MNT" -nobrowse >/dev/null
ln -s /Applications "$MNT/Applications" 2>/dev/null || true

LAID_OUT="plain"
if [ -f dist/dmg-background.png ]; then
    mkdir -p "$MNT/.background"
    cp dist/dmg-background.png "$MNT/.background/bg.png"
    # Finder layout — needs a GUI session; run guarded so it can't hang CI.
    cat > dist/dmg-layout.applescript <<OSA
tell application "Finder"
    tell disk "${VOL}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 500}
        set vopts to the icon view options of container window
        set arrangement of vopts to not arranged
        set icon size of vopts to 96
        set background picture of vopts to file ".background:bg.png"
        set position of item "Barq.app" of container window to {140, 190}
        set position of item "Applications" of container window to {400, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA
    osascript dist/dmg-layout.applescript >/dev/null 2>&1 &
    OSAPID=$!
    ( sleep 30; kill "$OSAPID" 2>/dev/null ) &
    WATCH=$!
    if wait "$OSAPID" 2>/dev/null; then LAID_OUT="styled"; fi
    kill "$WATCH" 2>/dev/null || true
    rm -f dist/dmg-layout.applescript
fi

sync
hdiutil detach "$MNT" >/dev/null 2>&1 || true
echo "▸ Compressing ($LAID_OUT layout)…"
hdiutil convert "$RW" -format UDZO -ov -o "$DMG" >/dev/null
rm -f "$RW"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "✓ $DMG  ($(du -h "$DMG" | awk '{print $1}'), layout: $LAID_OUT)"
echo "  sha256: $SHA"
echo
echo "Next: gh release + update packaging/barq-term.rb (version + sha256)."

#!/bin/bash
# Build a distributable Barq.app into dist/ (release build, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"

echo "▸ Building release binaries…"
swift build -c release

APP=dist/Barq.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Barq "$APP/Contents/MacOS/Barq"
cp .build/release/barq-mcp "$APP/Contents/MacOS/barq-mcp"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.barq.terminal</string>
    <key>CFBundleName</key><string>Barq</string>
    <key>CFBundleDisplayName</key><string>Barq</string>
    <key>CFBundleExecutable</key><string>Barq</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <!-- Ollama runs on http://127.0.0.1 -->
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP (v${VERSION})"
echo "  Launch:  open $APP"
echo "  MCP server inside the bundle: $APP/Contents/MacOS/barq-mcp"

#!/bin/bash
# Builds Tethera.app and a drag-to-install DMG in dist/.
#
#   scripts/package.sh [version]        e.g. scripts/package.sh 0.3.0
#
# UNIVERSAL=0 builds for this Mac's architecture only (faster).
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
DIST="dist"
APP="$DIST/Tethera.app"
DMG="$DIST/Tethera-macOS.dmg"

echo "==> Building Tethera $VERSION ($BUILD_NUMBER)"
if [ "${UNIVERSAL:-1}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64
    PRODUCTS=".build/apple/Products/Release"
else
    swift build -c release
    PRODUCTS="$(swift build -c release --show-bin-path)"
fi

echo "==> Assembling $APP"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/Tethera" "$APP/Contents/MacOS/Tethera"
# Bundle.tethera looks for the SwiftPM resource bundle in Contents/Resources.
cp -R "$PRODUCTS/Tethera_Tethera.bundle" "$APP/Contents/Resources/"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
cp Tethera/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Tethera</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.tethera.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Tethera</string>
    <key>CFBundleDisplayName</key><string>Tethera</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © $(date +%Y) Tethera contributors.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Creating $DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Tethera $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "==> Done"
ls -lh "$DMG"

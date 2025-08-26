#!/bin/bash

echo "Building Tethera app bundle..."

# Clean previous build
rm -rf Tethera.app

# Build the project
echo "Building project..."
swift build -c release

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Create app bundle structure
    echo "Creating app bundle..."
    mkdir -p Tethera.app/Contents/MacOS
    mkdir -p Tethera.app/Contents/Resources
    
    # Copy executable
    cp .build/release/Tethera Tethera.app/Contents/MacOS/
    
    # Copy resources
    cp -r Terminal/Assets.xcassets Tethera.app/Contents/Resources/
    cp -r Terminal/Fonts Tethera.app/Contents/Resources/
    
    # Create proper macOS icon file
    echo "Creating macOS icon file..."
    mkdir -p Tethera.iconset
    
    # Generate different icon sizes from the source icon
    sips -z 16 16 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_16x16.png
    sips -z 32 32 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_16x16@2x.png
    sips -z 32 32 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_32x32.png
    sips -z 64 64 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_32x32@2x.png
    sips -z 128 128 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_128x128.png
    sips -z 256 256 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_128x128@2x.png
    sips -z 256 256 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_256x256.png
    sips -z 512 512 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_256x256@2x.png
    sips -z 512 512 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_512x512.png
    sips -z 1024 1024 Terminal/Assets.xcassets/AppIcon.appiconset/icon.png --out Tethera.iconset/icon_512x512@2x.png
    
    # Create .icns file
    iconutil -c icns Tethera.iconset -o Tethera.app/Contents/Resources/App.icns
    
    # Clean up temporary files
    rm -rf Tethera.iconset
    
    # Create Info.plist with proper icon reference
    cat > Tethera.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Tethera</string>
	<key>CFBundleIconFile</key>
	<string>App.icns</string>
	<key>CFBundleIdentifier</key>
	<string>com.tethera.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Tethera</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2024. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
	<key>ATSApplicationFontsPath</key>
	<string>Fonts</string>
</dict>
</plist>
EOF
    
    echo "✅ App bundle created successfully!"
    echo "You can now run: open Tethera.app"
    echo "Or double-click the Tethera.app file in Finder"
    
else
    echo "❌ Build failed!"
    exit 1
fi

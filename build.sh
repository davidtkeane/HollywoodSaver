#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/HollywoodSaver.app"

echo "Building HollywoodSaver..."

# Create .app bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"

# Write Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.rangersmyth.hollywoodsaver</string>
    <key>CFBundleName</key>
    <string>HollywoodSaver</string>
    <key>CFBundleExecutable</key>
    <string>HollywoodSaver</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
</dict>
</plist>
PLIST

# Write PkgInfo
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Create app icon from ranger.png if available
mkdir -p "$APP_DIR/Contents/Resources"
if [ -f "$SCRIPT_DIR/ranger.png" ]; then
    ICONSET="$SCRIPT_DIR/HollywoodSaver.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 "$SCRIPT_DIR/ranger.png" --out "$ICONSET/icon_512x512@2x.png" > /dev/null 2>&1
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null && echo "App icon set from ranger.png"
    rm -rf "$ICONSET"
fi

# Compile
swiftc \
    -swift-version 5 \
    -target arm64-apple-macosx15.0 \
    -framework AVFoundation \
    -framework Cocoa \
    -framework QuartzCore \
    -o "$APP_DIR/Contents/MacOS/HollywoodSaver" \
    "$SCRIPT_DIR/HollywoodSaver.swift"

echo ""
echo "Build successful!"
echo "App: $APP_DIR"
echo ""
echo "To run:  open $APP_DIR"
echo "A play icon will appear in your menu bar."

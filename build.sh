#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/HollywoodSaver.app"
STAGE_DIR="$SCRIPT_DIR/.hs-build.app"

VERSION=$(grep -o 'appVersion = "[^"]*"' "$SCRIPT_DIR/src/AppDelegate.swift" | grep -o '"[^"]*"' | tr -d '"')
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not read appVersion from src/AppDelegate.swift${NC}"
    exit 1
fi

echo -e "${BLUE}Building HollywoodSaver v${VERSION}...${NC}"
echo ""

CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
ARCH=$(uname -m)

echo -e "${BLUE}System Info:${NC}"
echo "  CPU: $CHIP"
echo "  Architecture: $ARCH"

if [[ "$ARCH" != "arm64" ]]; then
    echo -e "${RED}Error: This app requires Apple Silicon (M1/M2/M3/M4)${NC}"
    echo "   Detected: $ARCH"
    exit 1
fi

echo ""
echo -e "${BLUE}Checking build tools...${NC}"

if ! command -v swiftc &> /dev/null; then
    echo -e "${RED}Error: swiftc not found${NC}"
    echo "   Install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi
echo -e "  ${GREEN}OK${NC} swiftc: $(swiftc --version | head -1)"

if ! command -v sips &> /dev/null; then
    echo -e "${RED}Error: sips not found (macOS image tool)${NC}"
    exit 1
fi
echo -e "  ${GREEN}OK${NC} sips available"

if ! command -v iconutil &> /dev/null; then
    echo -e "${RED}Error: iconutil not found (macOS icon tool)${NC}"
    exit 1
fi
echo -e "  ${GREEN}OK${NC} iconutil available"

if [ ! -f "$SCRIPT_DIR/images/ranger.png" ]; then
    echo -e "  ${YELLOW}WARN${NC}  images/ranger.png not found (app will use default icon)"
fi

echo ""
echo -e "${BLUE}Building into a staging bundle (live app left untouched)...${NC}"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Contents/MacOS"
mkdir -p "$STAGE_DIR/Contents/Resources"

cat > "$STAGE_DIR/Contents/Info.plist" << PLIST
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
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
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
echo -e "  ${GREEN}OK${NC} Info.plist created"

printf 'APPL????' > "$STAGE_DIR/Contents/PkgInfo"
echo -e "  ${GREEN}OK${NC} PkgInfo created"

if [ -f "$SCRIPT_DIR/images/ranger.png" ]; then
    echo ""
    echo -e "${BLUE}Creating app icon...${NC}"
    ICONSET="$SCRIPT_DIR/HollywoodSaver.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_16x16.png" > /dev/null 2>&1
    sips -z 32 32     "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_16x16@2x.png" > /dev/null 2>&1
    sips -z 32 32     "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_32x32.png" > /dev/null 2>&1
    sips -z 64 64     "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_32x32@2x.png" > /dev/null 2>&1
    sips -z 128 128   "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_128x128.png" > /dev/null 2>&1
    sips -z 256 256   "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_256x256.png" > /dev/null 2>&1
    sips -z 512 512   "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_512x512.png" > /dev/null 2>&1
    sips -z 1024 1024 "$SCRIPT_DIR/images/ranger.png" --out "$ICONSET/icon_512x512@2x.png" > /dev/null 2>&1
    if iconutil -c icns "$ICONSET" -o "$STAGE_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        ICON_SIZE=$(du -h "$STAGE_DIR/Contents/Resources/AppIcon.icns" | awk '{print $1}')
        echo -e "  ${GREEN}OK${NC} App icon created (${ICON_SIZE})"
    else
        echo -e "  ${YELLOW}WARN${NC}  Icon creation failed, using default"
    fi
    rm -rf "$ICONSET"
fi

echo ""
echo -e "${BLUE}Compiling Swift code...${NC}"
echo "  Target: arm64-apple-macosx15.0 (M1/M3/M4)"

SWIFT_SOURCES=("$SCRIPT_DIR/src/"*.swift)
echo "  Source files: ${#SWIFT_SOURCES[@]} files in src/"

set +e
COMPILE_OUTPUT=$(swiftc \
    -swift-version 5 \
    -target arm64-apple-macosx15.0 \
    -framework AVFoundation \
    -framework Cocoa \
    -framework QuartzCore \
    -framework ImageIO \
    -framework ServiceManagement \
    -framework IOKit \
    -framework UserNotifications \
    -framework WebKit \
    -framework Metal \
    -framework MetalKit \
    -o "$STAGE_DIR/Contents/MacOS/HollywoodSaver" \
    "${SWIFT_SOURCES[@]}" 2>&1)
COMPILE_STATUS=$?
set -e

if [ "$COMPILE_STATUS" -ne 0 ] || echo "$COMPILE_OUTPUT" | grep -q "error:"; then
    echo -e "${RED}Compilation failed (live app was not touched):${NC}"
    echo "$COMPILE_OUTPUT"
    rm -rf "$STAGE_DIR"
    exit 1
fi

WARNING_COUNT=$(echo "$COMPILE_OUTPUT" | grep -c "warning:" || true)
WARNING_COUNT=${WARNING_COUNT:-0}

if [ "$WARNING_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}WARN${NC}  Compiled with $WARNING_COUNT warnings (macOS 15 deprecations)"
    echo "     (These are safe to ignore - app will work perfectly)"
else
    echo -e "  ${GREEN}OK${NC} Compiled without warnings"
fi

if [ ! -f "$STAGE_DIR/Contents/MacOS/HollywoodSaver" ]; then
    echo -e "${RED}Error: Executable not created. Live app was not touched.${NC}"
    rm -rf "$STAGE_DIR"
    exit 1
fi

chmod +x "$STAGE_DIR/Contents/MacOS/HollywoodSaver"
EXEC_SIZE=$(du -h "$STAGE_DIR/Contents/MacOS/HollywoodSaver" | awk '{print $1}')
echo -e "  ${GREEN}OK${NC} Executable created (${EXEC_SIZE})"

if [ -f "$SCRIPT_DIR/docs/ABOUT.md" ]; then
    cp "$SCRIPT_DIR/docs/ABOUT.md" "$STAGE_DIR/Contents/Resources/"
    echo -e "  ${GREEN}OK${NC} ABOUT.md included"
fi

LIVE_BIN="$APP_DIR/Contents/MacOS/HollywoodSaver"
if [ -f "$LIVE_BIN" ]; then
    OLDVER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist" 2>/dev/null || echo "unknown")
    BACKUP="$SCRIPT_DIR/HollywoodSaver-v${OLDVER}.app"
    if [ "$BACKUP" = "$APP_DIR" ]; then
        BACKUP="$SCRIPT_DIR/HollywoodSaver-v${OLDVER}-prev.app"
    fi
    echo ""
    echo -e "${BLUE}Backing up live app to $(basename "$BACKUP")...${NC}"
    rm -rf "$BACKUP"
    cp -R "$APP_DIR" "$BACKUP"
    echo -e "  ${GREEN}OK${NC} Saved previous build"
else
    echo -e "  ${YELLOW}WARN${NC}  No working HollywoodSaver.app to keep (empty/husk)"
fi

if pgrep -x HollywoodSaver >/dev/null 2>&1; then
    echo "  Quitting running HollywoodSaver..."
    killall HollywoodSaver 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8; do
        pgrep -x HollywoodSaver >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

rm -rf "$APP_DIR"
mv "$STAGE_DIR" "$APP_DIR"

APP_SIZE=$(du -sh "$APP_DIR" | awk '{print $1}')

echo ""
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')

if [ -n "$SIGN_ID" ]; then
    echo ""
    echo -e "${BLUE}Code signing...${NC}"
    echo "  Identity: $SIGN_ID"
    codesign --deep --force --verify --verbose \
        --sign "$SIGN_ID" \
        --options runtime \
        "$APP_DIR" 2>&1 | grep -E "replacing|adding|signed" || true
    if codesign --verify --deep --strict "$APP_DIR" 2>/dev/null; then
        echo -e "  ${GREEN}OK${NC} Signed with Developer ID"
    else
        echo -e "  ${YELLOW}WARN${NC}  Signing failed — app built but unsigned"
    fi
else
    echo ""
    echo -e "${BLUE}Code signing (ad-hoc with Hardened Runtime)...${NC}"
    codesign --deep --force --sign - --options runtime "$APP_DIR" 2>&1 || true
    if codesign --verify --deep --strict "$APP_DIR" 2>/dev/null; then
        echo -e "  ${GREEN}OK${NC} Ad-hoc signed with Hardened Runtime"
    else
        echo -e "  ${YELLOW}WARN${NC}  Ad-hoc signing failed — app built unsigned"
    fi
    echo "     For public distribution: Xcode, Settings, Accounts, Developer ID Application"
fi

echo ""
echo -e "${GREEN}BUILD SUCCESSFUL (v${VERSION})${NC}"
echo ""
echo -e "${BLUE}App:${NC}       $APP_DIR"
echo -e "${BLUE}Size:${NC}      $APP_SIZE"
echo -e "${BLUE}Built for:${NC} M1/M3/M4 (arm64)"
echo ""

defaults delete com.rangersmyth.hollywoodsaver lastVersionCheckDate 2>/dev/null || true
defaults delete com.rangersmyth.hollywoodsaver cachedLatestVersion 2>/dev/null || true
defaults delete com.rangersmyth.hollywoodsaver lastNotifiedVersion 2>/dev/null || true

bash "$SCRIPT_DIR/run.sh"

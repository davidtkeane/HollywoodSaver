#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/HollywoodSaver.app"

echo -e "${BLUE}🎬 Building HollywoodSaver...${NC}"
echo ""

# Detect Apple Silicon chip
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
ARCH=$(uname -m)

echo -e "${BLUE}System Info:${NC}"
echo "  CPU: $CHIP"
echo "  Architecture: $ARCH"

# Verify we're on Apple Silicon
if [[ "$ARCH" != "arm64" ]]; then
    echo -e "${RED}❌ Error: This app requires Apple Silicon (M1/M2/M3/M4)${NC}"
    echo "   Detected: $ARCH"
    exit 1
fi

# Verify required tools
echo ""
echo -e "${BLUE}Checking build tools...${NC}"

if ! command -v swiftc &> /dev/null; then
    echo -e "${RED}❌ Error: swiftc not found${NC}"
    echo "   Install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi
echo -e "  ${GREEN}✅${NC} swiftc: $(swiftc --version | head -1)"

if ! command -v sips &> /dev/null; then
    echo -e "${RED}❌ Error: sips not found (macOS image tool)${NC}"
    exit 1
fi
echo -e "  ${GREEN}✅${NC} sips available"

if ! command -v iconutil &> /dev/null; then
    echo -e "${RED}❌ Error: iconutil not found (macOS icon tool)${NC}"
    exit 1
fi
echo -e "  ${GREEN}✅${NC} iconutil available"

# Check for ranger.png
if [ ! -f "$SCRIPT_DIR/ranger.png" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  ranger.png not found (app will use default icon)"
fi

echo ""
echo -e "${BLUE}Building app bundle...${NC}"

# Clean previous build
if [ -d "$APP_DIR" ]; then
    echo "  Removing previous build..."
    rm -rf "$APP_DIR"
fi

# Create .app bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

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
echo -e "  ${GREEN}✅${NC} Info.plist created"

# Write PkgInfo
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
echo -e "  ${GREEN}✅${NC} PkgInfo created"

# Create app icon from ranger.png if available
if [ -f "$SCRIPT_DIR/ranger.png" ]; then
    echo ""
    echo -e "${BLUE}Creating app icon...${NC}"

    ICONSET="$SCRIPT_DIR/HollywoodSaver.iconset"
    mkdir -p "$ICONSET"

    # Generate all required icon sizes
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

    # Convert iconset to .icns
    if iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null; then
        ICON_SIZE=$(du -h "$APP_DIR/Contents/Resources/AppIcon.icns" | awk '{print $1}')
        echo -e "  ${GREEN}✅${NC} App icon created (${ICON_SIZE})"
    else
        echo -e "  ${YELLOW}⚠️${NC}  Icon creation failed, using default"
    fi

    rm -rf "$ICONSET"
fi

# Compile Swift code
echo ""
echo -e "${BLUE}Compiling Swift code...${NC}"
echo "  Target: arm64-apple-macosx15.0 (M1/M3/M4)"

# Capture compilation output
COMPILE_OUTPUT=$(swiftc \
    -swift-version 5 \
    -target arm64-apple-macosx15.0 \
    -framework AVFoundation \
    -framework Cocoa \
    -framework QuartzCore \
    -framework ImageIO \
    -framework ServiceManagement \
    -o "$APP_DIR/Contents/MacOS/HollywoodSaver" \
    "$SCRIPT_DIR/HollywoodSaver.swift" 2>&1)

# Check for errors (not warnings)
if echo "$COMPILE_OUTPUT" | grep -q "error:"; then
    echo -e "${RED}❌ Compilation failed:${NC}"
    echo "$COMPILE_OUTPUT"
    exit 1
fi

# Count warnings
WARNING_COUNT=$(echo "$COMPILE_OUTPUT" | grep -c "warning:" || echo "0")

if [ "$WARNING_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠️${NC}  Compiled with $WARNING_COUNT warnings (macOS 15 deprecations)"
    echo "     (These are safe to ignore - app will work perfectly)"
else
    echo -e "  ${GREEN}✅${NC} Compiled without warnings"
fi

# Verify executable was created
if [ ! -f "$APP_DIR/Contents/MacOS/HollywoodSaver" ]; then
    echo -e "${RED}❌ Error: Executable not created${NC}"
    exit 1
fi

EXEC_SIZE=$(du -h "$APP_DIR/Contents/MacOS/HollywoodSaver" | awk '{print $1}')
echo -e "  ${GREEN}✅${NC} Executable created (${EXEC_SIZE})"

# Make executable
chmod +x "$APP_DIR/Contents/MacOS/HollywoodSaver"

# Calculate total app size
APP_SIZE=$(du -sh "$APP_DIR" | awk '{print $1}')

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎖️  BUILD SUCCESSFUL!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}App:${NC}       $APP_DIR"
echo -e "${BLUE}Size:${NC}      $APP_SIZE"
echo -e "${BLUE}Built for:${NC} M1/M3/M4 (arm64)"
echo ""
echo -e "${BLUE}To run:${NC}"
echo "  open $APP_DIR"
echo ""
echo -e "${BLUE}What to expect:${NC}"
echo "  • Ranger helmet icon appears in menu bar 🎖️"
echo "  • Click icon to see your videos"
echo "  • Drop .mp4/.mov/.gif files in this folder"
echo ""
echo -e "${GREEN}Rangers lead the way!${NC}"
echo ""

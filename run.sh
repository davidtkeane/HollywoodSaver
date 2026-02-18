#!/bin/bash

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/HollywoodSaver.app"

# Check if app exists
if [ ! -d "$APP_DIR" ]; then
    echo -e "${YELLOW}HollywoodSaver.app not found. Run 'bash build.sh' first.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎬  Launching HollywoodSaver...${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}This is a menu bar app — no window will open.${NC}"
echo ""
echo -e "${YELLOW}Where to find the icon:${NC}"
echo "  Look in the menu bar (top-right of your screen)"
echo "  next to Wi-Fi, battery, Spotlight, etc."
echo ""
echo "  🎖️  Look for the Ranger helmet icon or ▶️ play icon"
echo ""
echo -e "${YELLOW}Mac-specific notes:${NC}"
echo "  • M1 Macs: Icon appears on built-in AND external screen menu bars"
echo "  • M3/M4 Macs: If an external monitor is plugged in, the icon may"
echo "    ONLY appear on the external screen's menu bar"
echo ""
echo -e "${BLUE}Click the icon to:${NC}"
echo "  • Play your videos as a screensaver or ambient background"
echo "  • Launch the built-in Matrix Rain effect"
echo "  • Adjust settings (volume, opacity, loop, etc.)"
echo ""

# Launch the app
open "$APP_DIR"

echo -e "${GREEN}✅ HollywoodSaver is now running in your menu bar!${NC}"
echo -e "   If you don't see it, check your external monitor's menu bar."
echo ""
echo -e "   To quit: Click the icon → Quit (or ⌘Q)"
echo ""

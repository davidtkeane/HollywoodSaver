#!/bin/bash
# ============================================================================
# HollywoodSaver Release Script — 🎖️ MAINTAINER ONLY 🎖️
# ============================================================================
#
# 🚫 USERS: You do NOT need to run this script.
#    To build and run the app, use `bash build.sh` from the project root.
#
# 🛠️ MAINTAINERS: This script creates a GitHub Release with a pre-built
#    HollywoodSaver.app.zip and SHA-256 checksum, then uploads both as
#    release assets. The app's auto-update mechanism reads these releases.
#
# Requirements:
#    • GitHub CLI (`gh`) installed and authenticated with write access to
#      the davidtkeane/HollywoodSaver repo (run `gh auth login` once).
#    • A fresh build of HollywoodSaver.app in the project root (run
#      `bash build.sh` first).
#
# Usage (from project root):
#    bash release/release.sh
#
# What it does:
#    1. Reads version from src/AppDelegate.swift
#    2. Zips HollywoodSaver.app → HollywoodSaver.app.zip
#    3. Computes SHA-256 checksum
#    4. Creates git tag v${VERSION} (if not already tagged)
#    5. Pushes tag to origin
#    6. Creates GitHub Release with auto-generated notes + zip + checksum
#    7. Cleans up local zip/checksum files
#
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# release.sh lives in release/, so project root is one level up
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Extract version from Swift source
VERSION=$(grep -o 'appVersion = "[^"]*"' "$PROJECT_ROOT/src/AppDelegate.swift" | grep -o '"[^"]*"' | tr -d '"')
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not extract version from src/AppDelegate.swift${NC}"
    exit 1
fi

APP_DIR="$PROJECT_ROOT/HollywoodSaver.app"
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}Error: HollywoodSaver.app not found. Run 'bash build.sh' first.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  HollywoodSaver Release v${VERSION}${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Check gh CLI is available
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) not found. Install with: brew install gh${NC}"
    exit 1
fi

# Check if release already exists
if gh release view "v$VERSION" --repo davidtkeane/HollywoodSaver &> /dev/null; then
    echo -e "${YELLOW}Warning: Release v$VERSION already exists.${NC}"
    echo -n "Delete and recreate? (y/N): "
    read -r CONFIRM
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        gh release delete "v$VERSION" --repo davidtkeane/HollywoodSaver --yes
        echo -e "${GREEN}Deleted existing release.${NC}"
    else
        echo "Aborted."
        exit 0
    fi
fi

# Create zip (in project root, next to the .app)
echo -e "${BLUE}Creating HollywoodSaver.app.zip...${NC}"
cd "$PROJECT_ROOT"
zip -r HollywoodSaver.app.zip HollywoodSaver.app
ZIP_SIZE=$(du -h HollywoodSaver.app.zip | awk '{print $1}')
echo -e "  ${GREEN}✅${NC} Created ($ZIP_SIZE)"

# Create SHA-256 checksum
echo -e "${BLUE}Computing SHA-256 checksum...${NC}"
shasum -a 256 HollywoodSaver.app.zip > HollywoodSaver.app.zip.sha256
CHECKSUM=$(cat HollywoodSaver.app.zip.sha256 | awk '{print $1}')
echo -e "  ${GREEN}✅${NC} $CHECKSUM"

# Tag if not already tagged
echo -e "${BLUE}Tagging v${VERSION}...${NC}"
git tag -a "v$VERSION" -m "v$VERSION" 2>/dev/null && echo -e "  ${GREEN}✅${NC} Tag created" || echo -e "  ${YELLOW}⚠️${NC}  Tag already exists"
git push origin "v$VERSION" 2>/dev/null && echo -e "  ${GREEN}✅${NC} Tag pushed" || echo -e "  ${YELLOW}⚠️${NC}  Tag already on remote"

# Create GitHub Release with assets
echo -e "${BLUE}Creating GitHub Release...${NC}"
gh release create "v$VERSION" \
    --repo davidtkeane/HollywoodSaver \
    --title "HollywoodSaver v$VERSION" \
    --generate-notes \
    HollywoodSaver.app.zip \
    HollywoodSaver.app.zip.sha256

echo ""

# Cleanup
rm HollywoodSaver.app.zip HollywoodSaver.app.zip.sha256

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Release v${VERSION} published!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo -e "${BLUE}SHA-256:${NC} $CHECKSUM"
echo -e "${BLUE}URL:${NC}    https://github.com/davidtkeane/HollywoodSaver/releases/tag/v$VERSION"
echo ""

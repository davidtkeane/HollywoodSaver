#!/bin/bash
# compress_gif.sh — Reduce GIF size for GitHub READMEs
# Usage: bash compress_gif.sh input.gif
# Output: input_readme.gif (~2-3MB depending on source)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INPUT="$1"

if [ -z "$INPUT" ]; then
    echo -e "${RED}Usage: bash compress_gif.sh input.gif${NC}"
    exit 1
fi

if [ ! -f "$INPUT" ]; then
    echo -e "${RED}Error: File not found: $INPUT${NC}"
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo -e "${RED}Error: ffmpeg not found. Install with: brew install ffmpeg${NC}"
    exit 1
fi

BASENAME="${INPUT%.*}"
OUTPUT="${BASENAME}_readme.gif"
ORIGINAL_SIZE=$(du -h "$INPUT" | awk '{print $1}')

echo -e "${BLUE}Compressing GIF for README...${NC}"
echo "  Input:  $INPUT ($ORIGINAL_SIZE)"

ffmpeg -y -i "$INPUT" \
  -vf "scale=480:-1:flags=lanczos,fps=8,split[s0][s1];[s0]palettegen=max_colors=96:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
  "$OUTPUT" 2>/dev/null

OUTPUT_SIZE=$(du -h "$OUTPUT" | awk '{print $1}')

echo -e "  Output: $OUTPUT (${GREEN}${OUTPUT_SIZE}${NC})"
echo ""
echo -e "${GREEN}Done! Add to README.md:${NC}"
echo "  ![Demo]($OUTPUT)"
echo ""
echo -e "${BLUE}Rangers lead the way!${NC}"

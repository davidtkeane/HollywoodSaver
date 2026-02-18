# Changelog

All notable changes to HollywoodSaver are documented here.

## [2.2.0] - 2026-02-18

### Added
- **Contribute menu** — new submenu above Quit with two options:
  - ☕ **Buy Me a Coffee** — opens buymeacoffee.com/davidtkeane in browser
  - 🪙 **Hodl H3LLCOIN** — opens h3llcoin.com/how-to-buy.html in browser
- **README support section** — BuyMeACoffee badge + H3LLCOIN table with Jupiter swap link and contract address
- **ABOUT.md** — same donation links added and synced to all app bundles

### Changed
- All h3llcoin.cloud links updated to h3llcoin.com (canonical domain)

---

## [2.1.0] - 2026-02-18

### Added
- **Organized media folders** — `videos/` for .mp4/.mov/.m4v and `gifs/` for .gif files
- App scans root folder, `videos/`, and `gifs/` subfolders automatically
- Backward compatible — files in the root folder still work

### Changed
- `findMedia()` now scans three locations instead of one
- `resolveOriginalPath()` checks subfolders when resolving App Translocation paths
- Project structure updated in README with new folder layout
- CHANGELOG added to project

## [2.0.0] - 2026-02-18

### Added
- **Matrix Rain** — Built-in Matrix digital rain effect, no video file needed
- **Matrix Rain Settings** — Color theme (6 options), speed, character set, density, font size, trail length
- **Live Wallpaper Mode** — Ambient mode + reduced opacity turns any media into an animated wallpaper behind your windows
- **Ambient on All Screens** — Ambient mode now supports All Screens, Built-in, and External (previously external only)
- **run.sh** launcher script — prints helpful terminal output about where to find the menu bar icon
- **Shuffle Random** — pick a random video from your collection
- **TODO_FEATURES.md** — internal roadmap for future features (not tracked in git)
- **AppStore-Plan/** — internal App Store submission planning (not tracked in git)
- **MEGA download link** in README for hollywood.mp4 (113 MB)
- **Where is the icon?** section in README explaining M1 vs M3/M4 menu bar behavior
- **Buy Me a Coffee** and **H3LLCOIN** support sections in README
- **thematrix.png** — screenshot of Matrix Rain live wallpaper on external monitor

### Changed
- Ambient mode submenu now matches Screensaver with All Screens, Built-in, and individual screen options
- README rewritten as "video screensaver and live wallpaper engine"
- Project structure updated (~1300 lines, up from ~800)

## [1.1.0] - 2026-02-17

### Added
- **Demo GIF** (demo.gif) for README preview
- **GIF compression script** (compress_gif.sh) for optimizing demo assets
- **MEGA download link** for hollywood.mp4 video file
- H3LLCOIN promotion and comprehensive credits section in README

### Changed
- Build script enhanced for M1/M3/M4 compatibility
- .gitignore updated to properly exclude build output and media files
- Untracked compress_gif.sh from git (moved to .gitignore)

### Removed
- Removed loose bash script from repo

## [1.0.0] - 2026-02-17

### Added
- **Initial release** of HollywoodSaver
- **Screensaver Mode** — fullscreen video with cursor hidden, dismiss with Escape/click/mouse
- **Ambient Mode** — play on external monitor while you keep working
- **Multi-Screen support** — built-in, external, or all screens
- **Video + GIF support** — .mp4, .mov, .m4v, and .gif files
- **Volume slider** with mute toggle
- **Opacity slider** for ambient mode transparency
- **Loop toggle** — play forever or just once
- **Auto Play on Launch** — resume last video automatically
- **Launch at Login** — start with macOS
- **Custom menu bar icon** — drop ranger.png next to the app
- **Portable design** — move the folder anywhere, the app finds its videos
- **Single-file Swift app** — no Xcode project, no dependencies
- **build.sh** — creates the .app bundle, compiles Swift, generates icon, code-signs ad-hoc
- README with setup instructions and feature list

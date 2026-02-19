# Changelog

All notable changes to HollywoodSaver are documented here.

## [4.3.0] - 2026-02-19

### Added
- **Resume Playback After Wake** — when Mac wakes from sleep, automatically resumes the screensaver/ambient playback that was running before sleep (enabled by default, toggleable in Sleep submenu)

### Changed
- Version bumped to 4.3.0

---

## [4.2.0] - 2026-02-19

### Added
- **Sleep Countdown Overlay** — floating on-screen countdown showing time until sleep (blue color, positioned in opposite corner from break countdown)
- **Countdown Overlay toggle** — enable/disable the sleep countdown from the Sleep submenu

### Changed
- Version bumped to 4.2.0

---

## [4.1.0] - 2026-02-19

### Changed
- Version bumped to 4.1.0

---

## [4.0.0] - 2026-02-19

### Added
- **Sleep Now** — put your Mac to sleep instantly from the menu
- **Sleep Timer** — sleep after 90/60/45/30/15 minutes or custom duration, with 5-min and 1-min warnings
- **Sleep After Playback** — Mac sleeps automatically when the current video/GIF finishes

### Changed
- Version bumped to 4.0.0

---

## [3.4.0] - 2026-02-18

### Added
- **Custom break timer** — enter any number of minutes via input dialog
- **Break timer presets** — save and manage your favorite timer durations
- **Break sound** — audible alert (Glass, Hero, Ping, Pop, Purr, Submarine) when break screen appears
- **Countdown overlay color** — 6 color options: Green, Blue, Red, Orange, White, Purple
- **Countdown overlay size** — 3 sizes: Compact, Normal, Large
- **Pomodoro mode** — auto-cycling work/break timer (configurable work 15-50 min, break 3-15 min)
- **Session stats** — tracks breaks taken today and total, shown in Break Reminder menu
- **Break Screen toggle** — disable fullscreen break overlay for countdown-only mode (sound + notification still fire)
- **Resume Playback After Break** — automatically resumes screensaver/ambient playback after break screen dismisses (enabled by default, toggle in menu)
- **Show in Dock** — toggle to show/hide HollywoodSaver icon in the macOS Dock (off by default)
- **Desktop Shortcut** — toggle to create/remove a shortcut on your Desktop so you remember the app is there

### Changed
- Version bumped to 3.4.0
- Refactored startBreakTimer into reusable startBreakWithMinutes()

---

## [3.3.0] - 2026-02-18

### Added
- **Floating countdown overlay** — on-screen countdown timer widget visible while break timer is active
- **Display selection** — show countdown on All Screens, Built-in, or External only
- **Position selection** — place countdown in any corner: Top Right, Top Left, Bottom Right, Bottom Left
- Countdown overlay is click-through (doesn't block mouse events)
- Overlay auto-hides when break screen appears or timer is cancelled

### Changed
- Version bumped to 3.3.0

---

## [3.2.0] - 2026-02-18

### Added
- **Matrix Rain lock screen** — lock screen background shows animated Matrix Rain behind a semi-transparent overlay

### Changed
- Version bumped to 3.2.0

---

## [3.1.0] - 2026-02-18

### Added
- **Lock Screen** — password-protected screen lock with fullscreen overlay on all screens
- **Lock Screen menu** — Lock Now (Cmd+Shift+L), Set/Change Password, Clear Password
- **SHA-256 hashed password** — lock password stored securely with random salt (not plaintext)
- **Multi-screen lock** — password field on primary screen, overlay on all screens
- **Wrong password feedback** — shake animation + red error text on incorrect entry
- **Update notification** — system notification when a new version is detected (like a real app!)
- **Periodic version check** — checks GitHub every hour automatically, not just on launch

### Fixed
- **Break Reminder Escape key** — Escape/click/mouse now properly dismisses the break screen (InputMonitor was created but never started)
- **Break screen cleanup** — InputMonitor now properly stopped before cleanup to prevent event monitor leaks

### Changed
- Version bumped to 3.1.0
- Break screen skipped while lock screen is active

---

## [3.0.0] - 2026-02-18

### Added
- **Break Reminder** — countdown timer with 60, 45, 30, and 15 minute presets
- **Break screen overlay** — fullscreen "Take a Break, Ranger" screen with green glow effect
- **Auto-dismiss** — break screen auto-dismisses after 30 seconds or click/Escape
- **5-minute warning** — macOS notification 5 minutes before break time
- **Countdown in menu** — live countdown (MM:SS remaining) visible when timer is active
- **Cancel timer** — cancel any active break timer from the menu

### Fixed
- **Auto-update reliability** — replaced AppleScript with `open -a Terminal` (no Automation permission needed)
- **Error handling** — auto-update now shows error dialog instead of silently failing
- **Version cache cleared on build** — `build.sh` clears cached version so app does a fresh check on launch

### Changed
- Version bumped to 3.0.0

---

## [2.4.0] - 2026-02-18

### Added
- **GitHub version checker** — app checks for newer versions on launch via GitHub tags API
- **Version display in menu** — shows "HollywoodSaver v2.4.0" at top of menu dropdown
- **Update notification** — orange "Update Available: v2.4.0 → v2.5.0" when a newer tag exists
- **Update dialog** — NSAlert with Auto Update, Open GitHub, and Later buttons
- **Auto-update** — backs up current .app, runs git pull + build.sh in Terminal, relaunches
- **Dynamic version in build.sh** — reads version from Swift source, no more hardcoded Info.plist versions

### Changed
- Version is now single source of truth in `AppDelegate.appVersion`
- build.sh success message shows version number

---

## [2.3.0] - 2026-02-18

### Changed
- **build.sh auto-launches** — `bash build.sh` now automatically runs `run.sh` after a successful build. One command from zero to running app.

---

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

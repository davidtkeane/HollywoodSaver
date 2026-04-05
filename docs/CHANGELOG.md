# Changelog

All notable changes to HollywoodSaver are documented here.

## [5.0.0] - 2026-04-05 — Architecture Refactor

> **Architecture release.** Same feature set as v4.8.0, now living in a
> clean modular codebase: 14 Swift files in `src/`, with `docs/`,
> `images/`, `videos/`, and `gifs/` folders. Every v1.0 → v4.8 feature
> remains free forever. No new features, no removed features — just a
> grown-up project layout ready for the next chapter.

### Added
- **`src/` folder** — new home for all Swift source (14 focused files)
- **`images/` folder** — app logo (`ranger.png`) and screenshots (`thematrix.png`)
- **`docs/` folder** — project documentation (`ABOUT.md`, `CHANGELOG.md`)
- **Dual icon lookup** — `iconImagePath()` now checks both `appFolder/ranger.png` (user custom drop) and `appFolder/images/ranger.png` (dev layout), preserving the user customization feature while supporting the new folder structure
- **README docs links** — README now links to `docs/ABOUT.md` and `docs/CHANGELOG.md`

### Changed
- **DRY refactoring** — extracted three reusable helpers in `AppDelegate`:
  - `targetScreens(for:)` — resolves screen preference (`all`/`builtin`/`external`) to `[NSScreen]`, used in 5 places
  - `createFloatingOverlayWindow(rect:content:)` — standard transparent click-through window, shared by clock, break countdown, and sleep countdown overlays
  - `restartClockIfActive()` — collapses 5 clock setters and `toggleClockDate` from ~11 lines each down to 3–5 lines
  - **Net result: −75 lines** of duplicated code (3,674 → 3,599)
- **Module split** — single `HollywoodSaver.swift` (3,599 lines) split into **14 files** inside `src/`:
  | File | Responsibility |
  |------|----------------|
  | `main.swift` | App startup (`NSApplication` + delegate + run loop) |
  | `AppDelegate.swift` | Main controller (~2,485 lines) |
  | `Prefs.swift` | `UserDefaults` wrapper (37 preference keys) |
  | `MatrixConfig.swift` | 6 Matrix Rain config enums |
  | `MatrixRainView.swift` | Matrix Rain rendering |
  | `VideoPlayerView.swift` | `AVQueuePlayer`-based video playback |
  | `GifPlayerView.swift` | Frame-by-frame GIF animation |
  | `ScreensaverWindow.swift` | Custom `NSWindow` + `ScreensaverContent` protocol |
  | `InputMonitor.swift` | Global/local event monitoring |
  | `SliderMenuView.swift` | Volume slider menu item |
  | `BreakReminderView.swift` | Break screen overlay |
  | `LockScreen.swift` | Lock overlay + password entry views |
  | `CountdownOverlayView.swift` | Break/sleep countdown display |
  | `ClockOverlayView.swift` | Floating clock display |
- **Folder reorganization** — media and docs moved out of root:
  - `videos/` — `.mp4`, `.mov`, `.m4v` (moved `hollywood.mp4`, `hq.mp4`)
  - `gifs/` — `.gif` files (moved `demo.gif`)
  - `images/` — app logo and screenshots (moved `ranger.png`, `thematrix.png`)
  - `docs/` — `ABOUT.md`, `CHANGELOG.md` relocated here
- **`build.sh`** — now compiles every file in `src/*.swift`, reads version from `src/AppDelegate.swift`, and reads icon source from `images/ranger.png`; `ABOUT.md` is copied from `docs/ABOUT.md` into the built bundle
- **`README.md`** — project structure diagram rewritten to reflect the new layout, image paths updated (`gifs/demo.gif`, `images/thematrix.png`), docs links added
- **Menu reorganization — Rain Effects nested inside Matrix Rain** — the top-level "Rain Effects" menu item has moved into the Matrix Rain submenu as a sibling of "Settings". Rationale: Rain Effects *are* Matrix Rain running in specific modes (behind/over windows), so grouping them under their parent feature is more discoverable. Settings stays focused on visual config (color/speed/characters/density/font/trail length), while Rain Effects holds the behavior toggles (Rain Behind, Rain Over, opacity sliders, display selection, Stop All Rain). Top-level menu is cleaner with one fewer item.
- **Menu reorganization — Clock repositioned** — the top-level "Clock" submenu (briefly nested inside Break Reminder) now sits as its own top-level item between Break Reminder and Lock Screen, with a separator below. Rationale: Clock is an independent always-on overlay feature, not specifically tied to break timers — keeping it at top level with its own section makes it easier to reach. Clock keeps its full submenu (Show Clock, Show Date, Display, Position, Color, Size) intact.
- **Menu reorganization — Sleep repositioned** — the "Sleep" submenu moved from the middle of the menu (previously between Desktop Shortcut and Break Reminder) to near the bottom, between Lock Screen and Contribute. Rationale: Sleep is an exit-style action like Lock/Quit, so grouping it with them at the bottom of the menu is more intuitive than mixing it with playback settings. Sleep submenu contents unchanged (Sleep Now, Sleep in 90/60/45/30/15 min, Custom, Sleep After Playback, Countdown Overlay, Resume Playback After Wake).
- **Menu reorganization — features-first layout** — the menu is now organized into three clear zones separated by dividers: (1) **what to play** — media list + Matrix Rain, (2) **what to do** — Break Reminder, Clock, Lock Screen, Sleep (all feature submenus grouped together right under Matrix Rain), (3) **how to configure** — Sound, Volume, Opacity, Loop, Auto Play on Launch, Launch at Login, Show in Dock, Desktop Shortcut (flat toggles pushed to the bottom just above Contribute). Rationale: users open the menu to *do something*, not tweak settings — frequently-clicked features belong at the top. Matches the standard Mac app convention of features-first, preferences-last.

### Fixed
- **Menu bar icon regression** — after moving `ranger.png` to `images/`, the Swift runtime still looked only in `appFolder/ranger.png` and silently fell back to the `play.rectangle.fill` SF Symbol. Fixed by checking both legacy root and new `images/` paths. User customization (drop your own `ranger.png` next to the installed `.app`) still works exactly as before.
- **Single-screen menu missing Screensaver/Ambient choice** — on MacBooks with no external monitor attached, clicking the menu bar icon showed flat "Play {video}" entries with no `>` submenu, silently forcing Screensaver mode. There was no way to trigger Ambient (live wallpaper) mode from a single-screen Mac. Now every video and Matrix Rain always shows a proper `>` submenu with **Screensaver** and **Ambient (keep working)** options — regardless of monitor configuration. `addScreenItems()` helper now skips the redundant "All Screens" row when there are no externals (it would just duplicate the Built-in row), keeping the menu clean. Fixes both video items and Matrix Rain in one go.

### Technical Notes
- Zero user-facing behavioural changes — the app looks and acts identically to v4.8.0
- Zero new compile errors (22 pre-existing macOS 15 `CVDisplayLink` deprecation warnings are unchanged)
- Compiled binary size unchanged at ~804 KB
- All 37 preference keys preserved; `UserDefaults` data from older versions carries over seamlessly

### Why
Code quality groundwork before v5.0.0 Pro development. 14 focused files are
far easier to navigate, diff, and review than one 3,600-line monolith —
and the folder separation finally makes the repo look like a grown-up project.
Easier onboarding for contributors, cleaner git blame, room to grow.

---

## [4.8.0] - 2026-02-19 — FINAL FREE VERSION

> **This is the last free release.** v5.0.0 begins the Pro version journey with registration,
> advanced features, and the Rangers token ecosystem. Everything in v4.8.0 remains free forever.

### Added
- **Floating Clock Overlay** — always-on-top, click-through clock displaying current time
- **Show Date toggle** — optionally show day and date above the time
- **Clock Display selection** — All Screens, Built-in, or External
- **Clock Position** — place in any corner: Top Right, Top Left, Bottom Right, Bottom Left
- **Clock Color** — 6 colors matching Matrix Rain: Green, Blue, Red, Orange, White, Purple
- **Clock Size** — Compact, Normal, or Large
- Clock auto-restores on app relaunch
- Uses system locale for 12hr/24hr time format

### Summary of Free Features (v1.0 → v4.8.0)
- Screensaver Mode, Ambient Mode, Live Wallpaper Mode (multi-screen)
- Matrix Rain with full settings (color, speed, density, font, characters, trails)
- Rain Effects — behind windows + over windows (independent, click-through, auto-restore)
- Rain Effects screen selection (All/Built-in/External)
- Floating Clock Overlay (6 colors, 3 sizes, 4 positions, date toggle, screen selection)
- Break Reminder with Pomodoro mode, countdown overlay, session stats, break sound
- Lock Screen with SHA-256 password hashing
- Sleep Timer (Now/Scheduled/After Playback) with countdown overlay, resume on wake
- Secure auto-update via GitHub Releases + SHA-256 checksum verification
- Hardened Runtime, input validation, portable design, launch at login, auto play

---

## [4.7.0] - 2026-02-19

### Added
- **Rain Effects Display Selection** — choose which screen(s) to show rain on: All Screens, Built-in, or External (one shared setting for both rain modes)
- Rain restarts immediately on the selected screen(s) when changed

---

## [4.6.0] - 2026-02-19

### Changed
- **Updated ABOUT.md** — complete overhaul reflecting all features from v1.0 through v4.6.0 (was stuck at v1.0)
- Version bumped to 4.6.0

---

## [4.5.0] - 2026-02-19

### Added
- **Rain Effects** submenu with two independent Matrix Rain modes:
  - **Rain Behind Windows** — Matrix Rain as your desktop wallpaper (behind all windows and icons)
  - **Rain Over Windows** — transparent Matrix Rain overlay falling in front of everything while you keep working, fully click-through
  - Both can run simultaneously or independently
  - Each has its own opacity slider (Behind: 0.1–1.0, Over: 0.05–0.5)
  - Both auto-restore on app relaunch
  - Works across all screens and Spaces

---

## [4.4.0] - 2026-02-19

### Security
- **Secure Auto-Update** — replaced `git pull` + compile with pre-built GitHub Releases download + SHA-256 checksum verification. Eliminates supply chain risk from compromised repos.
- **Hardened Runtime** — ad-hoc builds now include Hardened Runtime (blocks DYLD injection attacks)
- **Input Validation** — custom timer inputs capped at 1440 minutes (24 hours max)

### Added
- `release.sh` — new script to create GitHub Releases with .app.zip and checksum assets

### Changed
- Version checker now uses GitHub Releases API (falls back to Tags API for older releases)
- Update dialog explains download-based update with checksum verification
- Error messages point to GitHub Releases page instead of git commands

---

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

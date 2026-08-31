# HollywoodSaver — Multi-Monitor Architecture & Technical Reference

**Date:** August 24, 2026  
**Target:** macOS 15+ (Apple Silicon — M1/M2/M3/M4)  
**Status:** Active Reference (`v5.0.4+`)  

---

## 1. Overview & Objectives

HollywoodSaver provides independent multi-monitor playback, live wallpaper assignment, and screensaver execution across complex Apple Silicon display topologies (built-in MacBook displays, external 4K/5K monitors, and Pro Display XDRs).

This document serves as the persistent technical record of:
1. macOS AppKit status bar (`NSStatusBar`) behavior and display constraints.
2. Per-monitor screensaver input isolation (working on a laptop while playing on external screens).
3. The per-screen media assignment engine (`Displays` submenu).
4. Auto-update release infrastructure.

---

## 2. macOS Status Bar (`NSStatusBar`) Architecture & Constraints

### 2.1 How macOS Manages Status Bar Items
In macOS AppKit, `NSStatusBar.system` represents the system-wide status bar.
- **Main Display Binding:** macOS automatically pins all third-party `NSStatusItem` instances to the **Main Display** (the display configured with the primary menu bar in **System Settings ▶ Displays**).
- **Behavior with "Displays have separate Spaces":**
  - When enabled, every physical display renders a top menu bar.
  - However, third-party status items created via `NSStatusBar.system.statusItem(withLength:)` reside exclusively in the status bar of the primary/active screen.
  - Apple's `WindowServer` and `ControlCenter` own the physical placement of status items and do not expose an API for third-party processes to bind specific `NSStatusItem`s to secondary physical screens.

### 2.2 The Multi-Instance Status Item Experiment
In early `v5.0.2` testing, an experiment was conducted where `AppDelegate` instantiated `NSScreen.screens.count` status items:
```swift
// EXPERIMENT (Reverted in v5.0.3):
for _ in 0..<NSScreen.screens.count {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItems.append(item)
}
```
**Result & Finding:**  
Rather than distributing one icon per physical display, macOS AppKit grouped all status items together on the **primary external monitor**, resulting in duplicate side-by-side icons.

**Architectural Decision (`v5.0.3`):**  
Standardized on a single, clean `NSStatusItem` instance (`var statusItem: NSStatusItem!`). This conforms to Apple Human Interface Guidelines and eliminates visual clutter.

---

## 3. Multi-Screen Screensaver Input Isolation

### 3.1 The Problem in Prior Versions
In standard macOS screensaver mode, any mouse movement, click, or keystroke immediately dismissed playback across the entire system. When a user wanted to run a screensaver/video exclusively on an external monitor while coding on their built-in MacBook display:
1. Moving the mouse on the laptop instantly triggered `InputMonitor` and killed external playback.
2. `NSCursor.hide()` hid the cursor globally across all displays, preventing laptop work.
3. `NSApp.activate(ignoringOtherApps: true)` stole focus from user applications.

### 3.2 The Spatial Isolation Engine (`InputMonitor.swift`)
In `v5.0.2+`, `InputMonitor` implements spatial coordinate filtering via `activeScreensaverFrames: [NSRect]`:

```swift
func isPointOnScreensaver(_ point: NSPoint) -> Bool {
    if activeScreensaverFrames.isEmpty { return true }
    return activeScreensaverFrames.contains { $0.contains(point) }
}
```

#### Event Handling Rules:
| Event Type | Condition | Action |
|---|---|---|
| **Escape Key (`keyCode == 53`)** | Always | Dismisses **every** screensaver screen |
| **Mouse Click (`left/right/other`)** | Inside a screensaver frame | Dismisses **that screen only** |
| **Mouse Click (`left/right/other`)** | On user's working / idle screen | **Ignored** |
| **Mouse Movement / Scroll** | Inside a screensaver frame (> 20pt) | Dismisses **that screen only** |
| **Mouse Movement / Scroll** | On user's working / idle screen | **Ignored** |

### 3.3 Conditional Focus & Cursor Management (`AppDelegate+Playback.swift`)
When playback starts:
- If screensaver covers **all connected displays**:
  ```swift
  NSApp.activate(ignoringOtherApps: true)
  NSCursor.hide()
  ```
- If screensaver is assigned to **a subset of displays** (e.g. external only):
  - `NSCursor.hide()` is **bypassed** (cursor remains visible on working display).
  - `NSApp.activate` is **bypassed** (active code editors/browsers retain focus).

When several screens are playing, mouse/click still maps to one frame via `stopPlayingOnScreen(id:)`. A 0.5s grace after each per-screen dismiss stops a cross-monitor swipe from killing the neighbour. Escape remains the global stop.

---

## 4. Per-Monitor Playback Engine

### 4.1 Hardware Screen Identification (`ScreensaverWindow.swift`)
To prevent configuration loss during monitor hotplugging or resolution changes, screens are identified using hardware `CGDirectDisplayID`:

```swift
extension NSScreen {
    var screenIdentifier: String {
        if let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return "\(id)_\(localizedName)"
        }
        return localizedName
    }
}
```

### 4.2 Independent Window Lifecycle
Each active playback window tracks its screen metadata:
```swift
class ScreensaverWindow: NSWindow {
    var targetScreenID: String?
    var screenSessionMode: PlayMode?
    var screenSessionMedia: String?
}
```
This allows granular teardown via `stopPlayingOnScreen(id:)` without tearing down or interrupting media playing on adjacent screens.

### 4.3 Multi-Monitor Controller Submenu (`AppDelegate+Menu.swift`)
When 2 or more screens are connected, the top-level menu shows **Displays**:
- Real-time status per display (`● Playing: Video Title` vs `○ Idle`).
- Click a clip or effect to play screensaver on that display; Option-click is ambient (no Screensaver/Ambient third level).
- Stop This Display tears down only that screen.
- Play (root) uses `Prefs.lastPlayScreen` (all / builtin / external / a stored `screenIdentifier`). Missing or unplugged IDs fall back to all screens.

### 4.4 Display-change restore
`NSApplication.didChangeScreenParametersNotification` used to call `startPlaying(media: currentMediaPath, on: NSScreen.screens)`, which cloned the last-started file onto every display and wiped per-monitor assignments.

It now snapshots each window's `screenSessionMedia` / `screenSessionMode` / `targetScreenID`, rematches live `NSScreen`s (exact ID, then display name), recreates only those screens, and leaves newly attached displays idle instead of cloning. The handler is debounced (~350ms) because macOS fires the notification in bursts.

---

## 5. Release & Auto-Update Architecture

### 5.1 Versioning Single Source of Truth
- Version string is declared exclusively in [`src/AppDelegate.swift`](file:///Users/ranger/M4-Stuff/Ranger-Projects/HollywoodSaver/src/AppDelegate.swift):
  ```swift
  static let appVersion = "5.0.4"
  ```
- `build.sh` and `release/release.sh` extract this version dynamically at build time:
  ```bash
  VERSION=$(grep -o 'appVersion = "[^"]*"' "$SCRIPT_DIR/src/AppDelegate.swift" | grep -o '"[^"]*"' | tr -d '"')
  ```

### 5.2 Secure Auto-Updater Pipeline
1. `release/release.sh` bundles `HollywoodSaver.app.zip` and generates a SHA-256 checksum file.
2. Creates and pushes Git tag `v${VERSION}` and publishes a GitHub Release via `gh release create`.
3. Client app (`AppDelegate+Updates.swift`) queries `https://api.github.com/repos/davidtkeane/HollywoodSaver/releases/latest`.
4. If a newer tag is detected, the app downloads the `.app.zip`, verifies the SHA-256 hash using `CryptoKit.SHA256`, swaps the application bundle in place, and relaunches automatically.

---

## 6. Summary Matrix

| Feature | Single Screen | Multi-Screen (Subset) | Multi-Screen (All) |
|---|---|---|---|
| **Status Bar Icon** | Main Screen | Main Screen | Main Screen |
| **Cursor Hiding** | Hidden (Screensaver) | Visible on Work Screen | Hidden |
| **Mouse Dismissal** | That screen | Isolated to that media screen | That screen (Esc = all) |
| **Typing Dismissal** | Escape Only | Escape Only | Escape Only |
| **Independent Stop** | Main Stop | Stop per Display | Stop All |

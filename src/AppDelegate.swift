import Cocoa
import AVFoundation
import QuartzCore
import ImageIO
import ServiceManagement
import CryptoKit
import IOKit.pwr_mgt
import UserNotifications

// MARK: - App Delegate

enum PlayMode {
    case screensaver
    case ambient
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static let matrixRainSentinel = "##MATRIX_RAIN##"
    static let starfieldWarpSentinel = "##STARFIELD_WARP##"
    static let appVersion = "5.0.0"
    static let githubRepo = "davidtkeane/HollywoodSaver"

    var statusItem: NSStatusItem!
    var screensaverWindows: [ScreensaverWindow] = []
    var contentViews: [ScreensaverContent] = []
    var inputMonitor: InputMonitor?
    var activityToken: NSObjectProtocol?
    var selectedMedia: String?
    var currentMode: PlayMode?
    var nowPlayingName: String?
    var latestVersion: String?
    var breakTimer: Timer?
    var breakEndDate: Date?
    var lockScreenWindows: [ScreensaverWindow] = []
    var lockScreenActive = false
    var versionCheckTimer: Timer?
    var countdownWindows: [NSWindow] = []
    var pomodoroActive = false
    var pomodoroOnBreak = false
    var currentMediaPath: String?
    var savedMediaBeforeBreak: String?
    var savedModeBeforeBreak: PlayMode?
    var sleepTimer: Timer?
    var sleepEndDate: Date?
    var sleepAfterPlayback = false
    var sleepCountdownWindows: [NSWindow] = []
    var savedMediaBeforeSleep: String?
    var savedModeBeforeSleep: PlayMode?
    var latestReleaseZipURL: String?
    var latestReleaseChecksumURL: String?
    var rainOverlayWindows: [NSWindow] = []
    var rainOverlayViews: [ScreensaverContent] = []
    var rainBehindWindows: [NSWindow] = []
    var rainBehindViews: [ScreensaverContent] = []
    var clockWindows: [NSWindow] = []
    var clockTimer: Timer?

    static let videoExtensions = ["mp4", "mov", "m4v"]
    static let gifExtensions = ["gif"]
    static let allExtensions = videoExtensions + gifExtensions

    var appFolder: String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("/AppTranslocation/") {
            if let original = resolveOriginalPath(bundlePath) {
                return (original as NSString).deletingLastPathComponent
            }
        }
        return (bundlePath as NSString).deletingLastPathComponent
    }

    func resolveOriginalPath(_ translocatedPath: String) -> String? {
        typealias TranslocateFunc = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Bool
        guard let _ = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else {
            return nil
        }
        let appName = ((translocatedPath as NSString).lastPathComponent)
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/Desktop/HollywoodSaver/\(appName)",
            "\(home)/Applications/\(appName)",
            "/Applications/\(appName)",
            "\(home)/Desktop/\(appName)",
            "\(home)/Downloads/\(appName)",
        ]
        let fm = FileManager.default
        for candidate in candidates {
            let folder = (candidate as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: candidate) {
                // Check root folder and subfolders for media files
                let foldersToCheck = [folder] + AppDelegate.mediaSubfolders.map {
                    (folder as NSString).appendingPathComponent($0)
                }
                for checkFolder in foldersToCheck {
                    if let files = try? fm.contentsOfDirectory(atPath: checkFolder),
                       files.contains(where: { AppDelegate.allExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
                        return candidate
                    }
                }
            }
        }
        for candidate in candidates {
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    func isGif(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return AppDelegate.gifExtensions.contains(ext)
    }

    static let mediaSubfolders = ["videos", "gifs"]

    func findMedia() -> [String] {
        let fm = FileManager.default
        var media: [String] = []

        let folders = [appFolder] + AppDelegate.mediaSubfolders.map {
            (appFolder as NSString).appendingPathComponent($0)
        }

        for folder in folders {
            if let files = try? fm.contentsOfDirectory(atPath: folder) {
                for file in files.sorted() {
                    let ext = (file as NSString).pathExtension.lowercased()
                    if AppDelegate.allExtensions.contains(ext) {
                        media.append((folder as NSString).appendingPathComponent(file))
                    }
                }
            }
        }

        return media
    }

    func displayName(for path: String) -> String {
        let filename = (path as NSString).lastPathComponent
        return (filename as NSString).deletingPathExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Prefs.showDockIcon ? .regular : .accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let iconPath = iconImagePath(), let image = NSImage(contentsOfFile: iconPath) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                let image = NSImage(systemSymbolName: "play.rectangle.fill",
                                    accessibilityDescription: "HollywoodSaver")
                image?.isTemplate = true
                button.image = image
            }
        }

        statusItem.menu = buildMenu()

        // Check for updates in background (and every hour after)
        checkForUpdates(forceRefresh: true)
        versionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkForUpdates(forceRefresh: false)
        }

        // Auto play on launch
        if Prefs.autoPlayEnabled, let filename = Prefs.lastMediaFilename {
            let mode: PlayMode = Prefs.lastPlayMode == "ambient" ? .ambient : .screensaver
            if filename == AppDelegate.matrixRainSentinel || filename == AppDelegate.starfieldWarpSentinel {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startPlaying(media: filename, on: NSScreen.screens, mode: mode)
                }
            } else {
                let path = (appFolder as NSString).appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: path) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startPlaying(media: path, on: NSScreen.screens, mode: mode)
                    }
                }
            }
        }

        // Restore rain effects if they were enabled
        if Prefs.rainBehindEnabled || Prefs.rainOverlayEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if Prefs.rainBehindEnabled { self.startRainBehind() }
                if Prefs.rainOverlayEnabled { self.startRainOverlay() }
            }
        }

        if Prefs.clockEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startClockOverlay()
            }
        }

        // Sync desktop shortcut on launch
        syncDesktopShortcut()

        // Listen for Mac wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc func handleWakeFromSleep() {
        if Prefs.resumeAfterSleep, let media = savedMediaBeforeSleep, let mode = savedModeBeforeSleep {
            savedMediaBeforeSleep = nil
            savedModeBeforeSleep = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.startPlaying(media: media, on: NSScreen.screens, mode: mode)
            }
        } else {
            savedMediaBeforeSleep = nil
            savedModeBeforeSleep = nil
        }
    }

    var isPlaying: Bool { currentMode != nil }

    func iconImagePath() -> String? {
        // 1. User drop: ranger.png next to the .app bundle (custom icon feature)
        let rootPath = (appFolder as NSString).appendingPathComponent("ranger.png")
        if FileManager.default.fileExists(atPath: rootPath) { return rootPath }
        // 2. Dev layout: images/ranger.png in the project folder
        let imagesPath = ((appFolder as NSString).appendingPathComponent("images") as NSString).appendingPathComponent("ranger.png")
        if FileManager.default.fileExists(atPath: imagesPath) { return imagesPath }
        return nil
    }

    func setMenuBarIcon(symbolName: String) {
        guard let button = statusItem.button else { return }
        if let iconPath = iconImagePath(), let image = NSImage(contentsOfFile: iconPath) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        } else {
            let image = NSImage(systemSymbolName: symbolName,
                                accessibilityDescription: "HollywoodSaver")
            image?.isTemplate = true
            button.image = image
        }
    }

    // MARK: - Helpers (DRY)

    /// Resolve a screen preference ("all"/"builtin"/"external") to the matching `NSScreen` list.
    /// Falls back to all screens if the requested type isn't available.
    func targetScreens(for preference: String) -> [NSScreen] {
        let screens = NSScreen.screens
        let builtIn = screens.first { $0.localizedName.contains("Built") }
        let externals = screens.filter { !$0.localizedName.contains("Built") }
        switch preference {
        case "builtin": return builtIn.map { [$0] } ?? screens
        case "external": return externals.isEmpty ? screens : externals
        default: return screens
        }
    }

    /// Create a transparent, click-through floating window used by clock/countdown overlays.
    func createFloatingOverlayWindow(rect: NSRect, content: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: rect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = content
        return window
    }

    /// Rebuild the clock overlay and restart its update timer — only if it's currently active.
    /// Used by every clock setting mutator so we don't repeat the same block 5 times.
    func restartClockIfActive() {
        guard !clockWindows.isEmpty else { return }
        showClockOverlay()
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateClockOverlay()
        }
    }

    // MARK: - Menu

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Version info / Update available
        if let latest = latestVersion, isNewerVersion(latest, than: AppDelegate.appVersion) {
            let updateItem = NSMenuItem(
                title: "Update Available: v\(AppDelegate.appVersion) → v\(latest)",
                action: #selector(showUpdateDialog),
                keyEquivalent: ""
            )
            updateItem.attributedTitle = NSAttributedString(
                string: "Update Available: v\(AppDelegate.appVersion) → v\(latest)",
                attributes: [.foregroundColor: NSColor.systemOrange]
            )
            menu.addItem(updateItem)
            menu.addItem(NSMenuItem.separator())
        } else {
            let versionItem = NSMenuItem(
                title: "HollywoodSaver v\(AppDelegate.appVersion)",
                action: nil,
                keyEquivalent: ""
            )
            versionItem.isEnabled = false
            menu.addItem(versionItem)

            let checkItem = NSMenuItem(title: "Check for Update", action: #selector(manualCheckForUpdate), keyEquivalent: "")
            menu.addItem(checkItem)
            menu.addItem(NSMenuItem.separator())
        }

        // If ambient mode is active, show stop option at the top
        if currentMode == .ambient, let name = nowPlayingName {
            let stopItem = NSMenuItem(title: "Stop \(name)", action: #selector(stopPlaying), keyEquivalent: "")
            menu.addItem(stopItem)
            menu.addItem(NSMenuItem.separator())
        }

        let media = findMedia()
        let screens = NSScreen.screens
        let builtIn = screens.first { $0.localizedName.contains("Built") }
        let externals = screens.filter { !$0.localizedName.contains("Built") }

        if media.isEmpty {
            let item = NSMenuItem(title: "No media found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let hint = NSMenuItem(title: "Add .mp4/.gif files next to the app", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        } else if media.count == 1 {
            selectedMedia = media[0]
            let name = displayName(for: media[0])
            let header = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(NSMenuItem.separator())
            addScreenItems(to: menu, file: media[0], builtIn: builtIn, externals: externals)
        } else {
            // Shuffle option
            let shuffleItem = NSMenuItem(title: "Shuffle Random", action: #selector(playShuffle), keyEquivalent: "")
            menu.addItem(shuffleItem)
            menu.addItem(NSMenuItem.separator())

            for file in media {
                let name = displayName(for: file)
                let submenu = NSMenu()
                addScreenItems(to: submenu, file: file, builtIn: builtIn, externals: externals)

                let menuItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                menuItem.submenu = submenu
                menu.addItem(menuItem)
            }
        }

        // Matrix Rain - built-in effect
        menu.addItem(NSMenuItem.separator())
        let matrixItem = NSMenuItem(title: "Matrix Rain", action: nil, keyEquivalent: "")
        let matrixSubmenu = NSMenu()

        // Matrix settings submenu
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsSubmenu = NSMenu()

        // Color Theme
        let colorMenu = NSMenu()
        for theme in MatrixColorTheme.allCases {
            let item = NSMenuItem(title: theme.rawValue, action: #selector(setMatrixColor(_:)), keyEquivalent: "")
            item.representedObject = theme.rawValue as AnyObject
            item.state = Prefs.matrixColorTheme == theme.rawValue ? .on : .off
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Color Theme", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        settingsSubmenu.addItem(colorItem)

        // Speed
        let speedMenu = NSMenu()
        for s in MatrixSpeed.allCases {
            let item = NSMenuItem(title: s.rawValue, action: #selector(setMatrixSpeed(_:)), keyEquivalent: "")
            item.representedObject = s.rawValue as AnyObject
            item.state = Prefs.matrixSpeed == s.rawValue ? .on : .off
            speedMenu.addItem(item)
        }
        let speedItem = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        speedItem.submenu = speedMenu
        settingsSubmenu.addItem(speedItem)

        // Characters
        let charMenu = NSMenu()
        for cs in MatrixCharacterSet.allCases {
            let item = NSMenuItem(title: cs.rawValue, action: #selector(setMatrixCharSet(_:)), keyEquivalent: "")
            item.representedObject = cs.rawValue as AnyObject
            item.state = Prefs.matrixCharacterSet == cs.rawValue ? .on : .off
            charMenu.addItem(item)
        }
        let charItem = NSMenuItem(title: "Characters", action: nil, keyEquivalent: "")
        charItem.submenu = charMenu
        settingsSubmenu.addItem(charItem)

        // Density
        let densityMenu = NSMenu()
        for d in MatrixDensity.allCases {
            let item = NSMenuItem(title: d.rawValue, action: #selector(setMatrixDensity(_:)), keyEquivalent: "")
            item.representedObject = d.rawValue as AnyObject
            item.state = Prefs.matrixDensity == d.rawValue ? .on : .off
            densityMenu.addItem(item)
        }
        let densityItem = NSMenuItem(title: "Density", action: nil, keyEquivalent: "")
        densityItem.submenu = densityMenu
        settingsSubmenu.addItem(densityItem)

        // Font Size
        let fontMenu = NSMenu()
        for f in MatrixFontSize.allCases {
            let item = NSMenuItem(title: f.rawValue, action: #selector(setMatrixFontSize(_:)), keyEquivalent: "")
            item.representedObject = f.rawValue as AnyObject
            item.state = Prefs.matrixFontSize == f.rawValue ? .on : .off
            fontMenu.addItem(item)
        }
        let fontItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        settingsSubmenu.addItem(fontItem)

        // Trail Length
        let trailMenu = NSMenu()
        for t in MatrixTrailLength.allCases {
            let item = NSMenuItem(title: t.rawValue, action: #selector(setMatrixTrailLength(_:)), keyEquivalent: "")
            item.representedObject = t.rawValue as AnyObject
            item.state = Prefs.matrixTrailLength == t.rawValue ? .on : .off
            trailMenu.addItem(item)
        }
        let trailItem = NSMenuItem(title: "Trail Length", action: nil, keyEquivalent: "")
        trailItem.submenu = trailMenu
        settingsSubmenu.addItem(trailItem)

        settingsItem.submenu = settingsSubmenu
        matrixSubmenu.addItem(settingsItem)

        // Rain Effects submenu (sibling of Settings, inside Matrix Rain)
        let rainItem = NSMenuItem(title: "Rain Effects", action: nil, keyEquivalent: "")
        let rainSubmenu = NSMenu(title: "Rain Effects")

        // Rain Behind Windows toggle
        let rainBehindToggle = NSMenuItem(title: "Rain Behind Windows", action: #selector(toggleRainBehind), keyEquivalent: "")
        rainBehindToggle.state = !rainBehindWindows.isEmpty ? .on : .off
        rainSubmenu.addItem(rainBehindToggle)

        let rainBehindOpacityView = SliderMenuView(title: "Behind Opacity", minValue: 0.1, maxValue: 1, currentValue: Double(Prefs.rainBehindOpacity)) { newVal in
            Prefs.rainBehindOpacity = newVal
            for w in self.rainBehindWindows {
                w.alphaValue = CGFloat(newVal)
            }
        }
        let rainBehindOpacityItem = NSMenuItem()
        rainBehindOpacityItem.view = rainBehindOpacityView
        rainSubmenu.addItem(rainBehindOpacityItem)

        rainSubmenu.addItem(NSMenuItem.separator())

        // Rain Over Windows toggle
        let rainOverToggle = NSMenuItem(title: "Rain Over Windows", action: #selector(toggleRainOverlay), keyEquivalent: "")
        rainOverToggle.state = !rainOverlayWindows.isEmpty ? .on : .off
        rainSubmenu.addItem(rainOverToggle)

        let rainOverOpacityView = SliderMenuView(title: "Over Opacity", minValue: 0.05, maxValue: 0.5, currentValue: Double(Prefs.rainOverlayOpacity)) { newVal in
            Prefs.rainOverlayOpacity = newVal
            for w in self.rainOverlayWindows {
                w.alphaValue = CGFloat(newVal)
            }
        }
        let rainOverOpacityItem = NSMenuItem()
        rainOverOpacityItem.view = rainOverOpacityView
        rainSubmenu.addItem(rainOverOpacityItem)

        // Display selection for rain effects
        rainSubmenu.addItem(NSMenuItem.separator())
        let rainDisplayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let rainDisplaySubmenu = NSMenu(title: "Display")
        for (label, value) in [("All Screens", "all"), ("Built-in", "builtin"), ("External", "external")] {
            let item = NSMenuItem(title: label, action: #selector(setRainScreen(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.rainScreen == value ? .on : .off
            rainDisplaySubmenu.addItem(item)
        }
        rainDisplayItem.submenu = rainDisplaySubmenu
        rainSubmenu.addItem(rainDisplayItem)

        // Stop All Rain (only show when at least one rain mode is active)
        if !rainBehindWindows.isEmpty || !rainOverlayWindows.isEmpty {
            rainSubmenu.addItem(NSMenuItem.separator())
            let stopAllRain = NSMenuItem(title: "Stop All Rain", action: #selector(stopAllRainEffects), keyEquivalent: "")
            rainSubmenu.addItem(stopAllRain)
        }

        rainItem.submenu = rainSubmenu
        matrixSubmenu.addItem(rainItem)

        matrixSubmenu.addItem(NSMenuItem.separator())

        // Screen selection for Matrix Rain
        addScreenItems(to: matrixSubmenu, file: AppDelegate.matrixRainSentinel, builtIn: builtIn, externals: externals)

        matrixItem.submenu = matrixSubmenu
        menu.addItem(matrixItem)

        // Starfield Warp - built-in hyperspace effect
        let starfieldItem = NSMenuItem(title: "Starfield Warp", action: nil, keyEquivalent: "")
        let starfieldSubmenu = NSMenu()

        // Starfield settings submenu
        let starfieldSettingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let starfieldSettingsSubmenu = NSMenu()

        // Speed
        let starfieldSpeedMenu = NSMenu()
        for s in StarfieldSpeed.allCases {
            let item = NSMenuItem(title: s.rawValue, action: #selector(setStarfieldSpeed(_:)), keyEquivalent: "")
            item.representedObject = s.rawValue as AnyObject
            item.state = Prefs.starfieldSpeed == s.rawValue ? .on : .off
            starfieldSpeedMenu.addItem(item)
        }
        let starfieldSpeedItem = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        starfieldSpeedItem.submenu = starfieldSpeedMenu
        starfieldSettingsSubmenu.addItem(starfieldSpeedItem)

        // Color
        let starfieldColorMenu = NSMenu()
        for c in StarfieldColor.allCases {
            let item = NSMenuItem(title: c.rawValue, action: #selector(setStarfieldColor(_:)), keyEquivalent: "")
            item.representedObject = c.rawValue as AnyObject
            item.state = Prefs.starfieldColor == c.rawValue ? .on : .off
            starfieldColorMenu.addItem(item)
        }
        let starfieldColorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        starfieldColorItem.submenu = starfieldColorMenu
        starfieldSettingsSubmenu.addItem(starfieldColorItem)

        // Density
        let starfieldDensityMenu = NSMenu()
        for d in StarfieldDensity.allCases {
            let item = NSMenuItem(title: d.rawValue, action: #selector(setStarfieldDensity(_:)), keyEquivalent: "")
            item.representedObject = d.rawValue as AnyObject
            item.state = Prefs.starfieldDensity == d.rawValue ? .on : .off
            starfieldDensityMenu.addItem(item)
        }
        let starfieldDensityItem = NSMenuItem(title: "Density", action: nil, keyEquivalent: "")
        starfieldDensityItem.submenu = starfieldDensityMenu
        starfieldSettingsSubmenu.addItem(starfieldDensityItem)

        // Backdrop — layered cosmic background (each layer toggleable)
        starfieldSettingsSubmenu.addItem(NSMenuItem.separator())
        let starfieldBackdropItem = NSMenuItem(title: "Backdrop", action: nil, keyEquivalent: "")
        let starfieldBackdropMenu = NSMenu()

        let bgStarsToggle = NSMenuItem(title: "Background Stars", action: #selector(toggleStarfieldBackgroundStars), keyEquivalent: "")
        bgStarsToggle.state = Prefs.starfieldBackgroundStars ? .on : .off
        starfieldBackdropMenu.addItem(bgStarsToggle)

        let gradientToggle = NSMenuItem(title: "Deep Space Gradient", action: #selector(toggleStarfieldGradient), keyEquivalent: "")
        gradientToggle.state = Prefs.starfieldGradient ? .on : .off
        starfieldBackdropMenu.addItem(gradientToggle)

        let galaxiesToggle = NSMenuItem(title: "Distant Galaxies", action: #selector(toggleStarfieldGalaxies), keyEquivalent: "")
        galaxiesToggle.state = Prefs.starfieldGalaxies ? .on : .off
        starfieldBackdropMenu.addItem(galaxiesToggle)

        let nebulaeToggle = NSMenuItem(title: "Nebula Clouds", action: #selector(toggleStarfieldNebulae), keyEquivalent: "")
        nebulaeToggle.state = Prefs.starfieldNebulae ? .on : .off
        starfieldBackdropMenu.addItem(nebulaeToggle)

        // Planets submenu with Show toggle + count override
        starfieldBackdropMenu.addItem(NSMenuItem.separator())
        let planetsItem = NSMenuItem(title: "Planets", action: nil, keyEquivalent: "")
        let planetsMenu = NSMenu()

        let planetsShowToggle = NSMenuItem(title: "Show Planets", action: #selector(toggleStarfieldPlanets), keyEquivalent: "")
        planetsShowToggle.state = Prefs.starfieldPlanets ? .on : .off
        planetsMenu.addItem(planetsShowToggle)

        planetsMenu.addItem(NSMenuItem.separator())

        let countOptions: [(String, String)] = [
            ("Random (0–3)", "random"),
            ("None",         "0"),
            ("1 Planet",     "1"),
            ("2 Planets",    "2"),
            ("3 Planets",    "3"),
        ]
        for (label, value) in countOptions {
            let item = NSMenuItem(title: label, action: #selector(setStarfieldPlanetsCount(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.starfieldPlanetsCount == value ? .on : .off
            planetsMenu.addItem(item)
        }

        planetsItem.submenu = planetsMenu
        starfieldBackdropMenu.addItem(planetsItem)

        starfieldBackdropItem.submenu = starfieldBackdropMenu
        starfieldSettingsSubmenu.addItem(starfieldBackdropItem)

        starfieldSettingsItem.submenu = starfieldSettingsSubmenu
        starfieldSubmenu.addItem(starfieldSettingsItem)

        starfieldSubmenu.addItem(NSMenuItem.separator())

        // Screen selection for Starfield Warp
        addScreenItems(to: starfieldSubmenu, file: AppDelegate.starfieldWarpSentinel, builtIn: builtIn, externals: externals)

        starfieldItem.submenu = starfieldSubmenu
        menu.addItem(starfieldItem)

        // Break Reminder
        menu.addItem(NSMenuItem.separator())
        let breakItem = NSMenuItem(title: "Break Reminder", action: nil, keyEquivalent: "")
        let breakSubmenu = NSMenu(title: "Break Reminder")

        // Session stats
        let todayItem = NSMenuItem(title: "Today: \(Prefs.breaksTakenToday) break\(Prefs.breaksTakenToday == 1 ? "" : "s")", action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        breakSubmenu.addItem(todayItem)
        let totalItem = NSMenuItem(title: "Total: \(Prefs.totalBreaksTaken) break\(Prefs.totalBreaksTaken == 1 ? "" : "s")", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        breakSubmenu.addItem(totalItem)
        breakSubmenu.addItem(NSMenuItem.separator())

        if let endDate = breakEndDate {
            let remaining = max(0, Int(endDate.timeIntervalSinceNow))
            let mins = remaining / 60
            let secs = remaining % 60
            let phase = pomodoroActive ? (pomodoroOnBreak ? "Break" : "Work") : "Break in"
            let countdownItem = NSMenuItem(title: String(format: "  %@ %d:%02d", phase, mins, secs), action: nil, keyEquivalent: "")
            countdownItem.isEnabled = false
            breakSubmenu.addItem(countdownItem)
            if pomodoroActive {
                let stopItem = NSMenuItem(title: "Stop Pomodoro", action: #selector(stopPomodoro), keyEquivalent: "")
                breakSubmenu.addItem(stopItem)
            }
            let cancelItem = NSMenuItem(title: "Cancel Timer", action: #selector(cancelBreakTimer), keyEquivalent: "")
            breakSubmenu.addItem(cancelItem)
        } else {
            for minutes in [60, 45, 30, 15] {
                let item = NSMenuItem(title: "Start \(minutes) min", action: #selector(startBreakTimer(_:)), keyEquivalent: "")
                item.representedObject = minutes as AnyObject
                breakSubmenu.addItem(item)
            }
            let customItem = NSMenuItem(title: "Custom...", action: #selector(startCustomBreakTimer), keyEquivalent: "")
            breakSubmenu.addItem(customItem)

            // Custom presets
            let presets = Prefs.customPresets
            if !presets.isEmpty {
                breakSubmenu.addItem(NSMenuItem.separator())
                for mins in presets {
                    let item = NSMenuItem(title: "Start \(mins) min \u{2605}", action: #selector(startBreakTimer(_:)), keyEquivalent: "")
                    item.representedObject = mins as AnyObject
                    breakSubmenu.addItem(item)
                }
            }

            // Manage Presets
            let presetsItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
            let presetsSubmenu = NSMenu(title: "Presets")
            let saveItem = NSMenuItem(title: "Save Current (\(Prefs.breakDuration) min)", action: #selector(saveCurrentPreset), keyEquivalent: "")
            presetsSubmenu.addItem(saveItem)
            if !presets.isEmpty {
                let clearItem = NSMenuItem(title: "Clear All Presets", action: #selector(clearPresets), keyEquivalent: "")
                presetsSubmenu.addItem(clearItem)
            }
            presetsItem.submenu = presetsSubmenu
            breakSubmenu.addItem(presetsItem)
        }

        // Pomodoro
        breakSubmenu.addItem(NSMenuItem.separator())
        let pomoItem = NSMenuItem(title: "Pomodoro", action: nil, keyEquivalent: "")
        let pomoSubmenu = NSMenu(title: "Pomodoro")
        if pomodoroActive {
            let stopPomo = NSMenuItem(title: "Stop Pomodoro", action: #selector(stopPomodoro), keyEquivalent: "")
            pomoSubmenu.addItem(stopPomo)
        } else {
            let startPomo = NSMenuItem(title: "Start Pomodoro", action: #selector(startPomodoro), keyEquivalent: "")
            pomoSubmenu.addItem(startPomo)
        }
        pomoSubmenu.addItem(NSMenuItem.separator())
        let workItem = NSMenuItem(title: "Work: \(Prefs.pomodoroWork) min", action: nil, keyEquivalent: "")
        let workSubmenu = NSMenu(title: "Work Duration")
        for mins in [15, 20, 25, 30, 45, 50] {
            let item = NSMenuItem(title: "\(mins) min", action: #selector(setPomodoroWork(_:)), keyEquivalent: "")
            item.representedObject = mins as AnyObject
            item.state = Prefs.pomodoroWork == mins ? .on : .off
            workSubmenu.addItem(item)
        }
        workItem.submenu = workSubmenu
        pomoSubmenu.addItem(workItem)
        let breakDurItem = NSMenuItem(title: "Break: \(Prefs.pomodoroBreak) min", action: nil, keyEquivalent: "")
        let breakDurSubmenu = NSMenu(title: "Break Duration")
        for mins in [3, 5, 10, 15] {
            let item = NSMenuItem(title: "\(mins) min", action: #selector(setPomodoroBreak(_:)), keyEquivalent: "")
            item.representedObject = mins as AnyObject
            item.state = Prefs.pomodoroBreak == mins ? .on : .off
            breakDurSubmenu.addItem(item)
        }
        breakDurItem.submenu = breakDurSubmenu
        pomoSubmenu.addItem(breakDurItem)
        pomoItem.submenu = pomoSubmenu
        breakSubmenu.addItem(pomoItem)

        // Sound settings
        breakSubmenu.addItem(NSMenuItem.separator())
        let breakSoundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        let breakSoundSubmenu = NSMenu(title: "Sound")
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleBreakSound), keyEquivalent: "")
        enabledItem.state = Prefs.breakSoundEnabled ? .on : .off
        breakSoundSubmenu.addItem(enabledItem)
        breakSoundSubmenu.addItem(NSMenuItem.separator())
        for name in ["Glass", "Hero", "Ping", "Pop", "Purr", "Submarine"] {
            let item = NSMenuItem(title: name, action: #selector(setBreakSound(_:)), keyEquivalent: "")
            item.representedObject = name as AnyObject
            item.state = Prefs.breakSoundName == name ? .on : .off
            item.isEnabled = Prefs.breakSoundEnabled
            breakSoundSubmenu.addItem(item)
        }
        breakSoundItem.submenu = breakSoundSubmenu
        breakSubmenu.addItem(breakSoundItem)

        let breakScreenItem = NSMenuItem(title: "Break Screen", action: #selector(toggleBreakScreen), keyEquivalent: "")
        breakScreenItem.state = Prefs.breakScreenEnabled ? .on : .off
        breakSubmenu.addItem(breakScreenItem)

        let resumeItem = NSMenuItem(title: "Resume Playback After Break", action: #selector(toggleResumeAfterBreak), keyEquivalent: "")
        resumeItem.state = Prefs.resumeAfterBreak ? .on : .off
        breakSubmenu.addItem(resumeItem)

        // Countdown overlay settings
        breakSubmenu.addItem(NSMenuItem.separator())

        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displaySubmenu = NSMenu(title: "Display")
        for (label, value) in [("All Screens", "all"), ("Built-in", "builtin"), ("External", "external")] {
            let item = NSMenuItem(title: label, action: #selector(setCountdownScreen(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.countdownScreen == value ? .on : .off
            displaySubmenu.addItem(item)
        }
        displayItem.submenu = displaySubmenu
        breakSubmenu.addItem(displayItem)

        let posItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let posSubmenu = NSMenu(title: "Position")
        for (label, value) in [("Top Right", "topRight"), ("Top Left", "topLeft"), ("Bottom Right", "bottomRight"), ("Bottom Left", "bottomLeft")] {
            let item = NSMenuItem(title: label, action: #selector(setCountdownPosition(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.countdownPosition == value ? .on : .off
            posSubmenu.addItem(item)
        }
        posItem.submenu = posSubmenu
        breakSubmenu.addItem(posItem)

        // Style settings
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let styleSubmenu = NSMenu(title: "Style")
        let overlayColorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let overlayColorSubmenu = NSMenu(title: "Color")
        for name in ["Green", "Blue", "Red", "Orange", "White", "Purple"] {
            let item = NSMenuItem(title: name, action: #selector(setCountdownColor(_:)), keyEquivalent: "")
            item.representedObject = name as AnyObject
            item.state = Prefs.countdownColor == name ? .on : .off
            overlayColorSubmenu.addItem(item)
        }
        overlayColorItem.submenu = overlayColorSubmenu
        styleSubmenu.addItem(overlayColorItem)
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeSubmenu = NSMenu(title: "Size")
        for name in ["Compact", "Normal", "Large"] {
            let item = NSMenuItem(title: name, action: #selector(setCountdownSize(_:)), keyEquivalent: "")
            item.representedObject = name as AnyObject
            item.state = Prefs.countdownSize == name ? .on : .off
            sizeSubmenu.addItem(item)
        }
        sizeItem.submenu = sizeSubmenu
        styleSubmenu.addItem(sizeItem)
        styleItem.submenu = styleSubmenu
        breakSubmenu.addItem(styleItem)

        breakItem.submenu = breakSubmenu
        menu.addItem(breakItem)

        // Clock overlay submenu (top level, between Break Reminder and Lock Screen)
        let clockItem = NSMenuItem(title: "Clock", action: nil, keyEquivalent: "")
        let clockSubmenu = NSMenu(title: "Clock")

        let clockToggle = NSMenuItem(title: "Show Clock", action: #selector(toggleClockOverlay), keyEquivalent: "")
        clockToggle.state = !clockWindows.isEmpty ? .on : .off
        clockSubmenu.addItem(clockToggle)

        let clockDateToggle = NSMenuItem(title: "Show Date", action: #selector(toggleClockDate), keyEquivalent: "")
        clockDateToggle.state = Prefs.clockShowDate ? .on : .off
        clockSubmenu.addItem(clockDateToggle)

        clockSubmenu.addItem(NSMenuItem.separator())

        // Clock Display
        let clockDisplayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let clockDisplaySubmenu = NSMenu(title: "Display")
        for (label, value) in [("All Screens", "all"), ("Built-in", "builtin"), ("External", "external")] {
            let item = NSMenuItem(title: label, action: #selector(setClockScreen(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.clockScreen == value ? .on : .off
            clockDisplaySubmenu.addItem(item)
        }
        clockDisplayItem.submenu = clockDisplaySubmenu
        clockSubmenu.addItem(clockDisplayItem)

        // Clock Position
        let clockPositionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let clockPositionSubmenu = NSMenu(title: "Position")
        for (label, value) in [("Top Right", "topRight"), ("Top Left", "topLeft"), ("Bottom Right", "bottomRight"), ("Bottom Left", "bottomLeft")] {
            let item = NSMenuItem(title: label, action: #selector(setClockPosition(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.clockPosition == value ? .on : .off
            clockPositionSubmenu.addItem(item)
        }
        clockPositionItem.submenu = clockPositionSubmenu
        clockSubmenu.addItem(clockPositionItem)

        // Clock Color
        let clockColorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let clockColorSubmenu = NSMenu(title: "Color")
        for color in ["Green", "Blue", "Red", "Orange", "White", "Purple"] {
            let item = NSMenuItem(title: color, action: #selector(setClockColor(_:)), keyEquivalent: "")
            item.representedObject = color as AnyObject
            item.state = Prefs.clockColor == color ? .on : .off
            clockColorSubmenu.addItem(item)
        }
        clockColorItem.submenu = clockColorSubmenu
        clockSubmenu.addItem(clockColorItem)

        // Clock Size
        let clockSizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let clockSizeSubmenu = NSMenu(title: "Size")
        for size in ["Compact", "Normal", "Large"] {
            let item = NSMenuItem(title: size, action: #selector(setClockSize(_:)), keyEquivalent: "")
            item.representedObject = size as AnyObject
            item.state = Prefs.clockSize == size ? .on : .off
            clockSizeSubmenu.addItem(item)
        }
        clockSizeItem.submenu = clockSizeSubmenu
        clockSubmenu.addItem(clockSizeItem)

        clockItem.submenu = clockSubmenu
        menu.addItem(clockItem)

        menu.addItem(NSMenuItem.separator())

        // Lock Screen
        let lockItem = NSMenuItem(title: "Lock Screen", action: nil, keyEquivalent: "")
        let lockSubmenu = NSMenu(title: "Lock Screen")

        let lockNowItem = NSMenuItem(title: "Lock Now", action: #selector(lockScreenNow), keyEquivalent: "L")
        lockNowItem.keyEquivalentModifierMask = [.command, .shift]
        lockNowItem.isEnabled = Prefs.hasLockPassword
        lockSubmenu.addItem(lockNowItem)

        lockSubmenu.addItem(NSMenuItem.separator())

        let setPassTitle = Prefs.hasLockPassword ? "Change Password..." : "Set Password..."
        let setPassItem = NSMenuItem(title: setPassTitle, action: #selector(showSetPasswordDialog), keyEquivalent: "")
        lockSubmenu.addItem(setPassItem)

        if Prefs.hasLockPassword {
            let clearItem = NSMenuItem(title: "Clear Password", action: #selector(clearLockPasswordAction), keyEquivalent: "")
            lockSubmenu.addItem(clearItem)
        }

        lockItem.submenu = lockSubmenu
        menu.addItem(lockItem)

        // Sleep (between Lock Screen and Contribute)
        menu.addItem(NSMenuItem.separator())
        let sleepItem = NSMenuItem(title: "Sleep", action: nil, keyEquivalent: "")
        let sleepSubmenu = NSMenu(title: "Sleep")

        if let endDate = sleepEndDate {
            let remaining = max(0, Int(endDate.timeIntervalSinceNow))
            let mins = remaining / 60
            let secs = remaining % 60
            let countdownItem = NSMenuItem(title: String(format: "  Sleep in %d:%02d", mins, secs), action: nil, keyEquivalent: "")
            countdownItem.isEnabled = false
            sleepSubmenu.addItem(countdownItem)
            let cancelItem = NSMenuItem(title: "Cancel Sleep Timer", action: #selector(cancelSleepTimer), keyEquivalent: "")
            sleepSubmenu.addItem(cancelItem)
        } else {
            let sleepNowItem = NSMenuItem(title: "Sleep Now", action: #selector(sleepNow), keyEquivalent: "")
            sleepSubmenu.addItem(sleepNowItem)

            sleepSubmenu.addItem(NSMenuItem.separator())

            for minutes in [90, 60, 45, 30, 15] {
                let item = NSMenuItem(title: "Sleep in \(minutes) min", action: #selector(startSleepTimer(_:)), keyEquivalent: "")
                item.representedObject = minutes as AnyObject
                sleepSubmenu.addItem(item)
            }
            let customSleepItem = NSMenuItem(title: "Custom...", action: #selector(startCustomSleepTimer), keyEquivalent: "")
            sleepSubmenu.addItem(customSleepItem)
        }

        sleepSubmenu.addItem(NSMenuItem.separator())
        let sleepAfterItem = NSMenuItem(title: "Sleep After Playback", action: #selector(toggleSleepAfterPlayback), keyEquivalent: "")
        sleepAfterItem.state = sleepAfterPlayback ? .on : .off
        sleepAfterItem.isEnabled = isPlaying || sleepAfterPlayback
        sleepSubmenu.addItem(sleepAfterItem)

        let sleepCountdownItem = NSMenuItem(title: "Countdown Overlay", action: #selector(toggleSleepCountdown), keyEquivalent: "")
        sleepCountdownItem.state = Prefs.sleepCountdownEnabled ? .on : .off
        sleepSubmenu.addItem(sleepCountdownItem)

        let resumeAfterSleepItem = NSMenuItem(title: "Resume Playback After Wake", action: #selector(toggleResumeAfterSleep), keyEquivalent: "")
        resumeAfterSleepItem.state = Prefs.resumeAfterSleep ? .on : .off
        sleepSubmenu.addItem(resumeAfterSleepItem)

        sleepItem.submenu = sleepSubmenu
        menu.addItem(sleepItem)

        // Playback / App config toggles (moved to bottom for cleaner feature-first layout)
        menu.addItem(NSMenuItem.separator())

        // Sound toggle
        let soundItem = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.state = Prefs.soundEnabled ? .on : .off
        menu.addItem(soundItem)

        // Volume slider
        let volumeView = SliderMenuView(title: "Volume", minValue: 0, maxValue: 1, currentValue: Double(Prefs.volume)) { newVal in
            Prefs.volume = newVal
            // Update any currently playing video players
            for cv in self.contentViews {
                if let vp = cv as? VideoPlayerView {
                    vp.queuePlayer.volume = newVal
                }
            }
        }
        let volumeMenuItem = NSMenuItem()
        volumeMenuItem.view = volumeView
        menu.addItem(volumeMenuItem)

        // Opacity slider (ambient mode)
        let opacityView = SliderMenuView(title: "Opacity", minValue: 0.1, maxValue: 1, currentValue: Double(Prefs.ambientOpacity)) { newVal in
            Prefs.ambientOpacity = newVal
            if self.currentMode == .ambient {
                for w in self.screensaverWindows {
                    w.alphaValue = CGFloat(newVal)
                }
            }
        }
        let opacityMenuItem = NSMenuItem()
        opacityMenuItem.view = opacityView
        menu.addItem(opacityMenuItem)

        // Loop toggle
        let loopItem = NSMenuItem(title: "Loop", action: #selector(toggleLoop), keyEquivalent: "")
        loopItem.state = Prefs.loopEnabled ? .on : .off
        menu.addItem(loopItem)

        // Auto Play toggle
        let autoPlayItem = NSMenuItem(title: "Auto Play on Launch", action: #selector(toggleAutoPlay), keyEquivalent: "")
        autoPlayItem.state = Prefs.autoPlayEnabled ? .on : .off
        menu.addItem(autoPlayItem)

        // Launch at login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = Prefs.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        // Show in Dock
        let dockItem = NSMenuItem(title: "Show in Dock", action: #selector(toggleDockIcon), keyEquivalent: "")
        dockItem.state = Prefs.showDockIcon ? .on : .off
        menu.addItem(dockItem)

        // Desktop Shortcut
        let desktopItem = NSMenuItem(title: "Desktop Shortcut", action: #selector(toggleDesktopShortcut), keyEquivalent: "")
        desktopItem.state = Prefs.showDesktopShortcut ? .on : .off
        menu.addItem(desktopItem)

        // Contribute
        menu.addItem(NSMenuItem.separator())
        let contributeItem = NSMenuItem(title: "Contribute", action: nil, keyEquivalent: "")
        let contributeSubmenu = NSMenu(title: "Contribute")
        let coffeeItem = NSMenuItem(title: "☕  Buy Me a Coffee", action: #selector(openBuyMeACoffee), keyEquivalent: "")
        contributeSubmenu.addItem(coffeeItem)
        let hodlItem = NSMenuItem(title: "🪙  Hodl H3LLCOIN", action: #selector(openH3llcoin), keyEquivalent: "")
        contributeSubmenu.addItem(hodlItem)
        contributeItem.submenu = contributeSubmenu
        menu.addItem(contributeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    // MARK: - Settings actions

    @objc func toggleSound() {
        Prefs.soundEnabled = !Prefs.soundEnabled
        for cv in contentViews {
            if let vp = cv as? VideoPlayerView {
                vp.queuePlayer.isMuted = !Prefs.soundEnabled
            }
        }
    }

    @objc func toggleLoop() {
        Prefs.loopEnabled = !Prefs.loopEnabled
    }

    @objc func toggleAutoPlay() {
        Prefs.autoPlayEnabled = !Prefs.autoPlayEnabled
    }

    @objc func toggleLaunchAtLogin() {
        Prefs.launchAtLogin = !Prefs.launchAtLogin
        if #available(macOS 13.0, *) {
            do {
                if Prefs.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user can retry
                Prefs.launchAtLogin = !Prefs.launchAtLogin
            }
        }
    }

    @objc func toggleDockIcon() {
        Prefs.showDockIcon = !Prefs.showDockIcon
        NSApp.setActivationPolicy(Prefs.showDockIcon ? .regular : .accessory)
    }

    @objc func toggleDesktopShortcut() {
        Prefs.showDesktopShortcut = !Prefs.showDesktopShortcut
        syncDesktopShortcut()
    }

    func syncDesktopShortcut() {
        let desktop = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        let shortcutPath = (desktop as NSString).appendingPathComponent("HollywoodSaver.app")
        let fm = FileManager.default

        if Prefs.showDesktopShortcut {
            // Create symbolic link to .app on Desktop
            if !fm.fileExists(atPath: shortcutPath) {
                let appPath = Bundle.main.bundlePath
                try? fm.createSymbolicLink(atPath: shortcutPath, withDestinationPath: appPath)
            }
        } else {
            // Remove shortcut if it exists and is a symlink
            if fm.fileExists(atPath: shortcutPath) {
                if let attrs = try? fm.attributesOfItem(atPath: shortcutPath),
                   attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                    try? fm.removeItem(atPath: shortcutPath)
                }
            }
        }
    }

    // MARK: - Sleep

    func putMacToSleep() {
        // Save playback state for resume after wake
        if isPlaying {
            savedMediaBeforeSleep = currentMediaPath
            savedModeBeforeSleep = currentMode
        }
        stopPlaying()
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    @objc func sleepNow() {
        putMacToSleep()
    }

    @objc func startSleepTimer(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        startSleepWithMinutes(minutes)
    }

    @objc func startCustomSleepTimer() {
        let alert = NSAlert()
        alert.messageText = "Sleep Timer"
        alert.informativeText = "Enter minutes until sleep:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        input.stringValue = "30"
        alert.accessoryView = input
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let mins = Int(input.stringValue), mins > 0, mins <= 1440 {
                startSleepWithMinutes(mins)
            }
        }
    }

    func startSleepWithMinutes(_ minutes: Int) {
        cancelSleepTimer()
        sleepEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        showSleepCountdownOverlay()

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self, let endDate = self.sleepEndDate else {
                timer.invalidate()
                return
            }
            let remaining = Int(endDate.timeIntervalSinceNow)
            if remaining <= 0 {
                timer.invalidate()
                self.sleepTimer = nil
                self.sleepEndDate = nil
                self.hideSleepCountdownOverlay()
                self.putMacToSleep()
            } else {
                self.updateSleepCountdownOverlay()
                if remaining == 300 {
                    self.sendBreakNotification(title: "Sleep Timer", body: "Mac will sleep in 5 minutes")
                } else if remaining == 60 {
                    self.sendBreakNotification(title: "Sleep Timer", body: "Mac will sleep in 1 minute")
                }
            }
        }
    }

    @objc func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEndDate = nil
        sleepAfterPlayback = false
        hideSleepCountdownOverlay()
    }

    @objc func toggleSleepAfterPlayback() {
        sleepAfterPlayback = !sleepAfterPlayback
    }

    @objc func toggleResumeAfterSleep() {
        Prefs.resumeAfterSleep = !Prefs.resumeAfterSleep
    }

    @objc func toggleSleepCountdown() {
        Prefs.sleepCountdownEnabled = !Prefs.sleepCountdownEnabled
        if Prefs.sleepCountdownEnabled && sleepEndDate != nil {
            showSleepCountdownOverlay()
        } else {
            hideSleepCountdownOverlay()
        }
    }

    func showSleepCountdownOverlay() {
        hideSleepCountdownOverlay()
        guard Prefs.sleepCountdownEnabled else { return }

        let sizeConfig = countdownSizeConfig()
        let size = CGSize(width: sizeConfig.width, height: sizeConfig.height)
        let padding: CGFloat = 20
        let sleepColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)

        for screen in targetScreens(for: Prefs.countdownScreen) {
            // Sleep countdown goes in the opposite corner from break countdown
            let origin: NSPoint
            switch Prefs.countdownPosition {
            case "topLeft":
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.minY + padding)
            case "bottomRight":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.maxY - size.height - padding - 25)
            case "bottomLeft":
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.maxY - size.height - padding - 25)
            default: // topRight — sleep goes to bottomLeft
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.minY + padding)
            }

            let overlay = CountdownOverlayView(frame: NSRect(origin: .zero, size: size), fontSize: sizeConfig.fontSize, color: sleepColor)
            let window = createFloatingOverlayWindow(rect: NSRect(origin: origin, size: size), content: overlay)
            window.orderFrontRegardless()
            sleepCountdownWindows.append(window)
        }

        updateSleepCountdownOverlay()
    }

    func hideSleepCountdownOverlay() {
        for window in sleepCountdownWindows {
            window.orderOut(nil)
        }
        sleepCountdownWindows.removeAll()
    }

    func updateSleepCountdownOverlay() {
        guard let endDate = sleepEndDate else {
            hideSleepCountdownOverlay()
            return
        }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow))
        for window in sleepCountdownWindows {
            (window.contentView as? CountdownOverlayView)?.update(remaining: remaining, subtitle: "Sleep in")
        }
    }

    @objc func openBuyMeACoffee() {
        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/davidtkeane")!)
    }

    @objc func openH3llcoin() {
        NSWorkspace.shared.open(URL(string: "https://h3llcoin.com/how-to-buy.html")!)
    }

    // MARK: - Version Checker

    @objc func manualCheckForUpdate() {
        checkForUpdates(forceRefresh: true)
        // Show result after a short delay for the network request
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            if let latest = self.latestVersion, self.isNewerVersion(latest, than: AppDelegate.appVersion) {
                self.showUpdateDialog()
            } else {
                let alert = NSAlert()
                alert.messageText = "You're Up to Date"
                alert.informativeText = "HollywoodSaver v\(AppDelegate.appVersion) is the latest version."
                alert.alertStyle = .informational
                alert.runModal()
            }
        }
    }

    func checkForUpdates(forceRefresh: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !forceRefresh && now - Prefs.lastVersionCheckDate < 3600 {
            latestVersion = Prefs.cachedLatestVersion
            return
        }

        // Use Releases API (secure: provides pre-built assets with checksums)
        let urlString = "https://api.github.com/repos/\(AppDelegate.githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            // Fallback to tags API if releases URL fails
            checkForUpdatesFallback()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                // Fallback to tags API on network error
                DispatchQueue.main.async { self.checkForUpdatesFallback() }
                return
            }

            // Try parsing as a single release object
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                // No releases found — fallback to tags
                DispatchQueue.main.async { self.checkForUpdatesFallback() }
                return
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // Parse release assets for .app.zip and .sha256
            var zipURL: String?
            var checksumURL: String?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    guard let name = asset["name"] as? String,
                          let downloadURL = asset["browser_download_url"] as? String else { continue }
                    if name.hasSuffix(".app.zip") { zipURL = downloadURL }
                    if name.hasSuffix(".sha256") { checksumURL = downloadURL }
                }
            }

            DispatchQueue.main.async {
                self.latestVersion = remoteVersion
                self.latestReleaseZipURL = zipURL
                self.latestReleaseChecksumURL = checksumURL
                Prefs.cachedLatestVersion = remoteVersion
                Prefs.lastVersionCheckDate = Date().timeIntervalSince1970

                // Send notification if newer version found (once per version)
                if self.isNewerVersion(remoteVersion, than: AppDelegate.appVersion) {
                    if Prefs.lastNotifiedVersion != remoteVersion {
                        Prefs.lastNotifiedVersion = remoteVersion
                        self.sendBreakNotification(
                            title: "HollywoodSaver Update Available",
                            body: "v\(AppDelegate.appVersion) → v\(remoteVersion) — Click the menu bar icon to update."
                        )
                    }
                }
            }
        }.resume()
    }

    // Fallback: use Tags API when no GitHub Releases exist yet
    func checkForUpdatesFallback() {
        let urlString = "https://api.github.com/repos/\(AppDelegate.githubRepo)/tags"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let firstTag = json.first,
                  let tagName = firstTag["name"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            DispatchQueue.main.async {
                self.latestVersion = remoteVersion
                self.latestReleaseZipURL = nil
                self.latestReleaseChecksumURL = nil
                Prefs.cachedLatestVersion = remoteVersion
                Prefs.lastVersionCheckDate = Date().timeIntervalSince1970

                if self.isNewerVersion(remoteVersion, than: AppDelegate.appVersion) {
                    if Prefs.lastNotifiedVersion != remoteVersion {
                        Prefs.lastNotifiedVersion = remoteVersion
                        self.sendBreakNotification(
                            title: "HollywoodSaver Update Available",
                            body: "v\(AppDelegate.appVersion) → v\(remoteVersion) — Click the menu bar icon to update."
                        )
                    }
                }
            }
        }.resume()
    }

    func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(remoteParts.count, localParts.count)
        for i in 0..<maxLen {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    @objc func showUpdateDialog() {
        let latest = latestVersion ?? "unknown"
        let alert = NSAlert()
        alert.messageText = "Update Available"

        let hasRelease = latestReleaseZipURL != nil && latestReleaseChecksumURL != nil

        if hasRelease {
            alert.informativeText = """
            Current version: v\(AppDelegate.appVersion)
            Latest version: v\(latest)

            Click "Auto Update" to download and install the new version.
            The update is verified with a SHA-256 checksum for security.

            Or visit the GitHub Releases page to download manually.
            """
        } else {
            alert.informativeText = """
            Current version: v\(AppDelegate.appVersion)
            Latest version: v\(latest)

            Download the latest version from GitHub Releases:
            https://github.com/\(AppDelegate.githubRepo)/releases

            Or update from source:
            cd \(appFolder) && git pull && bash build.sh
            """
        }
        alert.alertStyle = .informational

        if hasRelease {
            alert.addButton(withTitle: "Auto Update")
        }
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if hasRelease && response == .alertFirstButtonReturn {
            performAutoUpdate()
        } else if (!hasRelease && response == .alertFirstButtonReturn) || (hasRelease && response == .alertSecondButtonReturn) {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(AppDelegate.githubRepo)/releases")!)
        }
    }

    @objc func performAutoUpdate() {
        guard let zipURL = latestReleaseZipURL,
              let checksumURL = latestReleaseChecksumURL else { return }
        let currentVersion = AppDelegate.appVersion
        let latest = latestVersion ?? "unknown"

        let script = """
        #!/bin/bash
        set -e
        cd "\(appFolder)"

        echo ""
        echo "========================================="
        echo "  HollywoodSaver Auto-Update"
        echo "  v\(currentVersion) → v\(latest)"
        echo "========================================="
        echo ""

        # Download release
        echo "Downloading HollywoodSaver v\(latest)..."
        curl -L -o /tmp/HollywoodSaver.app.zip "\(zipURL)"
        curl -L -o /tmp/HollywoodSaver.app.zip.sha256 "\(checksumURL)"

        # Verify checksum
        echo ""
        echo "Verifying SHA-256 checksum..."
        EXPECTED=$(cat /tmp/HollywoodSaver.app.zip.sha256 | awk '{print $1}')
        ACTUAL=$(shasum -a 256 /tmp/HollywoodSaver.app.zip | awk '{print $1}')

        if [ "$EXPECTED" != "$ACTUAL" ]; then
            echo ""
            echo "╔══════════════════════════════════════╗"
            echo "║  CHECKSUM MISMATCH — UPDATE ABORTED  ║"
            echo "╚══════════════════════════════════════╝"
            echo ""
            echo "Expected: $EXPECTED"
            echo "Actual:   $ACTUAL"
            echo ""
            echo "The download may be corrupted or tampered with."
            echo "Please download manually from GitHub Releases."
            echo ""
            rm -f /tmp/HollywoodSaver.app.zip /tmp/HollywoodSaver.app.zip.sha256
            echo "Press Enter to close."
            read
            exit 1
        fi
        echo "Checksum verified ✓"

        # Backup current app
        if [ -d "HollywoodSaver.app" ]; then
            BACKUP_NAME="HollywoodSaver-v\(currentVersion).app"
            if [ -d "$BACKUP_NAME" ]; then
                rm -rf "$BACKUP_NAME"
            fi
            cp -R "HollywoodSaver.app" "$BACKUP_NAME"
            echo "Backed up to $BACKUP_NAME"
        fi

        # Install new version
        echo "Installing v\(latest)..."
        unzip -o /tmp/HollywoodSaver.app.zip -d .
        rm -f /tmp/HollywoodSaver.app.zip /tmp/HollywoodSaver.app.zip.sha256

        # Clear version cache
        defaults delete com.rangersmyth.hollywoodsaver lastVersionCheckDate 2>/dev/null || true
        defaults delete com.rangersmyth.hollywoodsaver cachedLatestVersion 2>/dev/null || true
        defaults delete com.rangersmyth.hollywoodsaver lastNotifiedVersion 2>/dev/null || true

        echo ""
        echo "========================================="
        echo "  Update complete! Launching v\(latest)..."
        echo "========================================="
        echo ""
        open "HollywoodSaver.app"
        """

        let tempScript = NSTemporaryDirectory() + "hollywoodsaver_update.sh"
        do {
            try script.write(toFile: tempScript, atomically: true, encoding: .utf8)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", tempScript]
            try chmod.run()
            chmod.waitUntilExit()

            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-a", "Terminal", tempScript]
            try open.run()
            open.waitUntilExit()

            if open.terminationStatus == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    NSApp.terminate(nil)
                }
            } else {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Update Failed"
                errorAlert.informativeText = "Could not open Terminal.\n\nPlease download manually from:\nhttps://github.com/\(AppDelegate.githubRepo)/releases"
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Update Failed"
            errorAlert.informativeText = "Could not start the update process: \(error.localizedDescription)\n\nPlease download manually from:\nhttps://github.com/\(AppDelegate.githubRepo)/releases"
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }

    // MARK: - Matrix Rain settings actions

    @objc func setMatrixColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixColorTheme = value
    }

    @objc func setMatrixSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixSpeed = value
    }

    @objc func setMatrixCharSet(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixCharacterSet = value
    }

    @objc func setMatrixDensity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixDensity = value
    }

    @objc func setMatrixFontSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixFontSize = value
    }

    @objc func setMatrixTrailLength(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixTrailLength = value
    }

    @objc func playMatrixRainAllScreens() {
        startPlaying(media: AppDelegate.matrixRainSentinel, on: NSScreen.screens, mode: .screensaver)
    }

    // MARK: - Starfield Warp settings actions

    @objc func setStarfieldSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.starfieldSpeed = value
    }

    @objc func setStarfieldColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.starfieldColor = value
    }

    @objc func setStarfieldDensity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.starfieldDensity = value
    }

    @objc func playStarfieldWarpAllScreens() {
        startPlaying(media: AppDelegate.starfieldWarpSentinel, on: NSScreen.screens, mode: .screensaver)
    }

    @objc func toggleStarfieldBackgroundStars() {
        Prefs.starfieldBackgroundStars = !Prefs.starfieldBackgroundStars
    }

    @objc func toggleStarfieldGradient() {
        Prefs.starfieldGradient = !Prefs.starfieldGradient
    }

    @objc func toggleStarfieldGalaxies() {
        Prefs.starfieldGalaxies = !Prefs.starfieldGalaxies
    }

    @objc func toggleStarfieldNebulae() {
        Prefs.starfieldNebulae = !Prefs.starfieldNebulae
    }

    @objc func toggleStarfieldPlanets() {
        Prefs.starfieldPlanets = !Prefs.starfieldPlanets
    }

    @objc func setStarfieldPlanetsCount(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.starfieldPlanetsCount = value
    }

    // MARK: - Break Reminder

    @objc func startBreakTimer(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        startBreakWithMinutes(minutes)
    }

    @objc func startCustomBreakTimer() {
        let alert = NSAlert()
        alert.messageText = "Custom Break Timer"
        alert.informativeText = "Enter minutes:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        input.stringValue = "\(Prefs.breakDuration)"
        alert.accessoryView = input
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let mins = Int(input.stringValue), mins > 0, mins <= 1440 {
                startBreakWithMinutes(mins)
            }
        }
    }

    func startBreakWithMinutes(_ minutes: Int) {
        breakTimer?.invalidate()
        breakEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        Prefs.breakDuration = minutes

        // Warning at 5 minutes remaining
        if minutes > 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval((minutes - 5) * 60)) { [weak self] in
                guard self?.breakEndDate != nil else { return }
                self?.sendBreakNotification(title: "Break Reminder", body: "5 minutes until break time!")
            }
        }

        // Timer fires every 1s to update countdown overlay and fires the break screen at end
        breakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self, let endDate = self.breakEndDate else {
                timer.invalidate()
                return
            }
            self.updateCountdownOverlay()
            if Date() >= endDate {
                timer.invalidate()
                self.breakTimer = nil
                self.breakEndDate = nil
                self.showBreakScreen()
            }
        }

        showCountdownOverlay()
    }

    @objc func cancelBreakTimer() {
        breakTimer?.invalidate()
        breakTimer = nil
        breakEndDate = nil
        pomodoroActive = false
        pomodoroOnBreak = false
        hideCountdownOverlay()
    }

    @objc func saveCurrentPreset() {
        var presets = Prefs.customPresets
        let current = Prefs.breakDuration
        if !presets.contains(current) {
            presets.append(current)
            presets.sort(by: >)
            Prefs.customPresets = presets
        }
    }

    @objc func clearPresets() {
        Prefs.customPresets = []
    }

    @objc func toggleBreakSound() {
        Prefs.breakSoundEnabled = !Prefs.breakSoundEnabled
    }

    @objc func toggleBreakScreen() {
        Prefs.breakScreenEnabled = !Prefs.breakScreenEnabled
    }

    @objc func toggleResumeAfterBreak() {
        Prefs.resumeAfterBreak = !Prefs.resumeAfterBreak
    }

    @objc func setBreakSound(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.breakSoundName = value
        NSSound(named: NSSound.Name(value))?.play()
    }

    @objc func setCountdownColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.countdownColor = value
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
    }

    @objc func setCountdownSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.countdownSize = value
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
    }

    @objc func startPomodoro() {
        pomodoroActive = true
        pomodoroOnBreak = false
        startBreakWithMinutes(Prefs.pomodoroWork)
    }

    @objc func stopPomodoro() {
        pomodoroActive = false
        pomodoroOnBreak = false
        cancelBreakTimer()
    }

    @objc func setPomodoroWork(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        Prefs.pomodoroWork = value
    }

    @objc func setPomodoroBreak(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        Prefs.pomodoroBreak = value
    }

    // MARK: - Countdown Overlay

    func countdownNSColor() -> NSColor {
        switch Prefs.countdownColor {
        case "Blue": return NSColor(calibratedRed: 0.2, green: 0.6, blue: 1, alpha: 1)
        case "Red": return NSColor(calibratedRed: 1, green: 0.3, blue: 0.3, alpha: 1)
        case "Orange": return NSColor.orange
        case "White": return NSColor.white
        case "Purple": return NSColor(calibratedRed: 0.7, green: 0.4, blue: 1, alpha: 1)
        default: return NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 1)
        }
    }

    func countdownSizeConfig() -> (width: CGFloat, height: CGFloat, fontSize: CGFloat) {
        switch Prefs.countdownSize {
        case "Compact": return (140, 40, 20)
        case "Large": return (240, 65, 34)
        default: return (180, 50, 26)
        }
    }

    func showCountdownOverlay() {
        hideCountdownOverlay()

        let sizeConfig = countdownSizeConfig()
        let size = CGSize(width: sizeConfig.width, height: sizeConfig.height)
        let color = countdownNSColor()
        let padding: CGFloat = 20
        let menuBarHeight: CGFloat = 25

        for screen in targetScreens(for: Prefs.countdownScreen) {
            let origin: NSPoint
            switch Prefs.countdownPosition {
            case "topLeft":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.maxY - size.height - padding - menuBarHeight)
            case "bottomRight":
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.minY + padding)
            case "bottomLeft":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.minY + padding)
            default: // topRight
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.maxY - size.height - padding - menuBarHeight)
            }

            let overlay = CountdownOverlayView(frame: NSRect(origin: .zero, size: size), fontSize: sizeConfig.fontSize, color: color)
            let window = createFloatingOverlayWindow(rect: NSRect(origin: origin, size: size), content: overlay)
            window.orderFrontRegardless()
            countdownWindows.append(window)
        }

        updateCountdownOverlay()
    }

    func hideCountdownOverlay() {
        for window in countdownWindows {
            window.orderOut(nil)
        }
        countdownWindows.removeAll()
    }

    func updateCountdownOverlay() {
        guard let endDate = breakEndDate else {
            hideCountdownOverlay()
            return
        }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow))
        let subtitle = pomodoroActive ? (pomodoroOnBreak ? "Break" : "Work") : "Break in"
        for window in countdownWindows {
            (window.contentView as? CountdownOverlayView)?.update(remaining: remaining, subtitle: subtitle)
        }
    }

    @objc func setCountdownScreen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.countdownScreen = value
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
    }

    @objc func setCountdownPosition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.countdownPosition = value
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
    }

    func sendBreakNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    func showBreakScreen() {
        // Skip if lock screen is active
        guard !lockScreenActive else { return }

        // Save current playback state for resume after break
        if isPlaying {
            savedMediaBeforeBreak = currentMediaPath
            savedModeBeforeBreak = currentMode
            stopPlaying()
        }

        // Remove floating countdown overlay (break screen replaces it)
        hideCountdownOverlay()

        // Track break stats
        Prefs.breaksTakenToday += 1
        Prefs.totalBreaksTaken += 1

        // Play break sound
        if Prefs.breakSoundEnabled {
            NSSound(named: NSSound.Name(Prefs.breakSoundName))?.play()
        }

        // Send notification
        sendBreakNotification(title: "Time for a Break!", body: "You've been working hard. Step away for a few minutes.")

        // Skip fullscreen break screen if disabled (countdown-only mode)
        if !Prefs.breakScreenEnabled {
            // Still handle Pomodoro cycling via dismissBreakScreen
            if pomodoroActive {
                dismissBreakScreen()
            }
            return
        }

        // Create fullscreen break overlay on all screens
        for screen in NSScreen.screens {
            let window = ScreensaverWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
            window.hasShadow = false
            window.ignoresMouseEvents = false

            // Create the break message view
            let breakView = BreakReminderView(frame: screen.frame)
            window.contentView = breakView

            window.makeKeyAndOrderFront(nil)
            screensaverWindows.append(window)
        }

        // Set up input monitoring to dismiss on click/key/mouse
        if inputMonitor == nil {
            inputMonitor = InputMonitor { [weak self] in
                self?.dismissBreakScreen()
            }
        }
        inputMonitor?.start()

        // Auto-dismiss after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if !(self?.screensaverWindows.isEmpty ?? true) {
                self?.dismissBreakScreen()
            }
        }
    }

    func dismissBreakScreen() {
        inputMonitor?.stop()
        inputMonitor = nil
        for window in screensaverWindows {
            window.orderOut(nil)
        }
        screensaverWindows.removeAll()
        contentViews.removeAll()

        // Pomodoro auto-cycle
        if pomodoroActive {
            if pomodoroOnBreak {
                // Break phase done → start work phase
                pomodoroOnBreak = false
                startBreakWithMinutes(Prefs.pomodoroWork)
            } else {
                // Work phase done → start break phase
                pomodoroOnBreak = true
                startBreakWithMinutes(Prefs.pomodoroBreak)
            }
        }

        // Resume playback if it was active before break
        if Prefs.resumeAfterBreak, let media = savedMediaBeforeBreak, let mode = savedModeBeforeBreak {
            savedMediaBeforeBreak = nil
            savedModeBeforeBreak = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startPlaying(media: media, on: NSScreen.screens, mode: mode)
            }
        } else {
            savedMediaBeforeBreak = nil
            savedModeBeforeBreak = nil
        }
    }

    // MARK: - Lock Screen

    @objc func lockScreenNow() {
        guard Prefs.hasLockPassword, !lockScreenActive else { return }

        // Dismiss break screen if showing
        if !screensaverWindows.isEmpty && breakEndDate == nil && currentMode == nil {
            dismissBreakScreen()
        }
        // Stop any active screensaver/ambient
        if isPlaying { stopPlaying() }

        lockScreenActive = true

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled],
            reason: "Screen locked"
        )

        let screens = NSScreen.screens
        let primaryScreen = NSScreen.main ?? screens[0]

        for screen in screens {
            let window = ScreensaverWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .init(rawValue: Int(CGShieldingWindowLevel()) + 1)
            window.isOpaque = false
            window.backgroundColor = .black
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let isPrimary = (screen == primaryScreen)
            let lockView = LockScreenView(frame: screen.frame, isPasswordScreen: isPrimary) { [weak self] in
                self?.unlockScreen()
            }
            window.contentView = lockView
            lockView.startMatrixRain()

            window.makeKeyAndOrderFront(nil)
            lockScreenWindows.append(window)

            if isPrimary {
                lockView.focusPasswordField()
            }
        }

        NSCursor.hide()
        NSApp.activate(ignoringOtherApps: true)
    }

    func unlockScreen() {
        lockScreenActive = false
        NSCursor.unhide()

        for window in lockScreenWindows {
            (window.contentView as? LockScreenView)?.stopMatrixRain()
            window.orderOut(nil)
        }
        lockScreenWindows.removeAll()

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    @objc func showSetPasswordDialog() {
        let alert = NSAlert()
        alert.alertStyle = .informational

        let width: CGFloat = 260

        if Prefs.hasLockPassword {
            alert.messageText = "Change Lock Password"
            alert.informativeText = "Enter your current password and choose a new one."

            let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 96))

            let currentLabel = NSTextField(labelWithString: "Current:")
            currentLabel.frame = NSRect(x: 0, y: 70, width: 70, height: 20)
            container.addSubview(currentLabel)

            let currentField = NSSecureTextField(frame: NSRect(x: 72, y: 68, width: width - 72, height: 24))
            container.addSubview(currentField)

            let newLabel = NSTextField(labelWithString: "New:")
            newLabel.frame = NSRect(x: 0, y: 38, width: 70, height: 20)
            container.addSubview(newLabel)

            let newField = NSSecureTextField(frame: NSRect(x: 72, y: 36, width: width - 72, height: 24))
            container.addSubview(newField)

            let confirmLabel = NSTextField(labelWithString: "Confirm:")
            confirmLabel.frame = NSRect(x: 0, y: 6, width: 70, height: 20)
            container.addSubview(confirmLabel)

            let confirmField = NSSecureTextField(frame: NSRect(x: 72, y: 4, width: width - 72, height: 24))
            container.addSubview(confirmField)

            alert.accessoryView = container
            alert.addButton(withTitle: "Change")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let currentPass = currentField.stringValue
                let newPass = newField.stringValue
                let confirmPass = confirmField.stringValue

                guard Prefs.verifyLockPassword(currentPass) else {
                    let err = NSAlert()
                    err.messageText = "Incorrect Password"
                    err.informativeText = "The current password you entered is wrong."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                guard !newPass.isEmpty else {
                    let err = NSAlert()
                    err.messageText = "Empty Password"
                    err.informativeText = "Password cannot be empty."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                guard newPass == confirmPass else {
                    let err = NSAlert()
                    err.messageText = "Passwords Don't Match"
                    err.informativeText = "New password and confirmation must match."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                Prefs.setLockPassword(newPass)
            }
        } else {
            alert.messageText = "Set Lock Password"
            alert.informativeText = "Choose a password for the lock screen."

            let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 64))

            let newLabel = NSTextField(labelWithString: "Password:")
            newLabel.frame = NSRect(x: 0, y: 38, width: 70, height: 20)
            container.addSubview(newLabel)

            let newField = NSSecureTextField(frame: NSRect(x: 72, y: 36, width: width - 72, height: 24))
            container.addSubview(newField)

            let confirmLabel = NSTextField(labelWithString: "Confirm:")
            confirmLabel.frame = NSRect(x: 0, y: 6, width: 70, height: 20)
            container.addSubview(confirmLabel)

            let confirmField = NSSecureTextField(frame: NSRect(x: 72, y: 4, width: width - 72, height: 24))
            container.addSubview(confirmField)

            alert.accessoryView = container
            alert.addButton(withTitle: "Set Password")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let newPass = newField.stringValue
                let confirmPass = confirmField.stringValue

                guard !newPass.isEmpty else {
                    let err = NSAlert()
                    err.messageText = "Empty Password"
                    err.informativeText = "Password cannot be empty."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                guard newPass == confirmPass else {
                    let err = NSAlert()
                    err.messageText = "Passwords Don't Match"
                    err.informativeText = "Password and confirmation must match."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                Prefs.setLockPassword(newPass)
            }
        }
    }

    @objc func clearLockPasswordAction() {
        let alert = NSAlert()
        alert.messageText = "Clear Lock Password?"
        alert.informativeText = "This will remove the lock screen password. You won't be able to lock the screen until you set a new one."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Prefs.clearLockPassword()
        }
    }

    // MARK: - Screen items submenu

    func addScreenItems(to menu: NSMenu, file: String, builtIn: NSScreen?, externals: [NSScreen]) {
        // Skip "All Screens" row when there are no externals — it would just duplicate the Built-in row.
        let showAllScreens = !externals.isEmpty

        let screensaverHeader = NSMenuItem(title: "Screensaver", action: nil, keyEquivalent: "")
        screensaverHeader.isEnabled = false
        menu.addItem(screensaverHeader)

        if showAllScreens {
            let allItem = NSMenuItem(title: "  All Screens", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
            allItem.representedObject = (file, NSScreen.screens) as AnyObject
            menu.addItem(allItem)
        }

        if let bi = builtIn {
            let item = NSMenuItem(title: "  \(bi.localizedName)", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
            item.representedObject = (file, [bi]) as AnyObject
            menu.addItem(item)
        }
        for ext in externals {
            let item = NSMenuItem(title: "  \(ext.localizedName)", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
            item.representedObject = (file, [ext]) as AnyObject
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let ambientHeader = NSMenuItem(title: "Ambient (keep working)", action: nil, keyEquivalent: "")
        ambientHeader.isEnabled = false
        menu.addItem(ambientHeader)

        if showAllScreens {
            let allAmbient = NSMenuItem(title: "  All Screens", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
            allAmbient.representedObject = (file, NSScreen.screens) as AnyObject
            menu.addItem(allAmbient)
        }

        if let bi = builtIn {
            let item = NSMenuItem(title: "  \(bi.localizedName)", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
            item.representedObject = (file, [bi]) as AnyObject
            menu.addItem(item)
        }
        for ext in externals {
            let item = NSMenuItem(title: "  \(ext.localizedName)", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
            item.representedObject = (file, [ext]) as AnyObject
            menu.addItem(item)
        }
        if externals.count > 1 {
            let allExt = NSMenuItem(title: "  All External", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
            allExt.representedObject = (file, externals) as AnyObject
            menu.addItem(allExt)
        }
    }

    // MARK: - Screensaver mode actions

    @objc func playAllScreensScreensaver() {
        guard let media = selectedMedia ?? findMedia().first else { return }
        startPlaying(media: media, on: NSScreen.screens, mode: .screensaver)
    }

    @objc func playMediaScreensaver(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? String else { return }
        startPlaying(media: file, on: NSScreen.screens, mode: .screensaver)
    }

    @objc func playMediaOnScreensScreensaver(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? (String, [NSScreen]) else { return }
        startPlaying(media: pair.0, on: pair.1, mode: .screensaver)
    }

    // MARK: - Ambient mode actions

    @objc func playMediaAmbient(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? (String, [NSScreen]) else { return }
        startPlaying(media: pair.0, on: pair.1, mode: .ambient)
    }

    // MARK: - Shuffle

    @objc func playShuffle() {
        let media = findMedia()
        guard !media.isEmpty else { return }
        let random = media[Int.random(in: 0..<media.count)]
        startPlaying(media: random, on: NSScreen.screens, mode: .screensaver)
    }

    // MARK: - Playback

    func startPlaying(media: String, on screens: [NSScreen], mode: PlayMode) {
        if isPlaying { stopPlaying() }

        let isMatrixRain = (media == AppDelegate.matrixRainSentinel)
        let isStarfieldWarp = (media == AppDelegate.starfieldWarpSentinel)
        let isBuiltInEffect = isMatrixRain || isStarfieldWarp

        if !isBuiltInEffect {
            guard FileManager.default.fileExists(atPath: media) else {
                let alert = NSAlert()
                alert.messageText = "File Not Found"
                alert.informativeText = "Could not find media at:\n\(media)"
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
        }

        currentMode = mode
        currentMediaPath = media
        if isMatrixRain {
            nowPlayingName = "Matrix Rain"
        } else if isStarfieldWarp {
            nowPlayingName = "Starfield Warp"
        } else {
            nowPlayingName = displayName(for: media)
        }

        // Save for auto play
        if isBuiltInEffect {
            Prefs.lastMediaFilename = media   // sentinel string
        } else {
            Prefs.lastMediaFilename = (media as NSString).lastPathComponent
        }
        Prefs.lastPlayMode = mode == .ambient ? "ambient" : "screensaver"

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled],
            reason: "Playing screensaver"
        )

        for screen in screens {
            let window = ScreensaverWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )

            if mode == .screensaver {
                window.level = .init(rawValue: Int(CGShieldingWindowLevel()))
                window.acceptsMouseMovedEvents = true
            } else {
                window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                window.acceptsMouseMovedEvents = false
                window.ignoresMouseEvents = true
                window.alphaValue = CGFloat(Prefs.ambientOpacity)
            }

            window.isOpaque = mode == .screensaver
            window.backgroundColor = .black
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let content: NSView & ScreensaverContent
            if isMatrixRain {
                content = MatrixRainView(frame: screen.frame)
            } else if isStarfieldWarp {
                content = StarfieldWarpView(frame: screen.frame)
            } else if isGif(media) {
                let url = URL(fileURLWithPath: media)
                content = GifPlayerView(frame: screen.frame, gifURL: url)
            } else {
                let url = URL(fileURLWithPath: media)
                content = VideoPlayerView(
                    frame: screen.frame, videoURL: url,
                    muted: !Prefs.soundEnabled, volume: Prefs.volume,
                    loop: Prefs.loopEnabled
                ) { [weak self] in
                    // Video finished and loop is off
                    self?.stopPlaying()
                }
            }

            window.contentView = content
            window.orderFrontRegardless()
            content.startPlayback()

            screensaverWindows.append(window)
            contentViews.append(content)
        }

        if mode == .screensaver {
            NSApp.activate(ignoringOtherApps: true)
            NSCursor.hide()

            inputMonitor = InputMonitor { [weak self] in
                self?.stopPlaying()
            }
            inputMonitor?.start()
        }

        if mode == .ambient {
            setMenuBarIcon(symbolName: "stop.circle.fill")
        }
    }

    @objc func stopPlaying() {
        inputMonitor?.stop()
        for cv in contentViews { cv.stopPlayback() }
        if currentMode == .screensaver { NSCursor.unhide() }
        for w in screensaverWindows { w.orderOut(nil) }

        screensaverWindows.removeAll()
        contentViews.removeAll()
        inputMonitor = nil
        currentMode = nil
        currentMediaPath = nil
        nowPlayingName = nil

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }

        setMenuBarIcon(symbolName: "play.rectangle.fill")

        // Sleep after playback if enabled
        if sleepAfterPlayback {
            sleepAfterPlayback = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.putMacToSleep()
            }
        }
    }

    // MARK: - Rain Overlay

    func startRainOverlay() {
        stopRainOverlay()

        for screen in targetScreens(for: Prefs.rainScreen) {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .floating
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.alphaValue = CGFloat(Prefs.rainOverlayOpacity)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let matrixView = MatrixRainView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = matrixView
            window.orderFrontRegardless()
            matrixView.startPlayback()

            rainOverlayWindows.append(window)
            rainOverlayViews.append(matrixView)
        }

        Prefs.rainOverlayEnabled = true
    }

    func stopRainOverlay() {
        for view in rainOverlayViews { view.stopPlayback() }
        for window in rainOverlayWindows { window.orderOut(nil) }
        rainOverlayWindows.removeAll()
        rainOverlayViews.removeAll()
        Prefs.rainOverlayEnabled = false
    }

    @objc func toggleRainOverlay() {
        if rainOverlayWindows.isEmpty {
            startRainOverlay()
        } else {
            stopRainOverlay()
        }
    }

    // MARK: - Rain Behind Windows

    func startRainBehind() {
        stopRainBehind()

        for screen in targetScreens(for: Prefs.rainScreen) {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.backgroundColor = .black
            window.hasShadow = false
            window.alphaValue = CGFloat(Prefs.rainBehindOpacity)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let matrixView = MatrixRainView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = matrixView
            window.orderFrontRegardless()
            matrixView.startPlayback()

            rainBehindWindows.append(window)
            rainBehindViews.append(matrixView)
        }

        Prefs.rainBehindEnabled = true
    }

    func stopRainBehind() {
        for view in rainBehindViews { view.stopPlayback() }
        for window in rainBehindWindows { window.orderOut(nil) }
        rainBehindWindows.removeAll()
        rainBehindViews.removeAll()
        Prefs.rainBehindEnabled = false
    }

    @objc func toggleRainBehind() {
        if rainBehindWindows.isEmpty {
            startRainBehind()
        } else {
            stopRainBehind()
        }
    }

    @objc func stopAllRainEffects() {
        if !rainOverlayWindows.isEmpty { stopRainOverlay() }
        if !rainBehindWindows.isEmpty { stopRainBehind() }
    }

    @objc func setRainScreen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.rainScreen = value
        if !rainBehindWindows.isEmpty { startRainBehind() }
        if !rainOverlayWindows.isEmpty { startRainOverlay() }
    }

    // MARK: - Clock Overlay

    func clockNSColor() -> NSColor {
        switch Prefs.clockColor {
        case "Blue": return NSColor(calibratedRed: 0.2, green: 0.6, blue: 1, alpha: 1)
        case "Red": return NSColor(calibratedRed: 1, green: 0.3, blue: 0.3, alpha: 1)
        case "Orange": return NSColor.orange
        case "White": return NSColor.white
        case "Purple": return NSColor(calibratedRed: 0.7, green: 0.4, blue: 1, alpha: 1)
        default: return NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 1)
        }
    }

    func clockSizeConfig() -> (width: CGFloat, height: CGFloat, fontSize: CGFloat) {
        switch Prefs.clockSize {
        case "Compact": return (120, Prefs.clockShowDate ? 48 : 32, 16)
        case "Large": return (260, Prefs.clockShowDate ? 80 : 58, 36)
        default: return (180, Prefs.clockShowDate ? 62 : 44, 24)
        }
    }

    func showClockOverlay() {
        hideClockOverlay()

        let sizeConfig = clockSizeConfig()
        let size = CGSize(width: sizeConfig.width, height: sizeConfig.height)
        let color = clockNSColor()
        let padding: CGFloat = 20
        let menuBarHeight: CGFloat = 25

        for screen in targetScreens(for: Prefs.clockScreen) {
            let origin: NSPoint
            switch Prefs.clockPosition {
            case "topLeft":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.maxY - size.height - padding - menuBarHeight)
            case "bottomRight":
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.minY + padding)
            case "bottomLeft":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.minY + padding)
            default:
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.maxY - size.height - padding - menuBarHeight)
            }

            let overlay = ClockOverlayView(frame: NSRect(origin: .zero, size: size), fontSize: sizeConfig.fontSize, color: color, showDate: Prefs.clockShowDate)
            let window = createFloatingOverlayWindow(rect: NSRect(origin: origin, size: size), content: overlay)
            window.orderFrontRegardless()
            clockWindows.append(window)
        }

        updateClockOverlay()
    }

    func hideClockOverlay() {
        clockTimer?.invalidate()
        clockTimer = nil
        for window in clockWindows { window.orderOut(nil) }
        clockWindows.removeAll()
    }

    func updateClockOverlay() {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jms", options: 0, locale: Locale.current)

        let now = Date()
        let timeString = timeFormatter.string(from: now)

        var dateString: String? = nil
        if Prefs.clockShowDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE, MMM d"
            dateString = dateFormatter.string(from: now)
        }

        for window in clockWindows {
            (window.contentView as? ClockOverlayView)?.update(time: timeString, date: dateString)
        }
    }

    func startClockOverlay() {
        showClockOverlay()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateClockOverlay()
        }
        Prefs.clockEnabled = true
    }

    func stopClockOverlay() {
        hideClockOverlay()
        Prefs.clockEnabled = false
    }

    @objc func toggleClockOverlay() {
        if clockWindows.isEmpty {
            startClockOverlay()
        } else {
            stopClockOverlay()
        }
    }

    @objc func toggleClockDate() {
        Prefs.clockShowDate = !Prefs.clockShowDate
        restartClockIfActive()
    }

    @objc func setClockScreen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.clockScreen = value
        restartClockIfActive()
    }

    @objc func setClockPosition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.clockPosition = value
        restartClockIfActive()
    }

    @objc func setClockColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.clockColor = value
        restartClockIfActive()
    }

    @objc func setClockSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.clockSize = value
        restartClockIfActive()
    }
}

// MARK: - Menu Delegate (rebuild menu each time to detect screen changes)

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = buildMenu()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
}

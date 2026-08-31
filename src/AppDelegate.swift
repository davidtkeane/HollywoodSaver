import Cocoa
import AVFoundation
import QuartzCore
import ImageIO
import ServiceManagement
import UserNotifications

// MARK: - App Delegate

enum PlayMode {
    case screensaver
    case ambient
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let matrixRainSentinel = "##MATRIX_RAIN##"
    static let starfieldWarpSentinel = "##STARFIELD_WARP##"
    static let photoSlideshowSentinel = "##PHOTO_SLIDESHOW##"
    static let metalHyperspaceSentinel = "##METAL_HYPERSPACE##"
    /// Single source of truth for About, updater, build.sh, and release.sh. Bump here only.
    static let appVersion = "5.0.4"
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
    var screenChangeWorkItem: DispatchWorkItem?
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
    static let photoExtensions = ["jpg", "jpeg", "png", "heic", "heif"]
    static let webExtensions = ["html", "htm"]
    static let allExtensions = videoExtensions + gifExtensions
    static let mediaSubfolders = ["videos", "gifs", "photos", "web"]

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

    func isWeb(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return AppDelegate.webExtensions.contains(ext)
    }

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

    /// Find all photo files (.jpg/.jpeg/.png/.heic/.heif). Scans the root
    /// folder and the `photos/` subfolder. Used exclusively by the Photo
    /// Slideshow feature — photos never appear as individual media items.
    func findPhotos() -> [URL] {
        let fm = FileManager.default
        var photos: [URL] = []

        let folders = [appFolder, (appFolder as NSString).appendingPathComponent("photos")]
        for folder in folders {
            if let files = try? fm.contentsOfDirectory(atPath: folder) {
                for file in files.sorted() {
                    let ext = (file as NSString).pathExtension.lowercased()
                    if AppDelegate.photoExtensions.contains(ext) {
                        photos.append(URL(fileURLWithPath: (folder as NSString).appendingPathComponent(file)))
                    }
                }
            }
        }
        return photos
    }

    /// Find all web wallpaper files (.html/.htm). Scans the root folder
    /// and the `web/` subfolder.
    func findWebWallpapers() -> [URL] {
        let fm = FileManager.default
        var pages: [URL] = []

        let folders = [appFolder, (appFolder as NSString).appendingPathComponent("web")]
        for folder in folders {
            if let files = try? fm.contentsOfDirectory(atPath: folder) {
                for file in files.sorted() {
                    let ext = (file as NSString).pathExtension.lowercased()
                    if AppDelegate.webExtensions.contains(ext) {
                        pages.append(URL(fileURLWithPath: (folder as NSString).appendingPathComponent(file)))
                    }
                }
            }
        }
        return pages
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
            let isBuiltIn = filename == AppDelegate.matrixRainSentinel
                         || filename == AppDelegate.starfieldWarpSentinel
                         || filename == AppDelegate.photoSlideshowSentinel
            if isBuiltIn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startPlaying(media: filename, on: NSScreen.screens, mode: mode)
                }
            } else {
                let media = findMedia()
                if let match = media.first(where: { ($0 as NSString).lastPathComponent == filename }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startPlaying(media: match, on: NSScreen.screens, mode: mode)
                    }
                }
            }
        }

        // Restore rain effects if previously enabled
        if Prefs.rainBehindEnabled {
            startRainBehind()
        }
        if Prefs.rainOverlayEnabled {
            startRainOverlay()
        }

        // Restore clock overlay if previously enabled
        if Prefs.clockEnabled {
            startClockOverlay()
        }

        // Observe sleep/wake notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Observe display changes (hotplugging, resolution change, rearrangement)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Set user notification delegate for foreground notification presentation
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @objc func handleScreenParametersChanged() {
        // This notification can fire in bursts on hotplug/resolution change.
        screenChangeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyScreenParameterChange()
        }
        screenChangeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func applyScreenParameterChange() {
        if !clockWindows.isEmpty {
            restartClockIfActive()
        }
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
        if !sleepCountdownWindows.isEmpty {
            showSleepCountdownOverlay()
        }
        if !rainOverlayWindows.isEmpty {
            startRainOverlay()
        }
        if !rainBehindWindows.isEmpty {
            startRainBehind()
        }
        restorePerMonitorPlaybackAfterDisplayChange()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
        let rootPath = (appFolder as NSString).appendingPathComponent("ranger.png")
        if FileManager.default.fileExists(atPath: rootPath) { return rootPath }
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

    /// Resolve a screen preference ("all"/"builtin"/"external"/screenIdentifier) to matching `NSScreen`s.
    func targetScreens(for preference: String) -> [NSScreen] {
        let screens = NSScreen.screens
        let builtIn = screens.first { $0.localizedName.contains("Built") }
        let externals = screens.filter { !$0.localizedName.contains("Built") }
        switch preference {
        case "all": return screens
        case "builtin": return builtIn.map { [$0] } ?? screens
        case "external": return externals.isEmpty ? screens : externals
        default:
            if let match = screens.first(where: { $0.screenIdentifier == preference }) {
                return [match]
            }
            return screens
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
    func restartClockIfActive() {
        guard !clockWindows.isEmpty else { return }
        showClockOverlay()
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateClockOverlay()
        }
    }

    func sendBreakNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request, withCompletionHandler: nil)
    }
}

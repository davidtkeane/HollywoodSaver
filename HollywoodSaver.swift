import Cocoa
import AVFoundation
import QuartzCore
import ImageIO
import ServiceManagement

// MARK: - Custom Window (borderless windows need this to receive key events)

class ScreensaverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Screensaver Content Protocol

protocol ScreensaverContent {
    func startPlayback()
    func stopPlayback()
}

// MARK: - Video Player View

class VideoPlayerView: NSView, ScreensaverContent {
    var queuePlayer: AVQueuePlayer!
    var playerLooper: AVPlayerLooper?
    var playerLayer: AVPlayerLayer!
    var onPlaybackEnded: (() -> Void)?
    var endObserver: Any?

    init(frame: NSRect, videoURL: URL, muted: Bool = true, volume: Float = 1.0, loop: Bool = true, onEnded: (() -> Void)? = nil) {
        super.init(frame: frame)
        wantsLayer = true
        onPlaybackEnded = onEnded

        let item = AVPlayerItem(url: videoURL)
        queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = muted
        queuePlayer.volume = volume

        if loop {
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        } else {
            queuePlayer.insert(item, after: nil)
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.onPlaybackEnded?()
            }
        }

        playerLayer = AVPlayerLayer(player: queuePlayer)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        layer!.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func startPlayback() {
        queuePlayer.play()
    }

    func stopPlayback() {
        queuePlayer.pause()
        queuePlayer.seek(to: .zero)
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }
}

// MARK: - GIF Player View

class GifPlayerView: NSView, ScreensaverContent {
    var imageView: NSImageView!
    var displayLink: CVDisplayLink?
    var frames: [(image: CGImage, delay: Double)] = []
    var currentFrame = 0
    var elapsed: Double = 0
    var lastTimestamp: Double = 0

    init(frame: NSRect, gifURL: URL) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageView = NSImageView(frame: bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        loadGif(url: gifURL)
    }

    required init?(coder: NSCoder) { fatalError() }

    func loadGif(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

        let count = CGImageSourceGetCount(source)
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gifProps = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gifProps?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gifProps?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
            frames.append((image: cgImage, delay: max(delay, 0.02)))
        }

        if let first = frames.first {
            imageView.image = NSImage(cgImage: first.image, size: NSSize(width: first.image.width, height: first.image.height))
        }
    }

    func startPlayback() {
        guard !frames.isEmpty else { return }
        currentFrame = 0
        elapsed = 0
        lastTimestamp = 0

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, inNow, _, _, _, userInfo -> CVReturn in
            let view = Unmanaged<GifPlayerView>.fromOpaque(userInfo!).takeUnretainedValue()
            let timestamp = Double(inNow.pointee.videoTime) / Double(inNow.pointee.videoTimeScale)

            if view.lastTimestamp == 0 {
                view.lastTimestamp = timestamp
            }
            let dt = timestamp - view.lastTimestamp
            view.lastTimestamp = timestamp
            view.elapsed += dt

            if view.elapsed >= view.frames[view.currentFrame].delay {
                view.elapsed -= view.frames[view.currentFrame].delay
                view.currentFrame = (view.currentFrame + 1) % view.frames.count
                let frame = view.frames[view.currentFrame]
                let img = NSImage(cgImage: frame.image, size: NSSize(width: frame.image.width, height: frame.image.height))
                DispatchQueue.main.async {
                    view.imageView.image = img
                }
            }
            return kCVReturnSuccess
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, callback, pointer)
        CVDisplayLinkStart(link)
    }

    func stopPlayback() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }
}

// MARK: - Input Monitor

class InputMonitor {
    var onDismiss: () -> Void
    var globalMonitor: Any?
    var localMonitor: Any?
    var initialMouseLocation: NSPoint?
    let movementThreshold: CGFloat = 5.0
    var isDismissing = false

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func start() {
        isDismissing = false
        initialMouseLocation = NSEvent.mouseLocation

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .scrollWheel, .keyDown
        ]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    func handleEvent(_ event: NSEvent) {
        guard !isDismissing else { return }

        switch event.type {
        case .keyDown:
            if event.keyCode == 53 { // Escape
                dismiss()
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            dismiss()
        case .mouseMoved, .scrollWheel:
            guard let initial = initialMouseLocation else { return }
            let current = NSEvent.mouseLocation
            let dx = abs(current.x - initial.x)
            let dy = abs(current.y - initial.y)
            if dx > movementThreshold || dy > movementThreshold {
                dismiss()
            }
        default:
            break
        }
    }

    func dismiss() {
        isDismissing = true
        onDismiss()
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }
}

// MARK: - Preferences

class Prefs {
    static let defaults = UserDefaults.standard
    static let volumeKey = "volume"
    static let soundKey = "soundEnabled"
    static let launchAtLoginKey = "launchAtLogin"
    static let opacityKey = "ambientOpacity"

    static var volume: Float {
        get { defaults.object(forKey: volumeKey) != nil ? defaults.float(forKey: volumeKey) : 0.5 }
        set { defaults.set(newValue, forKey: volumeKey) }
    }
    static var soundEnabled: Bool {
        get { defaults.bool(forKey: soundKey) }
        set { defaults.set(newValue, forKey: soundKey) }
    }
    static var launchAtLogin: Bool {
        get { defaults.bool(forKey: launchAtLoginKey) }
        set { defaults.set(newValue, forKey: launchAtLoginKey) }
    }
    static var ambientOpacity: Float {
        get { defaults.object(forKey: opacityKey) != nil ? defaults.float(forKey: opacityKey) : 1.0 }
        set { defaults.set(newValue, forKey: opacityKey) }
    }
    static var loopEnabled: Bool {
        get { defaults.object(forKey: "loopEnabled") != nil ? defaults.bool(forKey: "loopEnabled") : true }
        set { defaults.set(newValue, forKey: "loopEnabled") }
    }
    static var autoPlayEnabled: Bool {
        get { defaults.bool(forKey: "autoPlayEnabled") }
        set { defaults.set(newValue, forKey: "autoPlayEnabled") }
    }
    static var lastMediaFilename: String? {
        get { defaults.string(forKey: "lastMediaFilename") }
        set { defaults.set(newValue, forKey: "lastMediaFilename") }
    }
    static var lastPlayMode: String? {
        get { defaults.string(forKey: "lastPlayMode") }
        set { defaults.set(newValue, forKey: "lastPlayMode") }
    }
}

// MARK: - Slider Menu Item View

class SliderMenuView: NSView {
    var slider: NSSlider!
    var label: NSTextField!
    var onValueChanged: ((Float) -> Void)?

    init(title: String, minValue: Double, maxValue: Double, currentValue: Double, width: CGFloat = 220, onChange: @escaping (Float) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        onValueChanged = onChange

        label = NSTextField(labelWithString: title)
        label.font = NSFont.menuFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 5, width: 60, height: 20)
        addSubview(label)

        slider = NSSlider(value: currentValue, minValue: minValue, maxValue: maxValue, target: self, action: #selector(sliderChanged(_:)))
        slider.frame = NSRect(x: 80, y: 5, width: width - 100, height: 20)
        slider.isContinuous = true
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func sliderChanged(_ sender: NSSlider) {
        onValueChanged?(Float(sender.doubleValue))
    }
}

// MARK: - App Delegate

enum PlayMode {
    case screensaver
    case ambient
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var screensaverWindows: [ScreensaverWindow] = []
    var contentViews: [ScreensaverContent] = []
    var inputMonitor: InputMonitor?
    var activityToken: NSObjectProtocol?
    var selectedMedia: String?
    var currentMode: PlayMode?
    var nowPlayingName: String?

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
            if fm.fileExists(atPath: candidate),
               let files = try? fm.contentsOfDirectory(atPath: folder),
               files.contains(where: { AppDelegate.allExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
                return candidate
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

    func findMedia() -> [String] {
        let fm = FileManager.default
        var media: [String] = []

        if let files = try? fm.contentsOfDirectory(atPath: appFolder) {
            for file in files.sorted() {
                let ext = (file as NSString).pathExtension.lowercased()
                if AppDelegate.allExtensions.contains(ext) {
                    media.append((appFolder as NSString).appendingPathComponent(file))
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
        NSApp.setActivationPolicy(.accessory)

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

        // Auto play on launch
        if Prefs.autoPlayEnabled, let filename = Prefs.lastMediaFilename {
            let path = (appFolder as NSString).appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: path) {
                let mode: PlayMode = Prefs.lastPlayMode == "ambient" ? .ambient : .screensaver
                // Delay slightly so the app finishes launching
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startPlaying(media: path, on: NSScreen.screens, mode: mode)
                }
            }
        }
    }

    var isPlaying: Bool { currentMode != nil }

    func iconImagePath() -> String? {
        let path = (appFolder as NSString).appendingPathComponent("ranger.png")
        if FileManager.default.fileExists(atPath: path) { return path }
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

    // MARK: - Menu

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

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
        let hasExternal = !externals.isEmpty

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

            if hasExternal {
                let header = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
                menu.addItem(NSMenuItem.separator())
                addScreenItems(to: menu, file: media[0], builtIn: builtIn, externals: externals)
            } else {
                menu.addItem(NSMenuItem(title: "Play \(name)", action: #selector(playAllScreensScreensaver), keyEquivalent: ""))
            }
        } else {
            // Shuffle option
            if media.count > 1 {
                let shuffleItem = NSMenuItem(title: "Shuffle Random", action: #selector(playShuffle), keyEquivalent: "")
                menu.addItem(shuffleItem)
                menu.addItem(NSMenuItem.separator())
            }

            for file in media {
                let name = displayName(for: file)

                if hasExternal {
                    let submenu = NSMenu()
                    addScreenItems(to: submenu, file: file, builtIn: builtIn, externals: externals)

                    let menuItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                    menuItem.submenu = submenu
                    menu.addItem(menuItem)
                } else {
                    let item = NSMenuItem(title: name, action: #selector(playMediaScreensaver(_:)), keyEquivalent: "")
                    item.representedObject = file as AnyObject
                    menu.addItem(item)
                }
            }
        }

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

        menu.addItem(NSMenuItem.separator())

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

    // MARK: - Screen items submenu

    func addScreenItems(to menu: NSMenu, file: String, builtIn: NSScreen?, externals: [NSScreen]) {
        let screensaverHeader = NSMenuItem(title: "Screensaver", action: nil, keyEquivalent: "")
        screensaverHeader.isEnabled = false
        menu.addItem(screensaverHeader)

        let allItem = NSMenuItem(title: "  All Screens", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
        allItem.representedObject = (file, NSScreen.screens) as AnyObject
        menu.addItem(allItem)

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

        guard FileManager.default.fileExists(atPath: media) else {
            let alert = NSAlert()
            alert.messageText = "File Not Found"
            alert.informativeText = "Could not find media at:\n\(media)"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        let url = URL(fileURLWithPath: media)
        currentMode = mode
        nowPlayingName = displayName(for: media)

        // Save for auto play
        Prefs.lastMediaFilename = (media as NSString).lastPathComponent
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
            if isGif(media) {
                content = GifPlayerView(frame: screen.frame, gifURL: url)
            } else {
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
        nowPlayingName = nil

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }

        setMenuBarIcon(symbolName: "play.rectangle.fill")
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

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

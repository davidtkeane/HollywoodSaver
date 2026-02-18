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

// MARK: - Matrix Rain Configuration

enum MatrixColorTheme: String, CaseIterable {
    case green = "Classic Green"
    case blue = "Blue"
    case red = "Red"
    case amber = "Amber"
    case white = "White"
    case rainbow = "Rainbow"

    var primaryColor: NSColor {
        switch self {
        case .green:   return NSColor(red: 0, green: 1, blue: 0, alpha: 1)
        case .blue:    return NSColor(red: 0.2, green: 0.6, blue: 1, alpha: 1)
        case .red:     return NSColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        case .amber:   return NSColor(red: 1, green: 0.75, blue: 0, alpha: 1)
        case .white:   return NSColor.white
        case .rainbow: return NSColor.green
        }
    }
}

enum MatrixSpeed: String, CaseIterable {
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"

    var updatesPerSecond: Double {
        switch self {
        case .slow:   return 8
        case .medium: return 15
        case .fast:   return 25
        }
    }
}

enum MatrixCharacterSet: String, CaseIterable {
    case katakana = "Katakana"
    case latin = "Latin"
    case numbers = "Numbers"
    case mixed = "Mixed"
}

enum MatrixDensity: String, CaseIterable {
    case light = "Light"
    case medium = "Medium"
    case heavy = "Heavy"

    var columnSkip: Int {
        switch self {
        case .light:  return 3
        case .medium: return 2
        case .heavy:  return 1
        }
    }
}

enum MatrixFontSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var pointSize: CGFloat {
        switch self {
        case .small:  return 10
        case .medium: return 14
        case .large:  return 20
        }
    }
}

enum MatrixTrailLength: String, CaseIterable {
    case short = "Short"
    case medium = "Medium"
    case long = "Long"

    var fadeSteps: Int {
        switch self {
        case .short:  return 8
        case .medium: return 16
        case .long:   return 30
        }
    }
}

// MARK: - Matrix Rain View

class MatrixRainView: NSView, ScreensaverContent {
    struct RainColumn {
        var headRow: Int
        var speed: Double
        var characters: [Character]
        var length: Int
        var active: Bool
        var hue: CGFloat
        var delay: Double
    }

    var colorTheme: MatrixColorTheme
    var speed: MatrixSpeed
    var charSet: MatrixCharacterSet
    var density: MatrixDensity
    var fontSize: MatrixFontSize
    var trailLength: MatrixTrailLength

    var cellWidth: CGFloat
    var cellHeight: CGFloat
    var numColumns: Int
    var numRows: Int

    var columns: [RainColumn] = []
    var displayLink: CVDisplayLink?
    var lastTimestamp: Double = 0
    var elapsed: Double = 0
    var characterPool: [Character] = []
    var flickerCounter = 0

    override init(frame: NSRect) {
        colorTheme = MatrixColorTheme(rawValue: Prefs.matrixColorTheme) ?? .green
        speed = MatrixSpeed(rawValue: Prefs.matrixSpeed) ?? .medium
        charSet = MatrixCharacterSet(rawValue: Prefs.matrixCharacterSet) ?? .katakana
        density = MatrixDensity(rawValue: Prefs.matrixDensity) ?? .medium
        fontSize = MatrixFontSize(rawValue: Prefs.matrixFontSize) ?? .medium
        trailLength = MatrixTrailLength(rawValue: Prefs.matrixTrailLength) ?? .medium

        let ptSize = fontSize.pointSize
        cellWidth = ptSize * 0.7
        cellHeight = ptSize * 1.2
        numColumns = max(1, Int(frame.width / cellWidth))
        numRows = max(1, Int(frame.height / cellHeight))

        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        characterPool = buildCharacterPool()
        setupColumns()
    }

    required init?(coder: NSCoder) { fatalError() }

    func buildCharacterPool() -> [Character] {
        var pool: [Character] = []
        switch charSet {
        case .katakana:
            for scalar in 0x30A0...0x30FF {
                if let u = Unicode.Scalar(scalar) { pool.append(Character(u)) }
            }
        case .latin:
            for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { pool.append(c) }
        case .numbers:
            for c in "0123456789" { pool.append(c) }
        case .mixed:
            for scalar in 0x30A0...0x30FF {
                if let u = Unicode.Scalar(scalar) { pool.append(Character(u)) }
            }
            for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" { pool.append(c) }
        }
        return pool
    }

    func randomCharacter() -> Character {
        characterPool[Int.random(in: 0..<characterPool.count)]
    }

    func setupColumns() {
        columns = []
        for col in 0..<numColumns {
            let active = (col % density.columnSkip == 0)
            let chars = (0..<(numRows + trailLength.fadeSteps)).map { _ in randomCharacter() }
            let baseLength = trailLength.fadeSteps
            let length = baseLength + Int.random(in: -baseLength/4...baseLength/4)
            columns.append(RainColumn(
                headRow: Int.random(in: -numRows...0),
                speed: Double.random(in: 0.7...1.3),
                characters: chars,
                length: max(4, length),
                active: active,
                hue: CGFloat.random(in: 0...1),
                delay: Double.random(in: 0...2)
            ))
        }
    }

    func startPlayback() {
        lastTimestamp = 0
        elapsed = 0

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, inNow, _, _, _, userInfo -> CVReturn in
            let view = Unmanaged<MatrixRainView>.fromOpaque(userInfo!).takeUnretainedValue()
            let timestamp = Double(inNow.pointee.videoTime) / Double(inNow.pointee.videoTimeScale)

            if view.lastTimestamp == 0 { view.lastTimestamp = timestamp }
            let dt = timestamp - view.lastTimestamp
            view.lastTimestamp = timestamp

            DispatchQueue.main.async {
                view.updateState(dt: dt)
                view.setNeedsDisplay(view.bounds)
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

    func updateState(dt: Double) {
        elapsed += dt
        let interval = 1.0 / speed.updatesPerSecond
        guard elapsed >= interval else { return }
        elapsed -= interval
        flickerCounter += 1

        for i in 0..<columns.count {
            guard columns[i].active else { continue }

            if columns[i].delay > 0 {
                columns[i].delay -= interval
                continue
            }

            columns[i].headRow += 1

            // Flicker: swap a random character in the trail every few ticks
            if flickerCounter % 3 == 0 {
                let idx = Int.random(in: 0..<columns[i].characters.count)
                columns[i].characters[idx] = randomCharacter()
            }

            // Reset column when it's fully off screen
            if columns[i].headRow > numRows + columns[i].length {
                columns[i].headRow = Int.random(in: -columns[i].length...0)
                columns[i].speed = Double.random(in: 0.7...1.3)
                columns[i].delay = Double.random(in: 0...1.5)
                if colorTheme == .rainbow {
                    columns[i].hue = CGFloat.random(in: 0...1)
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        let font = CTFontCreateWithName("Menlo" as CFString, fontSize.pointSize, nil)

        for (colIndex, column) in columns.enumerated() where column.active && column.delay <= 0 {
            let x = CGFloat(colIndex) * cellWidth

            for rowOffset in 0...column.length {
                let row = column.headRow - rowOffset
                guard row >= 0, row < numRows else { continue }

                let y = bounds.height - CGFloat(row + 1) * cellHeight

                let color: NSColor
                if rowOffset == 0 {
                    color = NSColor.white
                } else {
                    let alpha = CGFloat(max(0, 1.0 - Double(rowOffset) / Double(column.length)))
                    if colorTheme == .rainbow {
                        color = NSColor(hue: column.hue, saturation: 1, brightness: 1, alpha: alpha)
                    } else {
                        color = colorTheme.primaryColor.withAlphaComponent(alpha)
                    }
                }

                let charIndex = abs(row + colIndex) % column.characters.count
                let char = String(column.characters[charIndex])

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font as Any,
                    .foregroundColor: color,
                ]
                let attrStr = NSAttributedString(string: char, attributes: attrs)
                let line = CTLineCreateWithAttributedString(attrStr)

                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, context)
            }
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

    // Matrix Rain preferences
    static var matrixColorTheme: String {
        get { defaults.string(forKey: "matrixColorTheme") ?? "Classic Green" }
        set { defaults.set(newValue, forKey: "matrixColorTheme") }
    }
    static var matrixSpeed: String {
        get { defaults.string(forKey: "matrixSpeed") ?? "Medium" }
        set { defaults.set(newValue, forKey: "matrixSpeed") }
    }
    static var matrixCharacterSet: String {
        get { defaults.string(forKey: "matrixCharacterSet") ?? "Katakana" }
        set { defaults.set(newValue, forKey: "matrixCharacterSet") }
    }
    static var matrixDensity: String {
        get { defaults.string(forKey: "matrixDensity") ?? "Medium" }
        set { defaults.set(newValue, forKey: "matrixDensity") }
    }
    static var matrixFontSize: String {
        get { defaults.string(forKey: "matrixFontSize") ?? "Medium" }
        set { defaults.set(newValue, forKey: "matrixFontSize") }
    }
    static var matrixTrailLength: String {
        get { defaults.string(forKey: "matrixTrailLength") ?? "Medium" }
        set { defaults.set(newValue, forKey: "matrixTrailLength") }
    }

    // Version check cache
    static var lastVersionCheckDate: Double {
        get { defaults.double(forKey: "lastVersionCheckDate") }
        set { defaults.set(newValue, forKey: "lastVersionCheckDate") }
    }
    static var cachedLatestVersion: String? {
        get { defaults.string(forKey: "cachedLatestVersion") }
        set { defaults.set(newValue, forKey: "cachedLatestVersion") }
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
    static let matrixRainSentinel = "##MATRIX_RAIN##"
    static let appVersion = "2.4.0"
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

        // Check for updates in background
        checkForUpdates()

        // Auto play on launch
        if Prefs.autoPlayEnabled, let filename = Prefs.lastMediaFilename {
            let mode: PlayMode = Prefs.lastPlayMode == "ambient" ? .ambient : .screensaver
            if filename == AppDelegate.matrixRainSentinel {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startPlaying(media: AppDelegate.matrixRainSentinel, on: NSScreen.screens, mode: mode)
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
        matrixSubmenu.addItem(NSMenuItem.separator())

        // Screen selection for Matrix Rain
        if hasExternal {
            addScreenItems(to: matrixSubmenu, file: AppDelegate.matrixRainSentinel, builtIn: builtIn, externals: externals)
        } else {
            let playItem = NSMenuItem(title: "Play", action: #selector(playMatrixRainAllScreens), keyEquivalent: "")
            matrixSubmenu.addItem(playItem)
        }

        matrixItem.submenu = matrixSubmenu
        menu.addItem(matrixItem)

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

    @objc func openBuyMeACoffee() {
        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/davidtkeane")!)
    }

    @objc func openH3llcoin() {
        NSWorkspace.shared.open(URL(string: "https://h3llcoin.com/how-to-buy.html")!)
    }

    // MARK: - Version Checker

    func checkForUpdates() {
        let now = Date().timeIntervalSince1970
        if now - Prefs.lastVersionCheckDate < 3600 {
            latestVersion = Prefs.cachedLatestVersion
            return
        }

        let urlString = "https://api.github.com/repos/\(AppDelegate.githubRepo)/tags"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let firstTag = json.first,
                  let tagName = firstTag["name"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            DispatchQueue.main.async {
                self?.latestVersion = remoteVersion
                Prefs.cachedLatestVersion = remoteVersion
                Prefs.lastVersionCheckDate = Date().timeIntervalSince1970
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
        alert.informativeText = """
        Current version: v\(AppDelegate.appVersion)
        Latest version: v\(latest)

        How to update:
        1. Open Terminal in the HollywoodSaver folder
        2. Run: git pull && bash build.sh
        3. The app will restart automatically

        Or click "Auto Update" to do this automatically.
        """
        alert.alertStyle = .informational

        let gitDir = (appFolder as NSString).appendingPathComponent(".git")
        let hasGit = FileManager.default.fileExists(atPath: gitDir)

        if hasGit {
            alert.addButton(withTitle: "Auto Update")
        }
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if hasGit && response == .alertFirstButtonReturn {
            performAutoUpdate()
        } else if (!hasGit && response == .alertFirstButtonReturn) || (hasGit && response == .alertSecondButtonReturn) {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(AppDelegate.githubRepo)/releases")!)
        }
    }

    @objc func performAutoUpdate() {
        let currentVersion = AppDelegate.appVersion

        let script = """
        #!/bin/bash
        set -e
        cd "\(appFolder)"

        # Backup current app
        if [ -d "HollywoodSaver.app" ]; then
            BACKUP_NAME="HollywoodSaver-v\(currentVersion).app"
            if [ -d "$BACKUP_NAME" ]; then
                rm -rf "$BACKUP_NAME"
            fi
            cp -R "HollywoodSaver.app" "$BACKUP_NAME"
            echo "Backed up to $BACKUP_NAME"
        fi

        # Pull latest code
        echo "Pulling latest code..."
        git pull origin main

        # Rebuild
        echo "Rebuilding..."
        bash build.sh
        """

        let tempScript = NSTemporaryDirectory() + "hollywoodsaver_update.sh"
        do {
            try script.write(toFile: tempScript, atomically: true, encoding: .utf8)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", tempScript]
            try chmod.run()
            chmod.waitUntilExit()

            let terminalScript = """
            tell application "Terminal"
                activate
                do script "bash '\(tempScript)'"
            end tell
            """

            let appleScript = NSAppleScript(source: terminalScript)
            var errorDict: NSDictionary?
            appleScript?.executeAndReturnError(&errorDict)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSApp.terminate(nil)
            }
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Update Failed"
            errorAlert.informativeText = "Could not start the update process: \(error.localizedDescription)\n\nPlease update manually:\ncd \(appFolder) && git pull && bash build.sh"
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

        let allAmbient = NSMenuItem(title: "  All Screens", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
        allAmbient.representedObject = (file, NSScreen.screens) as AnyObject
        menu.addItem(allAmbient)

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

        if !isMatrixRain {
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
        nowPlayingName = isMatrixRain ? "Matrix Rain" : displayName(for: media)

        // Save for auto play
        if isMatrixRain {
            Prefs.lastMediaFilename = AppDelegate.matrixRainSentinel
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

import Cocoa
import AVFoundation
import QuartzCore
import ImageIO
import ServiceManagement
import CryptoKit

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

    // Break reminder
    static var breakDuration: Int {
        get { let v = defaults.integer(forKey: "breakDuration"); return v > 0 ? v : 60 }
        set { defaults.set(newValue, forKey: "breakDuration") }
    }
    static var countdownScreen: String {
        get { defaults.string(forKey: "countdownScreen") ?? "all" }
        set { defaults.set(newValue, forKey: "countdownScreen") }
    }
    static var countdownPosition: String {
        get { defaults.string(forKey: "countdownPosition") ?? "topRight" }
        set { defaults.set(newValue, forKey: "countdownPosition") }
    }
    static var countdownColor: String {
        get { defaults.string(forKey: "countdownColor") ?? "Green" }
        set { defaults.set(newValue, forKey: "countdownColor") }
    }
    static var countdownSize: String {
        get { defaults.string(forKey: "countdownSize") ?? "Normal" }
        set { defaults.set(newValue, forKey: "countdownSize") }
    }
    static var customPresets: [Int] {
        get { defaults.array(forKey: "breakPresets") as? [Int] ?? [] }
        set { defaults.set(newValue, forKey: "breakPresets") }
    }
    static var breakSoundEnabled: Bool {
        get { defaults.object(forKey: "breakSoundEnabled") != nil ? defaults.bool(forKey: "breakSoundEnabled") : true }
        set { defaults.set(newValue, forKey: "breakSoundEnabled") }
    }
    static var breakSoundName: String {
        get { defaults.string(forKey: "breakSoundName") ?? "Glass" }
        set { defaults.set(newValue, forKey: "breakSoundName") }
    }
    static var breakScreenEnabled: Bool {
        get { defaults.object(forKey: "breakScreenEnabled") != nil ? defaults.bool(forKey: "breakScreenEnabled") : true }
        set { defaults.set(newValue, forKey: "breakScreenEnabled") }
    }
    static var resumeAfterBreak: Bool {
        get { defaults.object(forKey: "resumeAfterBreak") != nil ? defaults.bool(forKey: "resumeAfterBreak") : true }
        set { defaults.set(newValue, forKey: "resumeAfterBreak") }
    }
    static var showDockIcon: Bool {
        get { defaults.bool(forKey: "showDockIcon") }
        set { defaults.set(newValue, forKey: "showDockIcon") }
    }
    static var showDesktopShortcut: Bool {
        get { defaults.bool(forKey: "showDesktopShortcut") }
        set { defaults.set(newValue, forKey: "showDesktopShortcut") }
    }
    static var pomodoroWork: Int {
        get { let v = defaults.integer(forKey: "pomodoroWork"); return v > 0 ? v : 25 }
        set { defaults.set(newValue, forKey: "pomodoroWork") }
    }
    static var pomodoroBreak: Int {
        get { let v = defaults.integer(forKey: "pomodoroBreak"); return v > 0 ? v : 5 }
        set { defaults.set(newValue, forKey: "pomodoroBreak") }
    }
    static var breaksTakenToday: Int {
        get {
            let lastDate = defaults.string(forKey: "breakStatsDate") ?? ""
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())
            if lastDate != today { return 0 }
            return defaults.integer(forKey: "breaksTakenToday")
        }
        set {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            defaults.set(formatter.string(from: Date()), forKey: "breakStatsDate")
            defaults.set(newValue, forKey: "breaksTakenToday")
        }
    }
    static var totalBreaksTaken: Int {
        get { defaults.integer(forKey: "totalBreaksTaken") }
        set { defaults.set(newValue, forKey: "totalBreaksTaken") }
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
    static var lastNotifiedVersion: String? {
        get { defaults.string(forKey: "lastNotifiedVersion") }
        set { defaults.set(newValue, forKey: "lastNotifiedVersion") }
    }

    // Lock screen password
    static var lockPasswordHash: String? {
        get { defaults.string(forKey: "lockPasswordHash") }
        set { defaults.set(newValue, forKey: "lockPasswordHash") }
    }
    static var lockPasswordSalt: String? {
        get { defaults.string(forKey: "lockPasswordSalt") }
        set { defaults.set(newValue, forKey: "lockPasswordSalt") }
    }
    static var hasLockPassword: Bool {
        return lockPasswordHash != nil && lockPasswordSalt != nil
    }
    static func setLockPassword(_ password: String) {
        let saltData = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let salt = saltData.map { String(format: "%02x", $0) }.joined()
        let combined = salt + password
        let hash = SHA256.hash(data: Data(combined.utf8))
        lockPasswordSalt = salt
        lockPasswordHash = hash.map { String(format: "%02x", $0) }.joined()
    }
    static func verifyLockPassword(_ password: String) -> Bool {
        guard let salt = lockPasswordSalt, let storedHash = lockPasswordHash else { return false }
        let combined = salt + password
        let hash = SHA256.hash(data: Data(combined.utf8))
        let computed = hash.map { String(format: "%02x", $0) }.joined()
        return computed == storedHash
    }
    static func clearLockPassword() {
        defaults.removeObject(forKey: "lockPasswordHash")
        defaults.removeObject(forKey: "lockPasswordSalt")
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

// MARK: - Break Reminder View

class BreakReminderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dark background
        context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        context.fill(bounds)

        // Green glow circle
        let centerX = bounds.midX
        let centerY = bounds.midY + 40
        let radius: CGFloat = 120
        let glowColor = NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 0.15)
        for i in stride(from: radius * 2, through: radius, by: -10) {
            context.setFillColor(glowColor.cgColor)
            context.fillEllipse(in: CGRect(x: centerX - i, y: centerY - i, width: i * 2, height: i * 2))
        }

        // Main title
        let titleFont = NSFont.systemFont(ofSize: 48, weight: .bold)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 1)
        ]
        let title = "Take a Break, Ranger"
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        (title as NSString).draw(at: NSPoint(x: centerX - titleSize.width / 2, y: centerY - titleSize.height / 2), withAttributes: titleAttrs)

        // Subtitle
        let subFont = NSFont.systemFont(ofSize: 22, weight: .medium)
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: subFont,
            .foregroundColor: NSColor(calibratedRed: 0.7, green: 0.7, blue: 0.7, alpha: 1)
        ]
        let subtitle = "Step away from the screen for a few minutes"
        let subSize = (subtitle as NSString).size(withAttributes: subAttrs)
        (subtitle as NSString).draw(at: NSPoint(x: centerX - subSize.width / 2, y: centerY - titleSize.height / 2 - 50), withAttributes: subAttrs)

        // Dismiss hint
        let hintFont = NSFont.systemFont(ofSize: 14, weight: .regular)
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: hintFont,
            .foregroundColor: NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ]
        let hint = "Click anywhere or press Escape to dismiss  •  Auto-dismisses in 30 seconds"
        let hintSize = (hint as NSString).size(withAttributes: hintAttrs)
        (hint as NSString).draw(at: NSPoint(x: centerX - hintSize.width / 2, y: 60), withAttributes: hintAttrs)
    }
}

// MARK: - Lock Overlay View

class LockOverlayView: NSView {
    let isPasswordScreen: Bool

    init(frame: NSRect, isPasswordScreen: Bool) {
        self.isPasswordScreen = isPasswordScreen
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Semi-transparent overlay (lets Matrix Rain show through)
        context.setFillColor(NSColor.black.withAlphaComponent(0.65).cgColor)
        context.fill(bounds)

        // Green glow circle
        let centerX = bounds.midX
        let centerY = bounds.midY + 60
        let radius: CGFloat = 100
        let glowColor = NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 0.12)
        for i in stride(from: radius * 2, through: radius, by: -10) {
            context.setFillColor(glowColor.cgColor)
            context.fillEllipse(in: CGRect(x: centerX - i, y: centerY - i, width: i * 2, height: i * 2))
        }

        // Lock icon
        let lockFont = NSFont.systemFont(ofSize: 64)
        let lockAttrs: [NSAttributedString.Key: Any] = [
            .font: lockFont,
            .foregroundColor: NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 0.8)
        ]
        let lockStr = "🔒"
        let lockSize = (lockStr as NSString).size(withAttributes: lockAttrs)
        (lockStr as NSString).draw(at: NSPoint(x: centerX - lockSize.width / 2, y: centerY - lockSize.height / 2 + 10), withAttributes: lockAttrs)

        // Title
        let titleFont = NSFont.systemFont(ofSize: 42, weight: .bold)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 1)
        ]
        let title = "Screen Locked"
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        (title as NSString).draw(at: NSPoint(x: centerX - titleSize.width / 2, y: centerY - titleSize.height / 2 - 50), withAttributes: titleAttrs)

        if isPasswordScreen {
            let hintFont = NSFont.systemFont(ofSize: 14, weight: .regular)
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: hintFont,
                .foregroundColor: NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            ]
            let hint = "Enter your password and press Return to unlock"
            let hintSize = (hint as NSString).size(withAttributes: hintAttrs)
            (hint as NSString).draw(at: NSPoint(x: centerX - hintSize.width / 2, y: 60), withAttributes: hintAttrs)
        }
    }
}

// MARK: - Lock Screen View

class LockScreenView: NSView, NSTextFieldDelegate {
    var passwordField: NSSecureTextField?
    var errorLabel: NSTextField?
    var onUnlock: (() -> Void)?
    var matrixRainView: MatrixRainView?
    let isPasswordScreen: Bool

    init(frame: NSRect, isPasswordScreen: Bool, onUnlock: @escaping () -> Void) {
        self.isPasswordScreen = isPasswordScreen
        self.onUnlock = onUnlock
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Matrix Rain background
        let rain = MatrixRainView(frame: bounds)
        rain.autoresizingMask = [.width, .height]
        addSubview(rain)
        matrixRainView = rain

        // Semi-transparent overlay with lock content
        let overlay = LockOverlayView(frame: bounds, isPasswordScreen: isPasswordScreen)
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)

        if isPasswordScreen {
            setupPasswordField()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setupPasswordField() {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        field.placeholderString = "Enter password..."
        field.alignment = .center
        field.font = NSFont.systemFont(ofSize: 16)
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.target = self
        field.action = #selector(passwordSubmitted)
        field.frame.origin = NSPoint(
            x: bounds.midX - 120,
            y: bounds.midY - 80
        )
        field.autoresizingMask = []
        addSubview(field)
        passwordField = field

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = NSColor.systemRed
        label.alignment = .center
        label.frame = NSRect(x: bounds.midX - 150, y: bounds.midY - 115, width: 300, height: 20)
        label.autoresizingMask = []
        addSubview(label)
        errorLabel = label
    }

    @objc func passwordSubmitted() {
        guard let password = passwordField?.stringValue, !password.isEmpty else { return }
        if Prefs.verifyLockPassword(password) {
            onUnlock?()
        } else {
            errorLabel?.stringValue = "Incorrect password"
            shakeField()
            passwordField?.stringValue = ""
        }
    }

    func shakeField() {
        guard let field = passwordField else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.4
        animation.values = [-8, 8, -6, 6, -4, 4, 0]
        field.layer?.add(animation, forKey: "shake")
    }

    func startMatrixRain() {
        matrixRainView?.startPlayback()
    }

    func stopMatrixRain() {
        matrixRainView?.stopPlayback()
    }

    func focusPasswordField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.passwordField?.becomeFirstResponder()
        }
    }
}

// MARK: - Countdown Overlay View

class CountdownOverlayView: NSView {
    var timeLabel: NSTextField!
    var subtitleLabel: NSTextField!

    init(frame: NSRect, fontSize: CGFloat, color: NSColor) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.cornerRadius = 12

        let subtitleSize: CGFloat = fontSize < 22 ? 9 : (fontSize > 30 ? 14 : 11)
        let subtitleY = frame.height - subtitleSize - 6
        let timeY: CGFloat = 2

        subtitleLabel = NSTextField(labelWithString: "Break in")
        subtitleLabel.font = NSFont.systemFont(ofSize: subtitleSize, weight: .medium)
        subtitleLabel.textColor = NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        subtitleLabel.alignment = .center
        subtitleLabel.frame = NSRect(x: 0, y: subtitleY, width: frame.width, height: subtitleSize + 4)
        subtitleLabel.autoresizingMask = [.width]
        addSubview(subtitleLabel)

        timeLabel = NSTextField(labelWithString: "00:00")
        timeLabel.font = NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        timeLabel.textColor = color
        timeLabel.alignment = .center
        timeLabel.frame = NSRect(x: 0, y: timeY, width: frame.width, height: fontSize + 4)
        timeLabel.autoresizingMask = [.width]
        addSubview(timeLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(remaining: Int, subtitle: String? = nil) {
        let mins = remaining / 60
        let secs = remaining % 60
        timeLabel.stringValue = String(format: "%d:%02d", mins, secs)
        if let subtitle = subtitle {
            subtitleLabel.stringValue = subtitle
        }
    }
}

// MARK: - App Delegate

enum PlayMode {
    case screensaver
    case ambient
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static let matrixRainSentinel = "##MATRIX_RAIN##"
    static let appVersion = "3.4.0"
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

        // Sync desktop shortcut on launch
        syncDesktopShortcut()
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

        // Show in Dock
        let dockItem = NSMenuItem(title: "Show in Dock", action: #selector(toggleDockIcon), keyEquivalent: "")
        dockItem.state = Prefs.showDockIcon ? .on : .off
        menu.addItem(dockItem)

        // Desktop Shortcut
        let desktopItem = NSMenuItem(title: "Desktop Shortcut", action: #selector(toggleDesktopShortcut), keyEquivalent: "")
        desktopItem.state = Prefs.showDesktopShortcut ? .on : .off
        menu.addItem(desktopItem)

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

            // Use open -a Terminal (no Automation permission needed)
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
                errorAlert.informativeText = "Could not open Terminal.\n\nPlease update manually:\ncd \(appFolder) && git pull && bash build.sh"
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
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
            if let mins = Int(input.stringValue), mins > 0 {
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

        let screens = NSScreen.screens
        let builtIn = screens.first { $0.localizedName.contains("Built") }
        let externals = screens.filter { !$0.localizedName.contains("Built") }

        let targetScreens: [NSScreen]
        switch Prefs.countdownScreen {
        case "builtin": targetScreens = builtIn.map { [$0] } ?? screens
        case "external": targetScreens = externals.isEmpty ? screens : externals
        default: targetScreens = screens
        }

        let sizeConfig = countdownSizeConfig()
        let size = CGSize(width: sizeConfig.width, height: sizeConfig.height)
        let color = countdownNSColor()
        let padding: CGFloat = 20
        let menuBarHeight: CGFloat = 25

        for screen in targetScreens {
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

            let window = NSWindow(
                contentRect: NSRect(origin: origin, size: size),
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

            let overlay = CountdownOverlayView(frame: NSRect(origin: .zero, size: size), fontSize: sizeConfig.fontSize, color: color)
            window.contentView = overlay
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
        currentMediaPath = media
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
        currentMediaPath = nil
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

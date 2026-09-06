import Cocoa
import QuartzCore
import CoreText

// MARK: - Matrix Rain View

class MatrixRainView: NSView, ScreensaverContent {
    struct RainColumn {
        var headRow: Int
        var speed: Double
        var progress: Double
        var characters: [Character]
        var length: Int
        var active: Bool
        var hue: CGFloat
        var delay: Double
        var pointSize: CGFloat
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
    var lowPowerAccumulator: Double = 0
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

    /// Reload Prefs and apply while playback continues (Settings → Matrix Rain).
    func applyPrefsFromDefaults() {
        let newTheme = MatrixColorTheme(rawValue: Prefs.matrixColorTheme) ?? .green
        let newSpeed = MatrixSpeed(rawValue: Prefs.matrixSpeed) ?? .medium
        let newCharSet = MatrixCharacterSet(rawValue: Prefs.matrixCharacterSet) ?? .katakana
        let newDensity = MatrixDensity(rawValue: Prefs.matrixDensity) ?? .medium
        let newFontSize = MatrixFontSize(rawValue: Prefs.matrixFontSize) ?? .medium
        let newTrail = MatrixTrailLength(rawValue: Prefs.matrixTrailLength) ?? .medium

        let charsetChanged = newCharSet != charSet
        let needsRebuild = charsetChanged
            || newDensity != density
            || newFontSize != fontSize
            || newTrail != trailLength

        colorTheme = newTheme
        speed = newSpeed
        charSet = newCharSet
        density = newDensity
        fontSize = newFontSize
        trailLength = newTrail

        if charsetChanged {
            characterPool = buildCharacterPool()
        }

        if needsRebuild {
            let ptSize = fontSize.pointSize
            cellWidth = ptSize * 0.7
            cellHeight = ptSize * 1.2
            numColumns = max(1, Int(bounds.width / cellWidth))
            numRows = max(1, Int(bounds.height / cellHeight))
            setupColumns()
        }

        setNeedsDisplay(bounds)
    }

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
        let sizeRange = fontSize.mixedSizeRange
        for col in 0..<numColumns {
            let active = (col % density.columnSkip == 0)
            let colPoint = CGFloat.random(in: sizeRange)
            let colCellH = colPoint * 1.2
            let colRows = max(1, Int(bounds.height / max(colCellH, 1)))
            let baseLength = trailLength.fadeSteps
            // Wider length mix so streams feel uneven like film rain
            let length = baseLength + Int.random(in: -(baseLength / 3)...(baseLength / 2))
            let chars = (0..<(colRows + max(baseLength, length) + 8)).map { _ in randomCharacter() }
            columns.append(RainColumn(
                headRow: Int.random(in: -colRows...0),
                speed: Double.random(in: 0.7...1.3),
                progress: Double.random(in: 0..<1),
                characters: chars,
                length: max(8, length),
                active: active,
                hue: CGFloat.random(in: 0...1),
                delay: Double.random(in: 0...2),
                pointSize: colPoint
            ))
        }
    }

    func startPlayback() {
        lastTimestamp = 0
        elapsed = 0
        lowPowerAccumulator = 0

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, inNow, _, _, _, userInfo -> CVReturn in
            let view = Unmanaged<MatrixRainView>.fromOpaque(userInfo!).takeUnretainedValue()
            let timestamp = Double(inNow.pointee.videoTime) / Double(inNow.pointee.videoTimeScale)

            if view.lastTimestamp == 0 { view.lastTimestamp = timestamp }
            let dt = timestamp - view.lastTimestamp
            view.lastTimestamp = timestamp

            if Prefs.batterySaverActive {
                view.lowPowerAccumulator += dt
                if view.lowPowerAccumulator < (1.0 / 30.0) {
                    return kCVReturnSuccess
                }
                let stepDt = view.lowPowerAccumulator
                view.lowPowerAccumulator = 0
                DispatchQueue.main.async {
                    if view.updateState(dt: stepDt) {
                        view.setNeedsDisplay(view.bounds)
                    }
                }
                return kCVReturnSuccess
            }

            DispatchQueue.main.async {
                if view.updateState(dt: dt) {
                    view.setNeedsDisplay(view.bounds)
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

    @discardableResult
    func updateState(dt: Double) -> Bool {
        elapsed += dt
        let interval = 1.0 / speed.updatesPerSecond
        guard elapsed >= interval else { return false }
        elapsed -= interval
        flickerCounter += 1

        for i in 0..<columns.count {
            guard columns[i].active else { continue }

            if columns[i].delay > 0 {
                columns[i].delay -= interval
                continue
            }

            // Per-column fall rate (RainColumn.speed was unused before).
            columns[i].progress += columns[i].speed
            while columns[i].progress >= 1.0 {
                columns[i].progress -= 1.0
                columns[i].headRow += 1
            }

            // Flicker near the head so the tip sparkles.
            if flickerCounter % 3 == 0 {
                let tipSpan = min(4, columns[i].length)
                let rowOffset = Int.random(in: 0...tipSpan)
                let row = columns[i].headRow - rowOffset
                if row >= 0 {
                    let idx = abs(row + i) % columns[i].characters.count
                    columns[i].characters[idx] = randomCharacter()
                }
            }

            // Reset column when it's fully off screen
            let colCellH = columns[i].pointSize * 1.2
            let colRows = max(1, Int(bounds.height / max(colCellH, 1)))
            if columns[i].headRow > colRows + columns[i].length {
                columns[i].headRow = Int.random(in: -columns[i].length...0)
                columns[i].speed = Double.random(in: 0.7...1.3)
                columns[i].progress = Double.random(in: 0..<1)
                columns[i].delay = Double.random(in: 0...1.5)
                // Occasionally pick a new stream size on respawn
                if Int.random(in: 0...4) == 0 {
                    columns[i].pointSize = CGFloat.random(in: fontSize.mixedSizeRange)
                }
                if colorTheme == .rainbow {
                    columns[i].hue = CGFloat.random(in: 0...1)
                }
            }
        }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        let isRainbow = (colorTheme == .rainbow)
        let primary = colorTheme.primaryColor

        for (colIndex, column) in columns.enumerated() where column.active && column.delay <= 0 {
            let x = CGFloat(colIndex) * cellWidth
            let colLength = column.length
            let colCellH = column.pointSize * 1.2
            let colRows = max(1, Int(bounds.height / max(colCellH, 1)))
            let font = CTFontCreateWithName("Menlo" as CFString, column.pointSize, nil)

            for rowOffset in 0...colLength {
                let row = column.headRow - rowOffset
                guard row >= 0, row < colRows else { continue }

                let y = bounds.height - CGFloat(row + 1) * colCellH

                let color: NSColor
                if rowOffset == 0 {
                    // Tip: bright white
                    color = NSColor.white
                } else if rowOffset == 1 {
                    // First cell under tip: near-full brightness
                    if isRainbow {
                        color = NSColor(hue: column.hue, saturation: 0.85, brightness: 1, alpha: 0.95)
                    } else {
                        color = primary.withAlphaComponent(0.95)
                    }
                } else if rowOffset == 2 {
                    // Second cell: still bright, then trail fades
                    if isRainbow {
                        color = NSColor(hue: column.hue, saturation: 1, brightness: 1, alpha: 0.75)
                    } else {
                        color = primary.withAlphaComponent(0.75)
                    }
                } else {
                    let alpha = CGFloat(max(0, 1.0 - Double(rowOffset) / Double(colLength)))
                    if isRainbow {
                        color = NSColor(hue: column.hue, saturation: 1, brightness: 1, alpha: alpha)
                    } else {
                        color = primary.withAlphaComponent(alpha)
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

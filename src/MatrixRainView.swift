import Cocoa
import QuartzCore
import CoreText

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

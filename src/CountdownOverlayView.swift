import Cocoa

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

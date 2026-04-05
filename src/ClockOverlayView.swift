import Cocoa

class ClockOverlayView: NSView {
    var timeLabel: NSTextField!
    var dateLabel: NSTextField!

    init(frame: NSRect, fontSize: CGFloat, color: NSColor, showDate: Bool) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.cornerRadius = 12

        let dateSize: CGFloat = fontSize < 22 ? 9 : (fontSize > 30 ? 14 : 11)

        timeLabel = NSTextField(labelWithString: "00:00:00")
        timeLabel.font = NSFont(name: "Menlo", size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        timeLabel.textColor = color
        timeLabel.alignment = .center
        timeLabel.frame = NSRect(x: 0, y: showDate ? 2 : (frame.height - fontSize - 4) / 2, width: frame.width, height: fontSize + 4)
        timeLabel.autoresizingMask = [.width]
        addSubview(timeLabel)

        dateLabel = NSTextField(labelWithString: "")
        dateLabel.font = NSFont.systemFont(ofSize: dateSize, weight: .medium)
        dateLabel.textColor = NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        dateLabel.alignment = .center
        dateLabel.frame = NSRect(x: 0, y: frame.height - dateSize - 6, width: frame.width, height: dateSize + 4)
        dateLabel.autoresizingMask = [.width]
        dateLabel.isHidden = !showDate
        addSubview(dateLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(time: String, date: String?) {
        timeLabel.stringValue = time
        if let date = date {
            dateLabel.stringValue = date
            dateLabel.isHidden = false
        } else {
            dateLabel.isHidden = true
        }
    }
}

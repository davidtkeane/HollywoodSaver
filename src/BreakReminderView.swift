import Cocoa

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

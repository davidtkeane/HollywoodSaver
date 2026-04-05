import Cocoa

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

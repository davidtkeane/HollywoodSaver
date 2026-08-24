import Cocoa

// MARK: - Input Monitor

class InputMonitor {
    var onDismiss: () -> Void
    var globalMonitor: Any?
    var localMonitor: Any?
    var initialMouseLocation: NSPoint?
    var startTime: TimeInterval = 0
    let initialGracePeriod: TimeInterval = 0.5
    let movementThreshold: CGFloat = 20.0
    var isDismissing = false

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func start() {
        isDismissing = false
        startTime = CACurrentMediaTime()
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
            let now = CACurrentMediaTime()
            if now - startTime < initialGracePeriod {
                initialMouseLocation = NSEvent.mouseLocation
                return
            }
            guard let initial = initialMouseLocation else { return }
            let current = NSEvent.mouseLocation
            let dx = abs(current.x - initial.x)
            let dy = abs(current.y - initial.y)
            if hypot(dx, dy) > movementThreshold {
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

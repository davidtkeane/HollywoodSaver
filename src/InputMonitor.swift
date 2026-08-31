import Cocoa

// MARK: - Input Monitor

class InputMonitor {
    /// `nil` point means dismiss everything (Escape). A point means dismiss that screen only.
    var onDismiss: (NSPoint?) -> Void
    var globalMonitor: Any?
    var localMonitor: Any?
    var initialMouseLocation: NSPoint?
    var startTime: TimeInterval = 0
    let initialGracePeriod: TimeInterval = 0.5
    let movementThreshold: CGFloat = 20.0
    var isDismissing = false
    var activeScreensaverFrames: [NSRect] = []

    init(activeFrames: [NSRect] = [], onDismiss: @escaping (NSPoint?) -> Void) {
        self.activeScreensaverFrames = activeFrames
        self.onDismiss = onDismiss
    }

    func updateActiveFrames(_ frames: [NSRect]) {
        self.activeScreensaverFrames = frames
    }

    func isPointOnScreensaver(_ point: NSPoint) -> Bool {
        if activeScreensaverFrames.isEmpty { return true }
        return activeScreensaverFrames.contains { $0.contains(point) }
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
            if event.keyCode == 53 { // Escape still stops every screen
                dismissAll()
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let mousePt = NSEvent.mouseLocation
            if isPointOnScreensaver(mousePt) {
                dismissAt(mousePt)
            }
        case .mouseMoved, .scrollWheel:
            let now = CACurrentMediaTime()
            if now - startTime < initialGracePeriod {
                initialMouseLocation = NSEvent.mouseLocation
                return
            }

            let current = NSEvent.mouseLocation
            guard isPointOnScreensaver(current) else {
                initialMouseLocation = current
                return
            }

            guard let initial = initialMouseLocation else {
                initialMouseLocation = current
                return
            }

            let dx = abs(current.x - initial.x)
            let dy = abs(current.y - initial.y)
            if hypot(dx, dy) > movementThreshold {
                dismissAt(current)
            }
        default:
            break
        }
    }

    func dismissAll() {
        isDismissing = true
        onDismiss(nil)
    }

    func dismissAt(_ point: NSPoint) {
        onDismiss(point)
        // Reset so sliding onto a neighbouring screensaver does not instantly kill it too.
        initialMouseLocation = NSEvent.mouseLocation
        startTime = CACurrentMediaTime()
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }
}

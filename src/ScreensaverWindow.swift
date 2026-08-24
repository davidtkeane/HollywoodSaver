import Cocoa

// MARK: - Custom Window (borderless windows need this to receive key events)

class ScreensaverWindow: NSWindow {
    var targetScreenID: String?
    var screenSessionMode: PlayMode?
    var screenSessionMedia: String?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Screen Identifier Extension

extension NSScreen {
    var screenIdentifier: String {
        if let id = (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
            return "\(id)_\(localizedName)"
        }
        return "\(frame.origin.x)_\(frame.origin.y)_\(localizedName)"
    }
}

// MARK: - Screensaver Content Protocol

protocol ScreensaverContent {
    func startPlayback()
    func stopPlayback()
}

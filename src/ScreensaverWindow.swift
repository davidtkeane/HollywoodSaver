import Cocoa

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

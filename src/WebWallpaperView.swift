import Cocoa
import WebKit

// MARK: - Web / HTML5 Live Wallpaper View

class WebWallpaperView: NSView, ScreensaverContent {
    var webView: WKWebView!
    var fileURL: URL

    init(frame: NSRect, fileURL: URL) {
        self.fileURL = fileURL
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        addSubview(webView)

        loadURL()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    func loadURL() {
        let directory = fileURL.deletingLastPathComponent()
        webView.loadFileURL(fileURL, allowingReadAccessTo: directory)
    }

    func startPlayback() {
        loadURL()
    }

    func stopPlayback() {
        webView.loadHTMLString("", baseURL: nil)
        webView.stopLoading()
    }
}

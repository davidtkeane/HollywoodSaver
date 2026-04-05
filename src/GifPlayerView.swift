import Cocoa
import ImageIO
import QuartzCore

// MARK: - GIF Player View

class GifPlayerView: NSView, ScreensaverContent {
    var imageView: NSImageView!
    var displayLink: CVDisplayLink?
    var frames: [(image: CGImage, delay: Double)] = []
    var currentFrame = 0
    var elapsed: Double = 0
    var lastTimestamp: Double = 0

    init(frame: NSRect, gifURL: URL) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageView = NSImageView(frame: bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)

        loadGif(url: gifURL)
    }

    required init?(coder: NSCoder) { fatalError() }

    func loadGif(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

        let count = CGImageSourceGetCount(source)
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gifProps = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gifProps?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gifProps?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
            frames.append((image: cgImage, delay: max(delay, 0.02)))
        }

        if let first = frames.first {
            imageView.image = NSImage(cgImage: first.image, size: NSSize(width: first.image.width, height: first.image.height))
        }
    }

    func startPlayback() {
        guard !frames.isEmpty else { return }
        currentFrame = 0
        elapsed = 0
        lastTimestamp = 0

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, inNow, _, _, _, userInfo -> CVReturn in
            let view = Unmanaged<GifPlayerView>.fromOpaque(userInfo!).takeUnretainedValue()
            let timestamp = Double(inNow.pointee.videoTime) / Double(inNow.pointee.videoTimeScale)

            if view.lastTimestamp == 0 {
                view.lastTimestamp = timestamp
            }
            let dt = timestamp - view.lastTimestamp
            view.lastTimestamp = timestamp
            view.elapsed += dt

            if view.elapsed >= view.frames[view.currentFrame].delay {
                view.elapsed -= view.frames[view.currentFrame].delay
                view.currentFrame = (view.currentFrame + 1) % view.frames.count
                let frame = view.frames[view.currentFrame]
                let img = NSImage(cgImage: frame.image, size: NSSize(width: frame.image.width, height: frame.image.height))
                DispatchQueue.main.async {
                    view.imageView.image = img
                }
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
}

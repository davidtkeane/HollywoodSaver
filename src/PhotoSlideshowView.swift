import Cocoa
import QuartzCore

// MARK: - Photo Slideshow View (Ken Burns + crossfade)

/// Slideshow player for photo files (.jpg / .png / .heic / .jpeg / .heif).
/// Each photo gets a randomized **Ken Burns effect** — slow pan + zoom over the
/// slide duration — and crossfades smoothly into the next photo via a
/// ping-pong of two CALayers (front/back). Hardware-accelerated by Core
/// Animation so it stays buttery on any Apple Silicon Mac.
///
/// Photos are discovered from `photos/` in the project folder and ordered
/// randomly on each playback start. Conforms to `ScreensaverContent` so it
/// drops into the same playback pipeline as VideoPlayerView / GifPlayerView /
/// MatrixRainView / StarfieldWarpView.
class PhotoSlideshowView: NSView, ScreensaverContent {
    var photoURLs: [URL]
    var currentIndex: Int = 0
    var slideDuration: TimeInterval       // seconds per photo (pan+zoom time)
    var transitionDuration: TimeInterval  // crossfade seconds

    // Two layers ping-pong so one fades out while the next fades in.
    var frontLayer: CALayer!
    var backLayer: CALayer!
    var advanceTimer: Timer?

    init(frame: NSRect, photoURLs: [URL], slideDuration: TimeInterval, transitionDuration: TimeInterval) {
        self.photoURLs = photoURLs.shuffled()  // randomize order every launch
        self.slideDuration = slideDuration
        self.transitionDuration = transitionDuration
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true  // clip Ken Burns zoom overshoot

        // Create the two image layers. Both sized to view bounds, aspect-fill,
        // initially hidden.
        frontLayer = makeImageLayer(frame: bounds)
        backLayer  = makeImageLayer(frame: bounds)
        layer?.addSublayer(backLayer)
        layer?.addSublayer(frontLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeImageLayer(frame: NSRect) -> CALayer {
        let l = CALayer()
        l.frame = frame
        l.contentsGravity = .resizeAspectFill
        l.masksToBounds = true
        l.opacity = 0
        return l
    }

    // MARK: - Playback

    func startPlayback() {
        guard !photoURLs.isEmpty else { return }
        currentIndex = 0
        // First photo fades in softly from black (half the normal transition time).
        showPhoto(at: currentIndex, on: frontLayer, fadeInDuration: transitionDuration * 0.5, fadeOutLayer: nil)

        advanceTimer = Timer.scheduledTimer(withTimeInterval: slideDuration, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    func stopPlayback() {
        advanceTimer?.invalidate()
        advanceTimer = nil
        frontLayer?.removeAllAnimations()
        backLayer?.removeAllAnimations()
    }

    private func advance() {
        guard photoURLs.count > 1 else { return }
        currentIndex = (currentIndex + 1) % photoURLs.count

        // Swap the two layers — the current back becomes the new front (and
        // will receive the incoming photo), the current front becomes the new
        // back (and will fade out).
        let newFront = backLayer!
        let oldFront = frontLayer!
        backLayer = oldFront
        frontLayer = newFront

        showPhoto(at: currentIndex, on: frontLayer, fadeInDuration: transitionDuration, fadeOutLayer: oldFront)
    }

    // MARK: - Photo loading + Ken Burns

    private func showPhoto(at index: Int, on layer: CALayer, fadeInDuration: TimeInterval, fadeOutLayer: CALayer?) {
        guard index >= 0, index < photoURLs.count else { return }

        // Load the photo. Broken files get skipped with an advance.
        guard let image = NSImage(contentsOf: photoURLs[index]) else {
            DispatchQueue.main.async { [weak self] in self?.advance() }
            return
        }

        // Apply new image without implicit animation (we want to control the fade).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        layer.frame = bounds
        layer.zPosition = 1
        if let fadeOut = fadeOutLayer {
            fadeOut.zPosition = 0
        }
        CATransaction.commit()

        // Fade in the new front layer.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = fadeInDuration
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fadeIn, forKey: "fadeIn")
        layer.opacity = 1.0

        // Fade out the previous layer in parallel.
        if let fadeOut = fadeOutLayer {
            let fadeOutAnim = CABasicAnimation(keyPath: "opacity")
            fadeOutAnim.fromValue = 1.0
            fadeOutAnim.toValue = 0.0
            fadeOutAnim.duration = fadeInDuration
            fadeOutAnim.fillMode = .forwards
            fadeOutAnim.isRemovedOnCompletion = false
            fadeOutAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fadeOut.add(fadeOutAnim, forKey: "fadeOut")
            fadeOut.opacity = 0.0
        }

        // Ken Burns — slow zoom + pan running for the entire slide duration
        // plus a little extra so the motion keeps flowing through the crossfade.
        let kenBurns = makeKenBurnsAnimation()
        layer.add(kenBurns, forKey: "kenburns")
    }

    /// Random Ken Burns transform animation — picks a random zoom direction
    /// (in or out) and random pan direction. Each slide gets a unique feel.
    private func makeKenBurnsAnimation() -> CABasicAnimation {
        let anim = CABasicAnimation(keyPath: "transform")

        // 50/50: zoom IN (1.0 → 1.25) or zoom OUT (1.25 → 1.0). Zoom in feels
        // like "closing in on something", zoom out feels like "pulling back
        // to reveal the scene" — alternating gives documentary-style variety.
        let zoomIn = Bool.random()
        let startScale: CGFloat = zoomIn ? 1.02 : 1.25
        let endScale:   CGFloat = zoomIn ? 1.25 : 1.02

        // Random pan direction (±40 px on each axis). Bigger pans for bigger
        // images would be nice but the layer transform is applied in layer
        // coordinates so 40 px is a reasonable constant that scales well.
        let panX = CGFloat.random(in: -50...50)
        let panY = CGFloat.random(in: -50...50)

        var startTransform = CATransform3DIdentity
        startTransform = CATransform3DScale(startTransform, startScale, startScale, 1)

        var endTransform = CATransform3DIdentity
        endTransform = CATransform3DScale(endTransform, endScale, endScale, 1)
        endTransform = CATransform3DTranslate(endTransform, panX, panY, 0)

        anim.fromValue = NSValue(caTransform3D: startTransform)
        anim.toValue = NSValue(caTransform3D: endTransform)
        // Run the motion for slightly longer than the slide so it keeps flowing
        // through the crossfade into the next photo.
        anim.duration = slideDuration + transitionDuration
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return anim
    }
}

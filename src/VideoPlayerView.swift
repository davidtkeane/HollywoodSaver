import Cocoa
import AVFoundation

// MARK: - Video Player View

class VideoPlayerView: NSView, ScreensaverContent {
    var queuePlayer: AVQueuePlayer!
    var playerLooper: AVPlayerLooper?
    var playerLayer: AVPlayerLayer!
    var onPlaybackEnded: (() -> Void)?
    var endObserver: Any?

    init(frame: NSRect, videoURL: URL, muted: Bool = true, volume: Float = 1.0, loop: Bool = true, onEnded: (() -> Void)? = nil) {
        super.init(frame: frame)
        wantsLayer = true
        onPlaybackEnded = onEnded

        let item = AVPlayerItem(url: videoURL)
        queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = muted
        queuePlayer.volume = volume

        if loop {
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        } else {
            queuePlayer.insert(item, after: nil)
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                self?.onPlaybackEnded?()
            }
        }

        playerLayer = AVPlayerLayer(player: queuePlayer)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        layer!.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func startPlayback() {
        queuePlayer.play()
    }

    func stopPlayback() {
        queuePlayer.pause()
        queuePlayer.seek(to: .zero)
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }
}

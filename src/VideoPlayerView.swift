import Cocoa
import AVFoundation

// MARK: - Video Player View

class VideoPlayerView: NSView, ScreensaverContent {
    var queuePlayer: AVQueuePlayer!
    var playerLooper: AVPlayerLooper?
    var playerLayer: AVPlayerLayer!
    var onPlaybackEnded: (() -> Void)?
    var endObserver: Any?
    var playlist: [URL] = []
    var currentIndex: Int = 0
    var isLooping: Bool = true

    init(frame: NSRect, playlist: [URL], startIndex: Int = 0, muted: Bool = true, volume: Float = 1.0, loop: Bool = true, onEnded: (() -> Void)? = nil) {
        super.init(frame: frame)
        wantsLayer = true
        self.playlist = playlist
        self.currentIndex = (startIndex >= 0 && startIndex < playlist.count) ? startIndex : 0
        self.isLooping = loop
        self.onPlaybackEnded = onEnded

        queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = muted
        queuePlayer.volume = volume

        guard !playlist.isEmpty else {
            playerLayer = AVPlayerLayer(player: queuePlayer)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.frame = bounds
            layer!.addSublayer(playerLayer)
            return
        }

        let firstURL = playlist[currentIndex]
        let firstItem = AVPlayerItem(url: firstURL)

        if playlist.count == 1 && loop {
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: firstItem)
        } else {
            queuePlayer.insert(firstItem, after: nil)
            setupEndObserver(for: firstItem)
        }

        playerLayer = AVPlayerLayer(player: queuePlayer)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        layer!.addSublayer(playerLayer)
    }

    convenience init(frame: NSRect, videoURL: URL, muted: Bool = true, volume: Float = 1.0, loop: Bool = true, onEnded: (() -> Void)? = nil) {
        self.init(frame: frame, playlist: [videoURL], startIndex: 0, muted: muted, volume: volume, loop: loop, onEnded: onEnded)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func setupEndObserver(for item: AVPlayerItem) {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.advanceToNextItem()
        }
    }

    func advanceToNextItem() {
        guard !playlist.isEmpty else {
            onPlaybackEnded?()
            return
        }

        if currentIndex + 1 < playlist.count {
            currentIndex += 1
            playCurrentIndex()
        } else if isLooping {
            currentIndex = 0
            playCurrentIndex()
        } else {
            onPlaybackEnded?()
        }
    }

    func playCurrentIndex() {
        guard currentIndex < playlist.count else { return }
        let nextURL = playlist[currentIndex]
        let nextItem = AVPlayerItem(url: nextURL)
        setupEndObserver(for: nextItem)
        queuePlayer.removeAllItems()
        queuePlayer.insert(nextItem, after: nil)
        queuePlayer.play()
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

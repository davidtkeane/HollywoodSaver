import Cocoa
import QuartzCore

// MARK: - Playback, Rain Effects & Floating Clock Overlay

extension AppDelegate {

    // MARK: - Screensaver Mode Actions

    @objc func playAllScreensScreensaver() {
        guard let media = selectedMedia ?? findMedia().first else { return }
        startPlaying(media: media, on: NSScreen.screens, mode: .screensaver)
    }

    @objc func playMediaScreensaver(_ sender: NSMenuItem) {
        guard let file = sender.representedObject as? String else { return }
        startPlaying(media: file, on: NSScreen.screens, mode: .screensaver)
    }

    @objc func playMediaOnScreensScreensaver(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? (String, [NSScreen]) else { return }
        startPlaying(media: pair.0, on: pair.1, mode: .screensaver)
    }

    // MARK: - Ambient Mode Actions

    @objc func playMediaAmbient(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? (String, [NSScreen]) else { return }
        startPlaying(media: pair.0, on: pair.1, mode: .ambient)
    }

    // MARK: - Shuffle & Sequential Playlist

    @objc func playShuffle() {
        let media = findMedia()
        guard !media.isEmpty else { return }
        let random = media[Int.random(in: 0..<media.count)]
        startPlaying(media: random, on: NSScreen.screens, mode: .screensaver)
    }

    @objc func playAllVideosSequential() {
        let videos = findMedia().filter { !isGif($0) }
        guard let first = videos.first else { return }
        Prefs.playlistMode = true
        startPlaying(media: first, on: NSScreen.screens, mode: .screensaver)
    }

    // MARK: - Built-in Effect Quick Plays

    @objc func playMatrixRainAllScreens() {
        startPlaying(media: AppDelegate.matrixRainSentinel, on: NSScreen.screens, mode: .screensaver)
    }

    @objc func playStarfieldWarpAllScreens() {
        startPlaying(media: AppDelegate.starfieldWarpSentinel, on: NSScreen.screens, mode: .screensaver)
    }

    @objc func playMetalHyperspaceAllScreens() {
        startPlaying(media: AppDelegate.metalHyperspaceSentinel, on: NSScreen.screens, mode: .screensaver)
    }

    // MARK: - Core Playback Engine

    func startPlaying(media: String, on screens: [NSScreen], mode: PlayMode) {
        let isMatrixRain = (media == AppDelegate.matrixRainSentinel)
        let isStarfieldWarp = (media == AppDelegate.starfieldWarpSentinel)
        let isPhotoSlideshow = (media == AppDelegate.photoSlideshowSentinel)
        let isMetalHyperspace = (media == AppDelegate.metalHyperspaceSentinel)
        let isBuiltInEffect = isMatrixRain || isStarfieldWarp || isPhotoSlideshow || isMetalHyperspace

        // Photo slideshow needs at least one photo in the photos/ folder —
        // refuse to start if there aren't any rather than show a black screen.
        if isPhotoSlideshow {
            if findPhotos().isEmpty {
                let alert = NSAlert()
                alert.messageText = "No Photos Found"
                alert.informativeText = "Drop .jpg / .png / .heic files into the photos/ folder next to the app, then try again."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
        }

        if !isBuiltInEffect {
            guard FileManager.default.fileExists(atPath: media) else {
                let alert = NSAlert()
                alert.messageText = "File Not Found"
                alert.informativeText = "Could not find media at:\n\(media)"
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
        }

        currentMode = mode
        currentMediaPath = media
        if isMatrixRain {
            nowPlayingName = "Matrix Rain"
        } else if isStarfieldWarp {
            nowPlayingName = "Starfield Warp"
        } else if isPhotoSlideshow {
            nowPlayingName = "Photo Slideshow"
        } else if isMetalHyperspace {
            nowPlayingName = "GPU Hyperspace"
        } else {
            nowPlayingName = displayName(for: media)
        }

        // Save for auto play
        if isBuiltInEffect {
            Prefs.lastMediaFilename = media   // sentinel string
        } else {
            Prefs.lastMediaFilename = (media as NSString).lastPathComponent
        }
        Prefs.lastPlayMode = mode == .ambient ? "ambient" : "screensaver"

        if activityToken == nil {
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleDisplaySleepDisabled],
                reason: "Playing screensaver"
            )
        }

        for screen in screens {
            let screenID = screen.screenIdentifier

            // If this screen already has an active playback window, tear down only that one
            if let existingIndex = screensaverWindows.firstIndex(where: { $0.targetScreenID == screenID }) {
                let oldWin = screensaverWindows.remove(at: existingIndex)
                if let oldView = oldWin.contentView as? ScreensaverContent {
                    oldView.stopPlayback()
                    if let cvIdx = contentViews.firstIndex(where: { ($0 as? NSView) === (oldView as? NSView) }) {
                        contentViews.remove(at: cvIdx)
                    }
                }
                oldWin.orderOut(nil)
            }

            let window = ScreensaverWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.targetScreenID = screenID
            window.screenSessionMode = mode
            window.screenSessionMedia = media

            if mode == .screensaver {
                window.level = .init(rawValue: Int(CGShieldingWindowLevel()))
                window.acceptsMouseMovedEvents = true
            } else {
                window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                window.acceptsMouseMovedEvents = false
                window.ignoresMouseEvents = true
                window.alphaValue = CGFloat(Prefs.ambientOpacity)
            }

            window.isOpaque = mode == .screensaver
            window.backgroundColor = .black
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let content: NSView & ScreensaverContent
            if isMatrixRain {
                content = MatrixRainView(frame: screen.frame)
            } else if isStarfieldWarp {
                content = StarfieldWarpView(frame: screen.frame)
            } else if isMetalHyperspace {
                content = MetalWarpView(frame: screen.frame)
            } else if isPhotoSlideshow {
                content = PhotoSlideshowView(
                    frame: screen.frame,
                    photoURLs: findPhotos(),
                    slideDuration: Prefs.slideshowDuration,
                    transitionDuration: Prefs.slideshowTransition
                )
            } else if isWeb(media) {
                let url = URL(fileURLWithPath: media)
                content = WebWallpaperView(frame: screen.frame, fileURL: url)
            } else if isGif(media) {
                let url = URL(fileURLWithPath: media)
                content = GifPlayerView(frame: screen.frame, gifURL: url)
            } else {
                let allMedia = findMedia().filter { !isGif($0) }
                let playlistURLs = allMedia.map { URL(fileURLWithPath: $0) }
                let targetURL = URL(fileURLWithPath: media)
                let startIndex = playlistURLs.firstIndex(of: targetURL) ?? 0

                let playlistToPlay: [URL]
                let startIdx: Int
                if Prefs.playlistMode && playlistURLs.count > 1 {
                    playlistToPlay = playlistURLs
                    startIdx = startIndex
                } else {
                    playlistToPlay = [targetURL]
                    startIdx = 0
                }

                content = VideoPlayerView(
                    frame: screen.frame,
                    playlist: playlistToPlay,
                    startIndex: startIdx,
                    muted: !Prefs.soundEnabled,
                    volume: Prefs.volume,
                    loop: Prefs.loopEnabled
                ) { [weak self] in
                    // Video finished and loop is off
                    self?.stopPlayingOnScreen(id: screenID)
                }
            }

            window.contentView = content
            window.orderFrontRegardless()
            content.startPlayback()

            screensaverWindows.append(window)
            contentViews.append(content)
        }

        let screensaverWins = screensaverWindows.filter { $0.screenSessionMode == .screensaver }
        let allScreensCovered = screensaverWins.count >= max(1, NSScreen.screens.count)

        if !screensaverWins.isEmpty {
            if allScreensCovered {
                NSApp.activate(ignoringOtherApps: true)
                NSCursor.hide()
            }

            let activeFrames = screensaverWins.map { $0.frame }
            if inputMonitor == nil {
                inputMonitor = InputMonitor(activeFrames: activeFrames) { [weak self] in
                    self?.stopPlaying()
                }
                inputMonitor?.start()
            } else {
                inputMonitor?.updateActiveFrames(activeFrames)
            }
        }

        let hasAmbient = screensaverWindows.contains { $0.screenSessionMode == .ambient }
        if hasAmbient {
            setMenuBarIcon(symbolName: "stop.circle.fill")
        }
    }

    func stopPlayingOnScreen(id: String) {
        guard let idx = screensaverWindows.firstIndex(where: { $0.targetScreenID == id }) else { return }
        let win = screensaverWindows.remove(at: idx)
        if let cv = win.contentView as? ScreensaverContent {
            cv.stopPlayback()
            if let cvIdx = contentViews.firstIndex(where: { ($0 as? NSView) === (cv as? NSView) }) {
                contentViews.remove(at: cvIdx)
            }
        }
        win.orderOut(nil)

        if screensaverWindows.isEmpty {
            stopPlaying()
        } else {
            let screensaverWins = screensaverWindows.filter { $0.screenSessionMode == .screensaver }
            if screensaverWins.isEmpty {
                NSCursor.unhide()
                inputMonitor?.stop()
                inputMonitor = nil
            } else {
                let activeFrames = screensaverWins.map { $0.frame }
                inputMonitor?.updateActiveFrames(activeFrames)
            }
            let hasAmbient = screensaverWindows.contains { $0.screenSessionMode == .ambient }
            if !hasAmbient {
                setMenuBarIcon(symbolName: "play.rectangle.fill")
            }
        }
    }

    @objc func stopPlayingOnScreenAction(_ sender: NSMenuItem) {
        guard let screen = sender.representedObject as? NSScreen else { return }
        stopPlayingOnScreen(id: screen.screenIdentifier)
    }

    func mediaPlaying(on screen: NSScreen) -> (media: String, mode: PlayMode)? {
        if let win = screensaverWindows.first(where: { $0.targetScreenID == screen.screenIdentifier }),
           let media = win.screenSessionMedia,
           let mode = win.screenSessionMode {
            return (media, mode)
        }
        return nil
    }

    @objc func stopPlaying() {
        inputMonitor?.stop()
        for cv in contentViews { cv.stopPlayback() }
        if currentMode == .screensaver { NSCursor.unhide() }
        for w in screensaverWindows { w.orderOut(nil) }

        screensaverWindows.removeAll()
        contentViews.removeAll()
        inputMonitor = nil
        currentMode = nil
        currentMediaPath = nil
        nowPlayingName = nil

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }

        setMenuBarIcon(symbolName: "play.rectangle.fill")

        // Sleep after playback if enabled
        if sleepAfterPlayback {
            sleepAfterPlayback = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.putMacToSleep()
            }
        }
    }

    // MARK: - Rain Overlay (Over Windows)

    func startRainOverlay() {
        stopRainOverlay()

        for screen in targetScreens(for: Prefs.rainScreen) {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .floating
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.alphaValue = CGFloat(Prefs.rainOverlayOpacity)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]

            let matrixView = MatrixRainView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = matrixView
            window.orderFrontRegardless()
            matrixView.startPlayback()

            rainOverlayWindows.append(window)
            rainOverlayViews.append(matrixView)
        }

        Prefs.rainOverlayEnabled = true
    }

    func stopRainOverlay() {
        for view in rainOverlayViews { view.stopPlayback() }
        for window in rainOverlayWindows { window.orderOut(nil) }
        rainOverlayWindows.removeAll()
        rainOverlayViews.removeAll()
        Prefs.rainOverlayEnabled = false
    }

    @objc func toggleRainOverlay() {
        if rainOverlayWindows.isEmpty {
            startRainOverlay()
        } else {
            stopRainOverlay()
        }
    }

    // MARK: - Rain Behind Windows

    func startRainBehind() {
        stopRainBehind()

        for screen in targetScreens(for: Prefs.rainScreen) {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.backgroundColor = .black
            window.hasShadow = false
            window.alphaValue = CGFloat(Prefs.rainBehindOpacity)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let matrixView = MatrixRainView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = matrixView
            window.orderFrontRegardless()
            matrixView.startPlayback()

            rainBehindWindows.append(window)
            rainBehindViews.append(matrixView)
        }

        Prefs.rainBehindEnabled = true
    }

    func stopRainBehind() {
        for view in rainBehindViews { view.stopPlayback() }
        for window in rainBehindWindows { window.orderOut(nil) }
        rainBehindWindows.removeAll()
        rainBehindViews.removeAll()
        Prefs.rainBehindEnabled = false
    }

    @objc func toggleRainBehind() {
        if rainBehindWindows.isEmpty {
            startRainBehind()
        } else {
            stopRainBehind()
        }
    }

    @objc func stopAllRainEffects() {
        if !rainOverlayWindows.isEmpty { stopRainOverlay() }
        if !rainBehindWindows.isEmpty { stopRainBehind() }
    }

    @objc func setRainScreen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.rainScreen = value
        if !rainBehindWindows.isEmpty { startRainBehind() }
        if !rainOverlayWindows.isEmpty { startRainOverlay() }
    }

    // MARK: - Clock Overlay

    func clockNSColor() -> NSColor {
        switch Prefs.clockColor {
        case "Blue": return NSColor(calibratedRed: 0.2, green: 0.6, blue: 1, alpha: 1)
        case "Red": return NSColor(calibratedRed: 1, green: 0.3, blue: 0.3, alpha: 1)
        case "Orange": return NSColor.orange
        case "White": return NSColor.white
        case "Purple": return NSColor(calibratedRed: 0.7, green: 0.4, blue: 1, alpha: 1)
        default: return NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 1)
        }
    }

    func clockSizeConfig() -> (width: CGFloat, height: CGFloat, fontSize: CGFloat) {
        let is12h = !Prefs.clockFormat24h
        let widthMultiplier: CGFloat = is12h ? 1.25 : 1.0
        switch Prefs.clockSize {
        case "Compact": return (135 * widthMultiplier, Prefs.clockShowDate ? 48 : 32, 16)
        case "Large": return (280 * widthMultiplier, Prefs.clockShowDate ? 80 : 58, 36)
        default: return (190 * widthMultiplier, Prefs.clockShowDate ? 62 : 44, 24)
        }
    }

    func showClockOverlay() {
        hideClockOverlay()

        let sizeConfig = clockSizeConfig()
        let size = CGSize(width: sizeConfig.width, height: sizeConfig.height)
        let color = clockNSColor()
        let padding: CGFloat = 20
        let menuBarHeight: CGFloat = 25

        for screen in targetScreens(for: Prefs.clockScreen) {
            let origin: NSPoint
            switch Prefs.clockPosition {
            case "topLeft":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.maxY - size.height - padding - menuBarHeight)
            case "bottomRight":
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.minY + padding)
            case "bottomLeft":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.minY + padding)
            default:
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.maxY - size.height - padding - menuBarHeight)
            }

            let overlay = ClockOverlayView(frame: NSRect(origin: .zero, size: size), fontSize: sizeConfig.fontSize, color: color, showDate: Prefs.clockShowDate)
            let window = createFloatingOverlayWindow(rect: NSRect(origin: origin, size: size), content: overlay)
            window.orderFrontRegardless()
            clockWindows.append(window)
        }

        updateClockOverlay()
    }

    func hideClockOverlay() {
        clockTimer?.invalidate()
        clockTimer = nil
        for window in clockWindows { window.orderOut(nil) }
        clockWindows.removeAll()
    }

    func updateClockOverlay() {
        let timeFormatter = DateFormatter()
        if Prefs.clockFormat24h {
            timeFormatter.dateFormat = Prefs.clockShowSeconds ? "HH:mm:ss" : "HH:mm"
        } else {
            timeFormatter.dateFormat = Prefs.clockShowSeconds ? "h:mm:ss a" : "h:mm a"
        }

        let now = Date()
        let timeString = timeFormatter.string(from: now)

        var dateString: String? = nil
        if Prefs.clockShowDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE, MMM d"
            dateString = dateFormatter.string(from: now)
        }

        for window in clockWindows {
            (window.contentView as? ClockOverlayView)?.update(time: timeString, date: dateString)
        }
    }

    func startClockOverlay() {
        showClockOverlay()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateClockOverlay()
        }
        Prefs.clockEnabled = true
    }

    func stopClockOverlay() {
        hideClockOverlay()
        Prefs.clockEnabled = false
    }

    @objc func toggleClockOverlay() {
        if clockWindows.isEmpty {
            startClockOverlay()
        } else {
            stopClockOverlay()
        }
    }

    @objc func toggleClockDate() {
        Prefs.clockShowDate = !Prefs.clockShowDate
        restartClockIfActive()
    }

    @objc func setClockScreen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.clockScreen = value
        restartClockIfActive()
    }

    @objc func setClockPosition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.clockPosition = value
        restartClockIfActive()
    }

    @objc func setClockColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.clockColor = value
        restartClockIfActive()
    }

    @objc func setClockSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.clockSize = value
        restartClockIfActive()
    }
}

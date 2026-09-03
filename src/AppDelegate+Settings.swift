import Cocoa
import ServiceManagement

// MARK: - Settings Actions & Screen Items

extension AppDelegate {

    // MARK: - Core Settings

    @objc func toggleSound() {
        Prefs.soundEnabled = !Prefs.soundEnabled
        for cv in contentViews {
            if let vp = cv as? VideoPlayerView {
                vp.queuePlayer.isMuted = !Prefs.soundEnabled
            }
        }
    }

    @objc func toggleLoop() {
        Prefs.loopEnabled = !Prefs.loopEnabled
    }

    @objc func toggleAutoPlay() {
        Prefs.autoPlayEnabled = !Prefs.autoPlayEnabled
    }

    @objc func togglePlaylistMode() {
        Prefs.playlistMode = !Prefs.playlistMode
    }

    @objc func toggleLowPowerMode() {
        Prefs.lowPowerModeEnabled = !Prefs.lowPowerModeEnabled
        applyBatterySaverToRunningViews()
    }

    func applyBatterySaverToRunningViews() {
        let fps = Prefs.batterySaverActive ? 30 : 60
        for cv in contentViews {
            if let metal = cv as? MetalWarpView {
                metal.mtkView?.preferredFramesPerSecond = fps
            }
        }
    }

    @objc func openMediaFolder(_ sender: NSMenuItem) {
        let sub = sender.representedObject as? String ?? ""
        let path = sub.isEmpty ? appFolder : (appFolder as NSString).appendingPathComponent(sub)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func toggleClock24h() {
        Prefs.clockFormat24h = !Prefs.clockFormat24h
        restartClockIfActive()
    }

    @objc func toggleClockSeconds() {
        Prefs.clockShowSeconds = !Prefs.clockShowSeconds
        restartClockIfActive()
    }

    @objc func toggleLaunchAtLogin() {
        Prefs.launchAtLogin = !Prefs.launchAtLogin
        if #available(macOS 13.0, *) {
            do {
                if Prefs.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user can retry
                Prefs.launchAtLogin = !Prefs.launchAtLogin
            }
        }
    }

    @objc func toggleDockIcon() {
        Prefs.showDockIcon = !Prefs.showDockIcon
        NSApp.setActivationPolicy(Prefs.showDockIcon ? .regular : .accessory)
    }

    @objc func toggleDesktopShortcut() {
        Prefs.showDesktopShortcut = !Prefs.showDesktopShortcut
        syncDesktopShortcut()
    }

    func syncDesktopShortcut() {
        let desktop = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        let shortcutPath = (desktop as NSString).appendingPathComponent("HollywoodSaver.app")
        let fm = FileManager.default

        if Prefs.showDesktopShortcut {
            // Create symbolic link to .app on Desktop
            if !fm.fileExists(atPath: shortcutPath) {
                let appPath = Bundle.main.bundlePath
                try? fm.createSymbolicLink(atPath: shortcutPath, withDestinationPath: appPath)
            }
        } else {
            // Remove shortcut if it exists and is a symlink
            if fm.fileExists(atPath: shortcutPath) {
                if let attrs = try? fm.attributesOfItem(atPath: shortcutPath),
                   attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                    try? fm.removeItem(atPath: shortcutPath)
                }
            }
        }
    }

    // MARK: - Matrix Rain Settings

    @objc func setMatrixColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixColorTheme = value
    }

    @objc func setMatrixSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixSpeed = value
    }

    @objc func setMatrixCharSet(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixCharacterSet = value
    }

    @objc func setMatrixDensity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixDensity = value
    }

    @objc func setMatrixFontSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixFontSize = value
    }

    @objc func setMatrixTrailLength(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.matrixTrailLength = value
    }

    // MARK: - Starfield Warp Settings

    @objc func setStarfieldSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.starfieldSpeed = value
    }

    @objc func setStarfieldColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.starfieldColor = value
    }

    @objc func setStarfieldDensity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.starfieldDensity = value
    }

    @objc func setStarfieldPlanetsCount(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.starfieldPlanetsCount = value
    }

    @objc func triggerStarfieldDiveCometNow() {
        // Find any currently-playing StarfieldWarpView and trigger the animation on it.
        for view in contentViews {
            if let starfield = view as? StarfieldWarpView {
                starfield.triggerDiveComet(now: CACurrentMediaTime())
            }
        }
    }

    @objc func triggerStarfieldSpacecraftNow() {
        // Debug: spawn a random spacecraft immediately on any active Starfield view.
        for view in contentViews {
            if let starfield = view as? StarfieldWarpView {
                starfield.spawnSpacecraft(now: CACurrentMediaTime())
            }
        }
    }

    // MARK: - Photo Slideshow Settings

    @objc func setSlideshowDuration(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Prefs.slideshowDuration = value
    }

    @objc func setSlideshowTransition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Prefs.slideshowTransition = value
    }

    // MARK: - Screen Items Submenu Builder

    func addScreenItems(to menu: NSMenu, file: String, builtIn: NSScreen?, externals: [NSScreen]) {
        // Skip "All Screens" row when there are no externals — it would just duplicate the Built-in row.
        let showAllScreens = !externals.isEmpty

        let screensaverHeader = NSMenuItem(title: "Screensaver", action: nil, keyEquivalent: "")
        screensaverHeader.isEnabled = false
        menu.addItem(screensaverHeader)

        if showAllScreens {
            let allItem = NSMenuItem(title: "  All Screens", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
            allItem.representedObject = (file, NSScreen.screens) as AnyObject
            menu.addItem(allItem)
        }

        if let bi = builtIn {
            let item = NSMenuItem(title: "  \(bi.localizedName)", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
            item.representedObject = (file, [bi]) as AnyObject
            if let active = mediaPlaying(on: bi), active.media == file && active.mode == .screensaver {
                item.state = .on
            }
            menu.addItem(item)
        }
        for ext in externals {
            let item = NSMenuItem(title: "  \(ext.localizedName)", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
            item.representedObject = (file, [ext]) as AnyObject
            if let active = mediaPlaying(on: ext), active.media == file && active.mode == .screensaver {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let ambientHeader = NSMenuItem(title: "Ambient (keep working)", action: nil, keyEquivalent: "")
        ambientHeader.isEnabled = false
        menu.addItem(ambientHeader)

        if showAllScreens {
            let allAmbient = NSMenuItem(title: "  All Screens", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
            allAmbient.representedObject = (file, NSScreen.screens) as AnyObject
            menu.addItem(allAmbient)
        }

        if let bi = builtIn {
            let item = NSMenuItem(title: "  \(bi.localizedName)", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
            item.representedObject = (file, [bi]) as AnyObject
            if let active = mediaPlaying(on: bi), active.media == file && active.mode == .ambient {
                item.state = .on
            }
            menu.addItem(item)
        }
        for ext in externals {
            let item = NSMenuItem(title: "  \(ext.localizedName)", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
            item.representedObject = (file, [ext]) as AnyObject
            if let active = mediaPlaying(on: ext), active.media == file && active.mode == .ambient {
                item.state = .on
            }
            menu.addItem(item)
        }
        if externals.count > 1 {
            let allExt = NSMenuItem(title: "  All External", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
            allExt.representedObject = (file, externals) as AnyObject
            menu.addItem(allExt)
        }
    }
}

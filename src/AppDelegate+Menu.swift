import Cocoa

// MARK: - Menu Construction & Delegate

extension AppDelegate {

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        addNowPlayingItems(to: menu)
        addLastPlayedItem(to: menu)

        let media = findMedia()
        let screens = NSScreen.screens

        let playItem = NSMenuItem(title: "Play", action: nil, keyEquivalent: "")
        playItem.submenu = makePlayMenu(media: media)
        menu.addItem(playItem)

        if screens.count > 1 {
            let displaysItem = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
            displaysItem.submenu = makeDisplaysMenu(media: media, screens: screens)
            menu.addItem(displaysItem)
        }

        let overlaysItem = NSMenuItem(title: "Overlays", action: nil, keyEquivalent: "")
        overlaysItem.submenu = makeOverlaysMenu()
        menu.addItem(overlaysItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = makeSettingsMenu()
        menu.addItem(settingsItem)

        addAboutVersionQuit(to: menu)
        return menu
    }

    // MARK: - Now Playing

    func addNowPlayingItems(to menu: NSMenu) {
        let windows = screensaverWindows
        guard !windows.isEmpty else { return }

        var resolved: [(window: ScreensaverWindow, screen: NSScreen?, name: String)] = []
        for win in windows {
            let screen = NSScreen.screens.first { $0.screenIdentifier == win.targetScreenID }
            let screenName: String
            if let screen {
                screenName = screen.localizedName
            } else if let id = win.targetScreenID, let idx = id.firstIndex(of: "_") {
                screenName = String(id[id.index(after: idx)...])
            } else {
                screenName = "Display"
            }
            resolved.append((win, screen, screenName))
        }

        for item in resolved {
            let media = item.window.screenSessionMedia ?? currentMediaPath ?? ""
            var status = "● \(friendlyMediaName(for: media)) — \(item.name)"
            if item.window.screenSessionMode == .ambient {
                status += " (Ambient)"
            }
            let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
        }

        // Video audio mute is easy to miss in Settings. Surface it here while
        // a real video (not Matrix/Starfield) is playing. Default is Off.
        if contentViews.contains(where: { $0 is VideoPlayerView }) {
            addStayOpenToggle(to: menu, title: Prefs.soundEnabled ? "Sound On" : "Sound Off", isOn: Prefs.soundEnabled) { on in
                Prefs.soundEnabled = on
                for cv in self.contentViews {
                    if let vp = cv as? VideoPlayerView {
                        vp.queuePlayer.isMuted = !on
                    }
                }
            }
        }

        if resolved.count == 1 {
            if let screen = resolved[0].screen {
                let stopThis = NSMenuItem(title: "Stop This Screen", action: #selector(stopPlayingOnScreenAction(_:)), keyEquivalent: "")
                stopThis.representedObject = screen
                menu.addItem(stopThis)
            }
        } else {
            for item in resolved {
                guard let screen = item.screen else { continue }
                let stop = NSMenuItem(title: "Stop \(item.name)", action: #selector(stopPlayingOnScreenAction(_:)), keyEquivalent: "")
                stop.representedObject = screen
                menu.addItem(stop)
            }
        }

        let stopAll = NSMenuItem(title: "Stop All", action: #selector(stopPlaying), keyEquivalent: "")
        menu.addItem(stopAll)
        menu.addItem(NSMenuItem.separator())
    }

    /// One-click replay of the last clip/effect on the last screen(s).
    /// Hidden while something is already playing (Now Playing covers that)
    /// and when there is no saved last item.
    func addLastPlayedItem(to menu: NSMenu) {
        guard screensaverWindows.isEmpty else { return }
        guard let filename = Prefs.lastMediaFilename, !filename.isEmpty else { return }
        guard let media = resolvedLastPlayedMedia() else {
            let missing = NSMenuItem(title: "Last Played (missing)", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            menu.addItem(missing)
            return
        }

        let name = friendlyMediaName(for: media)
        let screen = lastPlayedScreenLabel()
        let mode = Prefs.lastPlayMode == "ambient" ? " · Ambient" : ""
        let item = NSMenuItem(
            title: "Last Played: \(name) — \(screen)\(mode)",
            action: #selector(playLastPlayed),
            keyEquivalent: ""
        )
        menu.addItem(item)
    }

    func lastPlayedScreenLabel() -> String {
        let pref = Prefs.lastPlayScreen ?? "all"
        switch pref {
        case "all": return "All Displays"
        case "builtin": return "Built-in"
        case "external": return "External"
        default:
            if let match = NSScreen.screens.first(where: { $0.screenIdentifier == pref }) {
                return match.localizedName
            }
            return "Last Display"
        }
    }

    func addStayOpenToggle(to menu: NSMenu, title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        let item = NSMenuItem()
        item.view = ToggleMenuItemView(title: title, isOn: isOn, onToggle: onToggle)
        menu.addItem(item)
    }

    func friendlyMediaName(for path: String) -> String {
        switch path {
        case AppDelegate.matrixRainSentinel: return "Matrix Rain"
        case AppDelegate.starfieldWarpSentinel: return "Starfield Warp"
        case AppDelegate.photoSlideshowSentinel: return "Photo Slideshow"
        case AppDelegate.metalHyperspaceSentinel: return "GPU Hyperspace"
        default: return displayName(for: path)
        }
    }

    /// Clickable play item. `screens == nil` uses last-used screens (`playMediaDefault`).
    func makePlayableItem(title: String, file: String, screens: [NSScreen]? = nil) -> NSMenuItem {
        let item: NSMenuItem
        if let screens {
            item = NSMenuItem(title: title, action: #selector(playMediaOnScreenDefault(_:)), keyEquivalent: "")
            item.representedObject = (file, screens) as AnyObject
            if screens.count == 1, let screen = screens.first,
               let active = mediaPlaying(on: screen), active.media == file {
                item.state = .on
            }
        } else {
            item = NSMenuItem(title: title, action: #selector(playMediaDefault(_:)), keyEquivalent: "")
            item.representedObject = file as AnyObject
            if screensaverWindows.contains(where: { $0.screenSessionMedia == file }) {
                item.state = .on
            }
        }
        return item
    }

    // MARK: - Play

    func makePlayMenu(media: [String]) -> NSMenu {
        let menu = NSMenu(title: "Play")

        if media.count > 1 {
            menu.addItem(NSMenuItem(title: "Shuffle", action: #selector(playShuffle), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Play All Sequential", action: #selector(playAllVideosSequential), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
        }

        if media.isEmpty {
            let item = NSMenuItem(title: "No media found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let hint = NSMenuItem(title: "Add .mp4/.gif files next to the app", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        } else {
            let videosItem = NSMenuItem(title: "Videos", action: nil, keyEquivalent: "")
            let videosMenu = NSMenu(title: "Videos")
            for file in media {
                videosMenu.addItem(makePlayableItem(title: displayName(for: file), file: file))
            }
            videosItem.submenu = videosMenu
            menu.addItem(videosItem)
        }

        let effectsItem = NSMenuItem(title: "Effects", action: nil, keyEquivalent: "")
        effectsItem.submenu = makeEffectsMenu()
        menu.addItem(effectsItem)

        menu.addItem(NSMenuItem.separator())
        let hint = NSMenuItem(title: "Option-click = ambient", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        return menu
    }

    func makeEffectsMenu() -> NSMenu {
        let menu = NSMenu(title: "Effects")
        menu.addItem(makePlayableItem(title: "Matrix Rain", file: AppDelegate.matrixRainSentinel))
        menu.addItem(makePlayableItem(title: "Starfield Warp", file: AppDelegate.starfieldWarpSentinel))
        menu.addItem(makePlayableItem(title: "GPU Hyperspace ⚡", file: AppDelegate.metalHyperspaceSentinel))
        menu.addItem(makePlayableItem(title: "Photo Slideshow 📸", file: AppDelegate.photoSlideshowSentinel))

        let webPages = findWebWallpapers()
        if !webPages.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let webItem = NSMenuItem(title: "Web Wallpapers 🌐", action: nil, keyEquivalent: "")
            let webMenu = NSMenu(title: "Web")
            for pageURL in webPages {
                webMenu.addItem(makePlayableItem(title: displayName(for: pageURL.path), file: pageURL.path))
            }
            webItem.submenu = webMenu
            menu.addItem(webItem)
        }
        return menu
    }

    // MARK: - Displays

    func makeDisplaysMenu(media: [String], screens: [NSScreen]) -> NSMenu {
        let menu = NSMenu(title: "Displays")

        for screen in screens {
            let screenSubmenu = NSMenu()
            let active = mediaPlaying(on: screen)

            let statusTitle: String
            if let active {
                let modeLabel = active.mode == .ambient ? "Ambient" : "Screensaver"
                statusTitle = "● \(friendlyMediaName(for: active.media)) (\(modeLabel))"
            } else {
                statusTitle = "○ Status: Idle"
            }
            let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            screenSubmenu.addItem(statusItem)
            screenSubmenu.addItem(NSMenuItem.separator())

            let target = [screen]
            screenSubmenu.addItem(makePlayableItem(title: "Matrix Rain", file: AppDelegate.matrixRainSentinel, screens: target))
            screenSubmenu.addItem(makePlayableItem(title: "Starfield Warp", file: AppDelegate.starfieldWarpSentinel, screens: target))
            screenSubmenu.addItem(makePlayableItem(title: "GPU Hyperspace ⚡", file: AppDelegate.metalHyperspaceSentinel, screens: target))
            screenSubmenu.addItem(makePlayableItem(title: "Photo Slideshow 📸", file: AppDelegate.photoSlideshowSentinel, screens: target))

            if !media.isEmpty {
                screenSubmenu.addItem(NSMenuItem.separator())
                let videosHeader = NSMenuItem(title: "Videos & GIFs", action: nil, keyEquivalent: "")
                videosHeader.isEnabled = false
                screenSubmenu.addItem(videosHeader)

                for file in media {
                    screenSubmenu.addItem(makePlayableItem(title: displayName(for: file), file: file, screens: target))
                }
            }

            if active != nil {
                screenSubmenu.addItem(NSMenuItem.separator())
                let stopDisplayItem = NSMenuItem(title: "Stop This Display", action: #selector(stopPlayingOnScreenAction(_:)), keyEquivalent: "")
                stopDisplayItem.representedObject = screen
                screenSubmenu.addItem(stopDisplayItem)
            }

            let screenMenuItem = NSMenuItem(title: screen.localizedName, action: nil, keyEquivalent: "")
            screenMenuItem.submenu = screenSubmenu
            menu.addItem(screenMenuItem)
        }

        return menu
    }

    // MARK: - Overlays

    func makeOverlaysMenu() -> NSMenu {
        let menu = NSMenu(title: "Overlays")
        menu.addItem(makeClockMenuItem())
        menu.addItem(makeRainMenuItem())
        menu.addItem(makeBreakMenuItem())
        menu.addItem(makeLockMenuItem())
        menu.addItem(makeSleepMenuItem())
        return menu
    }

    // MARK: - Settings

    func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu(title: "Settings")

        addStayOpenToggle(to: menu, title: "Sound", isOn: Prefs.soundEnabled) { on in
            Prefs.soundEnabled = on
            for cv in self.contentViews {
                if let vp = cv as? VideoPlayerView {
                    vp.queuePlayer.isMuted = !on
                }
            }
        }

        let volumeView = SliderMenuView(title: "Volume", minValue: 0, maxValue: 1, currentValue: Double(Prefs.volume)) { newVal in
            Prefs.volume = newVal
            for cv in self.contentViews {
                if let vp = cv as? VideoPlayerView {
                    vp.queuePlayer.volume = newVal
                }
            }
        }
        let volumeMenuItem = NSMenuItem()
        volumeMenuItem.view = volumeView
        menu.addItem(volumeMenuItem)

        let opacityView = SliderMenuView(title: "Opacity", minValue: 0.1, maxValue: 1, currentValue: Double(Prefs.ambientOpacity)) { newVal in
            Prefs.ambientOpacity = newVal
            if self.currentMode == .ambient {
                for w in self.screensaverWindows {
                    w.alphaValue = CGFloat(newVal)
                }
            }
        }
        let opacityMenuItem = NSMenuItem()
        opacityMenuItem.view = opacityView
        menu.addItem(opacityMenuItem)

        addStayOpenToggle(to: menu, title: "Loop", isOn: Prefs.loopEnabled) { Prefs.loopEnabled = $0 }
        addStayOpenToggle(to: menu, title: "Sequential Playlist", isOn: Prefs.playlistMode) { Prefs.playlistMode = $0 }
        addStayOpenToggle(to: menu, title: "Battery Saver (30fps)", isOn: Prefs.lowPowerModeEnabled) { Prefs.lowPowerModeEnabled = $0 }
        addStayOpenToggle(to: menu, title: "Auto Play on Launch", isOn: Prefs.autoPlayEnabled) { Prefs.autoPlayEnabled = $0 }

        addStayOpenToggle(to: menu, title: "Launch at Login", isOn: Prefs.launchAtLogin) { on in
            if Prefs.launchAtLogin == on { return }
            self.toggleLaunchAtLogin()
        }
        addStayOpenToggle(to: menu, title: "Show in Dock", isOn: Prefs.showDockIcon) { on in
            if Prefs.showDockIcon == on { return }
            self.toggleDockIcon()
        }
        addStayOpenToggle(to: menu, title: "Desktop Shortcut", isOn: Prefs.showDesktopShortcut) { on in
            if Prefs.showDesktopShortcut == on { return }
            self.toggleDesktopShortcut()
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMatrixSettingsItem())
        menu.addItem(makeStarfieldSettingsItem())
        menu.addItem(makeSlideshowSettingsItem())

        return menu
    }

    // MARK: - About / Version / Quit

    func addAboutVersionQuit(to menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())

        if let latest = latestVersion, isNewerVersion(latest, than: AppDelegate.appVersion) {
            let updateItem = NSMenuItem(
                title: "Update Available: v\(AppDelegate.appVersion) → v\(latest)",
                action: #selector(showUpdateDialog),
                keyEquivalent: ""
            )
            updateItem.attributedTitle = NSAttributedString(
                string: "Update Available: v\(AppDelegate.appVersion) → v\(latest)",
                attributes: [.foregroundColor: NSColor.systemOrange]
            )
            menu.addItem(updateItem)
        } else {
            let versionItem = NSMenuItem(
                title: "HollywoodSaver v\(AppDelegate.appVersion)",
                action: nil,
                keyEquivalent: ""
            )
            versionItem.isEnabled = false
            menu.addItem(versionItem)

            let checkItem = NSMenuItem(title: "Check for Update", action: #selector(manualCheckForUpdate), keyEquivalent: "")
            menu.addItem(checkItem)
        }

        let aboutItem = NSMenuItem(title: "About HollywoodSaver", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(aboutItem)

        let contributeItem = NSMenuItem(title: "Contribute", action: nil, keyEquivalent: "")
        let contributeSubmenu = NSMenu(title: "Contribute")
        let coffeeItem = NSMenuItem(title: "☕  Buy Me a Coffee", action: #selector(openBuyMeACoffee), keyEquivalent: "")
        contributeSubmenu.addItem(coffeeItem)
        let hodlItem = NSMenuItem(title: "🪙  Hodl H3LLCOIN", action: #selector(openH3llcoin), keyEquivalent: "")
        contributeSubmenu.addItem(hodlItem)
        contributeItem.submenu = contributeSubmenu
        menu.addItem(contributeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: - Matrix Settings (knobs only; play lives under Play/Displays)

    func makeMatrixSettingsItem() -> NSMenuItem {
        let settingsItem = NSMenuItem(title: "Matrix Rain", action: nil, keyEquivalent: "")
        let settingsSubmenu = NSMenu()

        let colorMenu = NSMenu()
        for theme in MatrixColorTheme.allCases {
            let item = NSMenuItem(title: theme.rawValue, action: #selector(setMatrixColor(_:)), keyEquivalent: "")
            item.representedObject = theme.rawValue as AnyObject
            item.state = Prefs.matrixColorTheme == theme.rawValue ? .on : .off
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Color Theme", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        settingsSubmenu.addItem(colorItem)

        let speedMenu = NSMenu()
        for s in MatrixSpeed.allCases {
            let item = NSMenuItem(title: s.rawValue, action: #selector(setMatrixSpeed(_:)), keyEquivalent: "")
            item.representedObject = s.rawValue as AnyObject
            item.state = Prefs.matrixSpeed == s.rawValue ? .on : .off
            speedMenu.addItem(item)
        }
        let speedItem = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        speedItem.submenu = speedMenu
        settingsSubmenu.addItem(speedItem)

        let charMenu = NSMenu()
        for cs in MatrixCharacterSet.allCases {
            let item = NSMenuItem(title: cs.rawValue, action: #selector(setMatrixCharSet(_:)), keyEquivalent: "")
            item.representedObject = cs.rawValue as AnyObject
            item.state = Prefs.matrixCharacterSet == cs.rawValue ? .on : .off
            charMenu.addItem(item)
        }
        let charItem = NSMenuItem(title: "Characters", action: nil, keyEquivalent: "")
        charItem.submenu = charMenu
        settingsSubmenu.addItem(charItem)

        let densityMenu = NSMenu()
        for d in MatrixDensity.allCases {
            let item = NSMenuItem(title: d.rawValue, action: #selector(setMatrixDensity(_:)), keyEquivalent: "")
            item.representedObject = d.rawValue as AnyObject
            item.state = Prefs.matrixDensity == d.rawValue ? .on : .off
            densityMenu.addItem(item)
        }
        let densityItem = NSMenuItem(title: "Density", action: nil, keyEquivalent: "")
        densityItem.submenu = densityMenu
        settingsSubmenu.addItem(densityItem)

        let fontMenu = NSMenu()
        for f in MatrixFontSize.allCases {
            let item = NSMenuItem(title: f.rawValue, action: #selector(setMatrixFontSize(_:)), keyEquivalent: "")
            item.representedObject = f.rawValue as AnyObject
            item.state = Prefs.matrixFontSize == f.rawValue ? .on : .off
            fontMenu.addItem(item)
        }
        let fontItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        settingsSubmenu.addItem(fontItem)

        let trailMenu = NSMenu()
        for t in MatrixTrailLength.allCases {
            let item = NSMenuItem(title: t.rawValue, action: #selector(setMatrixTrailLength(_:)), keyEquivalent: "")
            item.representedObject = t.rawValue as AnyObject
            item.state = Prefs.matrixTrailLength == t.rawValue ? .on : .off
            trailMenu.addItem(item)
        }
        let trailItem = NSMenuItem(title: "Trail Length", action: nil, keyEquivalent: "")
        trailItem.submenu = trailMenu
        settingsSubmenu.addItem(trailItem)

        settingsItem.submenu = settingsSubmenu
        return settingsItem
    }

    // MARK: - Starfield Settings (knobs only)

    func makeStarfieldSettingsItem() -> NSMenuItem {
        let starfieldSettingsItem = NSMenuItem(title: "Starfield Warp", action: nil, keyEquivalent: "")
        let starfieldSettingsSubmenu = NSMenu()

        let starfieldSpeedMenu = NSMenu()
        for s in StarfieldSpeed.allCases {
            let item = NSMenuItem(title: s.rawValue, action: #selector(setStarfieldSpeed(_:)), keyEquivalent: "")
            item.representedObject = s.rawValue as AnyObject
            item.state = Prefs.starfieldSpeed == s.rawValue ? .on : .off
            starfieldSpeedMenu.addItem(item)
        }
        let starfieldSpeedItem = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        starfieldSpeedItem.submenu = starfieldSpeedMenu
        starfieldSettingsSubmenu.addItem(starfieldSpeedItem)

        let starfieldColorMenu = NSMenu()
        for c in StarfieldColor.allCases {
            let item = NSMenuItem(title: c.rawValue, action: #selector(setStarfieldColor(_:)), keyEquivalent: "")
            item.representedObject = c.rawValue as AnyObject
            item.state = Prefs.starfieldColor == c.rawValue ? .on : .off
            starfieldColorMenu.addItem(item)
        }
        let starfieldColorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        starfieldColorItem.submenu = starfieldColorMenu
        starfieldSettingsSubmenu.addItem(starfieldColorItem)

        let starfieldDensityMenu = NSMenu()
        for d in StarfieldDensity.allCases {
            let item = NSMenuItem(title: d.rawValue, action: #selector(setStarfieldDensity(_:)), keyEquivalent: "")
            item.representedObject = d.rawValue as AnyObject
            item.state = Prefs.starfieldDensity == d.rawValue ? .on : .off
            starfieldDensityMenu.addItem(item)
        }
        let starfieldDensityItem = NSMenuItem(title: "Density", action: nil, keyEquivalent: "")
        starfieldDensityItem.submenu = starfieldDensityMenu
        starfieldSettingsSubmenu.addItem(starfieldDensityItem)

        starfieldSettingsSubmenu.addItem(NSMenuItem.separator())
        let starfieldBackdropItem = NSMenuItem(title: "Backdrop", action: nil, keyEquivalent: "")
        let starfieldBackdropMenu = NSMenu()

        let bgStarsItem = NSMenuItem()
        bgStarsItem.view = ToggleMenuItemView(title: "Background Stars", isOn: Prefs.starfieldBackgroundStars) { newValue in
            Prefs.starfieldBackgroundStars = newValue
        }
        starfieldBackdropMenu.addItem(bgStarsItem)

        let gradientItem = NSMenuItem()
        gradientItem.view = ToggleMenuItemView(title: "Deep Space Gradient", isOn: Prefs.starfieldGradient) { newValue in
            Prefs.starfieldGradient = newValue
        }
        starfieldBackdropMenu.addItem(gradientItem)

        let galaxiesItem = NSMenuItem()
        galaxiesItem.view = ToggleMenuItemView(title: "Distant Galaxies", isOn: Prefs.starfieldGalaxies) { newValue in
            Prefs.starfieldGalaxies = newValue
        }
        starfieldBackdropMenu.addItem(galaxiesItem)

        let nebulaeItem = NSMenuItem()
        nebulaeItem.view = ToggleMenuItemView(title: "Nebula Clouds", isOn: Prefs.starfieldNebulae) { newValue in
            Prefs.starfieldNebulae = newValue
        }
        starfieldBackdropMenu.addItem(nebulaeItem)

        starfieldBackdropMenu.addItem(NSMenuItem.separator())
        let planetsItem = NSMenuItem(title: "Planets", action: nil, keyEquivalent: "")
        let planetsMenu = NSMenu()

        let planetsShowItem = NSMenuItem()
        planetsShowItem.view = ToggleMenuItemView(title: "Show Planets", isOn: Prefs.starfieldPlanets) { newValue in
            Prefs.starfieldPlanets = newValue
        }
        planetsMenu.addItem(planetsShowItem)

        planetsMenu.addItem(NSMenuItem.separator())

        let countOptions: [(String, String)] = [
            ("Random (0–3)", "random"),
            ("None",         "0"),
            ("1 Planet",     "1"),
            ("2 Planets",    "2"),
            ("3 Planets",    "3"),
        ]
        for (label, value) in countOptions {
            let item = NSMenuItem(title: label, action: #selector(setStarfieldPlanetsCount(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.starfieldPlanetsCount == value ? .on : .off
            planetsMenu.addItem(item)
        }

        planetsItem.submenu = planetsMenu
        starfieldBackdropMenu.addItem(planetsItem)

        starfieldBackdropMenu.addItem(NSMenuItem.separator())
        let cometsItem = NSMenuItem(title: "Comets", action: nil, keyEquivalent: "")
        let cometsMenu = NSMenu()

        let passingCometsItem = NSMenuItem()
        passingCometsItem.view = ToggleMenuItemView(title: "Passing Comets", isOn: Prefs.starfieldPassingComets) { newValue in
            Prefs.starfieldPassingComets = newValue
        }
        cometsMenu.addItem(passingCometsItem)

        let diveCometItem = NSMenuItem()
        diveCometItem.view = ToggleMenuItemView(title: "Screen-Dive Comet 🎯", isOn: Prefs.starfieldDiveComet) { newValue in
            Prefs.starfieldDiveComet = newValue
        }
        cometsMenu.addItem(diveCometItem)

        cometsMenu.addItem(NSMenuItem.separator())

        let triggerDive = NSMenuItem(title: "🎬 Trigger Screen-Dive Now", action: #selector(triggerStarfieldDiveCometNow), keyEquivalent: "")
        cometsMenu.addItem(triggerDive)

        cometsItem.submenu = cometsMenu
        starfieldBackdropMenu.addItem(cometsItem)

        let spacecraftItem = NSMenuItem(title: "Spacecraft 🛸", action: nil, keyEquivalent: "")
        let spacecraftMenu = NSMenu()

        let spacecraftShowItem = NSMenuItem()
        spacecraftShowItem.view = ToggleMenuItemView(title: "Show Spacecraft", isOn: Prefs.starfieldSpacecraft) { newValue in
            Prefs.starfieldSpacecraft = newValue
        }
        spacecraftMenu.addItem(spacecraftShowItem)

        spacecraftMenu.addItem(NSMenuItem.separator())

        let shipInfo = NSMenuItem(title: "Rare visitors: Falcon, Enterprise, TARDIS, Serenity, UFO", action: nil, keyEquivalent: "")
        shipInfo.isEnabled = false
        spacecraftMenu.addItem(shipInfo)

        spacecraftMenu.addItem(NSMenuItem.separator())

        let triggerSpacecraft = NSMenuItem(title: "🎬 Spawn Random Spacecraft Now", action: #selector(triggerStarfieldSpacecraftNow), keyEquivalent: "")
        spacecraftMenu.addItem(triggerSpacecraft)

        spacecraftItem.submenu = spacecraftMenu
        starfieldBackdropMenu.addItem(spacecraftItem)

        starfieldBackdropItem.submenu = starfieldBackdropMenu
        starfieldSettingsSubmenu.addItem(starfieldBackdropItem)

        starfieldSettingsItem.submenu = starfieldSettingsSubmenu
        return starfieldSettingsItem
    }

    // MARK: - Slideshow Settings (knobs only)

    func makeSlideshowSettingsItem() -> NSMenuItem {
        let slideshowSettingsItem = NSMenuItem(title: "Photo Slideshow", action: nil, keyEquivalent: "")
        let slideshowSettingsSubmenu = NSMenu()

        let photoCount = findPhotos().count
        if photoCount == 0 {
            let noPhotos = NSMenuItem(title: "No photos found", action: nil, keyEquivalent: "")
            noPhotos.isEnabled = false
            slideshowSettingsSubmenu.addItem(noPhotos)
            let hint = NSMenuItem(title: "Drop .jpg / .png / .heic into photos/", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            slideshowSettingsSubmenu.addItem(hint)
            slideshowSettingsSubmenu.addItem(NSMenuItem.separator())
        } else {
            let countItem = NSMenuItem(title: "\(photoCount) photo\(photoCount == 1 ? "" : "s") ready", action: nil, keyEquivalent: "")
            countItem.isEnabled = false
            slideshowSettingsSubmenu.addItem(countItem)
            slideshowSettingsSubmenu.addItem(NSMenuItem.separator())
        }

        let durationItem = NSMenuItem(title: "Slide Duration", action: nil, keyEquivalent: "")
        let durationMenu = NSMenu()
        for (label, seconds) in [("3 seconds", 3.0), ("5 seconds", 5.0), ("8 seconds", 8.0), ("10 seconds", 10.0), ("15 seconds", 15.0), ("30 seconds", 30.0)] {
            let item = NSMenuItem(title: label, action: #selector(setSlideshowDuration(_:)), keyEquivalent: "")
            item.representedObject = seconds as AnyObject
            item.state = Prefs.slideshowDuration == seconds ? .on : .off
            durationMenu.addItem(item)
        }
        durationItem.submenu = durationMenu
        slideshowSettingsSubmenu.addItem(durationItem)

        let transitionItem = NSMenuItem(title: "Transition Speed", action: nil, keyEquivalent: "")
        let transitionMenu = NSMenu()
        for (label, seconds) in [("Fast (0.5s)", 0.5), ("Normal (1.5s)", 1.5), ("Slow (3s)", 3.0)] {
            let item = NSMenuItem(title: label, action: #selector(setSlideshowTransition(_:)), keyEquivalent: "")
            item.representedObject = seconds as AnyObject
            item.state = Prefs.slideshowTransition == seconds ? .on : .off
            transitionMenu.addItem(item)
        }
        transitionItem.submenu = transitionMenu
        slideshowSettingsSubmenu.addItem(transitionItem)

        slideshowSettingsItem.submenu = slideshowSettingsSubmenu
        return slideshowSettingsItem
    }

    // MARK: - Rain (Overlays)

    func makeRainMenuItem() -> NSMenuItem {
        let rainItem = NSMenuItem(title: "Rain", action: nil, keyEquivalent: "")
        let rainSubmenu = NSMenu(title: "Rain")

        let rainBehindToggle = NSMenuItem(title: "Rain Behind Windows", action: #selector(toggleRainBehind), keyEquivalent: "")
        rainBehindToggle.state = !rainBehindWindows.isEmpty ? .on : .off
        rainSubmenu.addItem(rainBehindToggle)

        let rainBehindOpacityView = SliderMenuView(title: "Behind Opacity", minValue: 0.1, maxValue: 1, currentValue: Double(Prefs.rainBehindOpacity)) { newVal in
            Prefs.rainBehindOpacity = newVal
            for w in self.rainBehindWindows {
                w.alphaValue = CGFloat(newVal)
            }
        }
        let rainBehindOpacityItem = NSMenuItem()
        rainBehindOpacityItem.view = rainBehindOpacityView
        rainSubmenu.addItem(rainBehindOpacityItem)

        rainSubmenu.addItem(NSMenuItem.separator())

        let rainOverToggle = NSMenuItem(title: "Rain Over Windows", action: #selector(toggleRainOverlay), keyEquivalent: "")
        rainOverToggle.state = !rainOverlayWindows.isEmpty ? .on : .off
        rainSubmenu.addItem(rainOverToggle)

        let rainOverOpacityView = SliderMenuView(title: "Over Opacity", minValue: 0.05, maxValue: 0.5, currentValue: Double(Prefs.rainOverlayOpacity)) { newVal in
            Prefs.rainOverlayOpacity = newVal
            for w in self.rainOverlayWindows {
                w.alphaValue = CGFloat(newVal)
            }
        }
        let rainOverOpacityItem = NSMenuItem()
        rainOverOpacityItem.view = rainOverOpacityView
        rainSubmenu.addItem(rainOverOpacityItem)

        rainSubmenu.addItem(NSMenuItem.separator())
        let rainDisplayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let rainDisplaySubmenu = NSMenu(title: "Display")
        for (label, value) in [("All Screens", "all"), ("Built-in", "builtin"), ("External", "external")] {
            let item = NSMenuItem(title: label, action: #selector(setRainScreen(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.rainScreen == value ? .on : .off
            rainDisplaySubmenu.addItem(item)
        }
        rainDisplayItem.submenu = rainDisplaySubmenu
        rainSubmenu.addItem(rainDisplayItem)

        if !rainBehindWindows.isEmpty || !rainOverlayWindows.isEmpty {
            rainSubmenu.addItem(NSMenuItem.separator())
            let stopAllRain = NSMenuItem(title: "Stop All Rain", action: #selector(stopAllRainEffects), keyEquivalent: "")
            rainSubmenu.addItem(stopAllRain)
        }

        rainItem.submenu = rainSubmenu
        return rainItem
    }

    // MARK: - Break Reminder (Overlays)

    func makeBreakMenuItem() -> NSMenuItem {
        let breakItem = NSMenuItem(title: "Break / Pomodoro", action: nil, keyEquivalent: "")
        let breakSubmenu = NSMenu(title: "Break Reminder")

        let todayItem = NSMenuItem(title: "Today: \(Prefs.breaksTakenToday) break\(Prefs.breaksTakenToday == 1 ? "" : "s")", action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        breakSubmenu.addItem(todayItem)
        let totalItem = NSMenuItem(title: "Total: \(Prefs.totalBreaksTaken) break\(Prefs.totalBreaksTaken == 1 ? "" : "s")", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        breakSubmenu.addItem(totalItem)
        breakSubmenu.addItem(NSMenuItem.separator())

        if let endDate = breakEndDate {
            let remaining = max(0, Int(endDate.timeIntervalSinceNow))
            let mins = remaining / 60
            let secs = remaining % 60
            let phase = pomodoroActive ? (pomodoroOnBreak ? "Break" : "Work") : "Break in"
            let countdownItem = NSMenuItem(title: String(format: "  %@ %d:%02d", phase, mins, secs), action: nil, keyEquivalent: "")
            countdownItem.isEnabled = false
            breakSubmenu.addItem(countdownItem)
            if pomodoroActive {
                let stopItem = NSMenuItem(title: "Stop Pomodoro", action: #selector(stopPomodoro), keyEquivalent: "")
                breakSubmenu.addItem(stopItem)
            }
            let cancelItem = NSMenuItem(title: "Cancel Timer", action: #selector(cancelBreakTimer), keyEquivalent: "")
            breakSubmenu.addItem(cancelItem)
        } else {
            for minutes in [60, 45, 30, 15] {
                let item = NSMenuItem(title: "Start \(minutes) min", action: #selector(startBreakTimer(_:)), keyEquivalent: "")
                item.representedObject = minutes as AnyObject
                breakSubmenu.addItem(item)
            }
            let customItem = NSMenuItem(title: "Custom...", action: #selector(startCustomBreakTimer), keyEquivalent: "")
            breakSubmenu.addItem(customItem)

            let presets = Prefs.customPresets
            if !presets.isEmpty {
                breakSubmenu.addItem(NSMenuItem.separator())
                for mins in presets {
                    let item = NSMenuItem(title: "Start \(mins) min \u{2605}", action: #selector(startBreakTimer(_:)), keyEquivalent: "")
                    item.representedObject = mins as AnyObject
                    breakSubmenu.addItem(item)
                }
            }

            let presetsItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
            let presetsSubmenu = NSMenu(title: "Presets")
            let saveItem = NSMenuItem(title: "Save Current (\(Prefs.breakDuration) min)", action: #selector(saveCurrentPreset), keyEquivalent: "")
            presetsSubmenu.addItem(saveItem)
            if !presets.isEmpty {
                let clearItem = NSMenuItem(title: "Clear All Presets", action: #selector(clearPresets), keyEquivalent: "")
                presetsSubmenu.addItem(clearItem)
            }
            presetsItem.submenu = presetsSubmenu
            breakSubmenu.addItem(presetsItem)
        }

        breakSubmenu.addItem(NSMenuItem.separator())
        let pomoItem = NSMenuItem(title: "Pomodoro", action: nil, keyEquivalent: "")
        let pomoSubmenu = NSMenu(title: "Pomodoro")
        if pomodoroActive {
            let stopPomo = NSMenuItem(title: "Stop Pomodoro", action: #selector(stopPomodoro), keyEquivalent: "")
            pomoSubmenu.addItem(stopPomo)
        } else {
            let startPomo = NSMenuItem(title: "Start Pomodoro", action: #selector(startPomodoro), keyEquivalent: "")
            pomoSubmenu.addItem(startPomo)
        }
        pomoSubmenu.addItem(NSMenuItem.separator())
        let workItem = NSMenuItem(title: "Work: \(Prefs.pomodoroWork) min", action: nil, keyEquivalent: "")
        let workSubmenu = NSMenu(title: "Work Duration")
        for mins in [15, 20, 25, 30, 45, 50] {
            let item = NSMenuItem(title: "\(mins) min", action: #selector(setPomodoroWork(_:)), keyEquivalent: "")
            item.representedObject = mins as AnyObject
            item.state = Prefs.pomodoroWork == mins ? .on : .off
            workSubmenu.addItem(item)
        }
        workItem.submenu = workSubmenu
        pomoSubmenu.addItem(workItem)
        let breakDurItem = NSMenuItem(title: "Break: \(Prefs.pomodoroBreak) min", action: nil, keyEquivalent: "")
        let breakDurSubmenu = NSMenu(title: "Break Duration")
        for mins in [3, 5, 10, 15] {
            let item = NSMenuItem(title: "\(mins) min", action: #selector(setPomodoroBreak(_:)), keyEquivalent: "")
            item.representedObject = mins as AnyObject
            item.state = Prefs.pomodoroBreak == mins ? .on : .off
            breakDurSubmenu.addItem(item)
        }
        breakDurItem.submenu = breakDurSubmenu
        pomoSubmenu.addItem(breakDurItem)
        pomoItem.submenu = pomoSubmenu
        breakSubmenu.addItem(pomoItem)

        breakSubmenu.addItem(NSMenuItem.separator())
        let breakSoundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        let breakSoundSubmenu = NSMenu(title: "Sound")
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleBreakSound), keyEquivalent: "")
        enabledItem.state = Prefs.breakSoundEnabled ? .on : .off
        breakSoundSubmenu.addItem(enabledItem)
        breakSoundSubmenu.addItem(NSMenuItem.separator())
        for name in ["Glass", "Hero", "Ping", "Pop", "Purr", "Submarine"] {
            let item = NSMenuItem(title: name, action: #selector(setBreakSound(_:)), keyEquivalent: "")
            item.representedObject = name as AnyObject
            item.state = Prefs.breakSoundName == name ? .on : .off
            item.isEnabled = Prefs.breakSoundEnabled
            breakSoundSubmenu.addItem(item)
        }
        breakSoundItem.submenu = breakSoundSubmenu
        breakSubmenu.addItem(breakSoundItem)

        let breakScreenItem = NSMenuItem(title: "Break Screen", action: #selector(toggleBreakScreen), keyEquivalent: "")
        breakScreenItem.state = Prefs.breakScreenEnabled ? .on : .off
        breakSubmenu.addItem(breakScreenItem)

        let resumeItem = NSMenuItem(title: "Resume Playback After Break", action: #selector(toggleResumeAfterBreak), keyEquivalent: "")
        resumeItem.state = Prefs.resumeAfterBreak ? .on : .off
        breakSubmenu.addItem(resumeItem)

        breakSubmenu.addItem(NSMenuItem.separator())

        let displayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let displaySubmenu = NSMenu(title: "Display")
        for (label, value) in [("All Screens", "all"), ("Built-in", "builtin"), ("External", "external")] {
            let item = NSMenuItem(title: label, action: #selector(setCountdownScreen(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.countdownScreen == value ? .on : .off
            displaySubmenu.addItem(item)
        }
        displayItem.submenu = displaySubmenu
        breakSubmenu.addItem(displayItem)

        let posItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let posSubmenu = NSMenu(title: "Position")
        for (label, value) in [("Top Right", "topRight"), ("Top Left", "topLeft"), ("Bottom Right", "bottomRight"), ("Bottom Left", "bottomLeft")] {
            let item = NSMenuItem(title: label, action: #selector(setCountdownPosition(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.countdownPosition == value ? .on : .off
            posSubmenu.addItem(item)
        }
        posItem.submenu = posSubmenu
        breakSubmenu.addItem(posItem)

        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let styleSubmenu = NSMenu(title: "Style")
        let overlayColorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let overlayColorSubmenu = NSMenu(title: "Color")
        for name in ["Green", "Blue", "Red", "Orange", "White", "Purple"] {
            let item = NSMenuItem(title: name, action: #selector(setCountdownColor(_:)), keyEquivalent: "")
            item.representedObject = name as AnyObject
            item.state = Prefs.countdownColor == name ? .on : .off
            overlayColorSubmenu.addItem(item)
        }
        overlayColorItem.submenu = overlayColorSubmenu
        styleSubmenu.addItem(overlayColorItem)
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeSubmenu = NSMenu(title: "Size")
        for name in ["Compact", "Normal", "Large"] {
            let item = NSMenuItem(title: name, action: #selector(setCountdownSize(_:)), keyEquivalent: "")
            item.representedObject = name as AnyObject
            item.state = Prefs.countdownSize == name ? .on : .off
            sizeSubmenu.addItem(item)
        }
        sizeItem.submenu = sizeSubmenu
        styleSubmenu.addItem(sizeItem)
        styleItem.submenu = styleSubmenu
        breakSubmenu.addItem(styleItem)

        breakItem.submenu = breakSubmenu
        return breakItem
    }

    // MARK: - Clock (Overlays)

    func makeClockMenuItem() -> NSMenuItem {
        let clockItem = NSMenuItem(title: "Clock", action: nil, keyEquivalent: "")
        let clockSubmenu = NSMenu(title: "Clock")

        let clockToggle = NSMenuItem(title: "Show Clock", action: #selector(toggleClockOverlay), keyEquivalent: "")
        clockToggle.state = !clockWindows.isEmpty ? .on : .off
        clockSubmenu.addItem(clockToggle)

        let clockDateToggle = NSMenuItem(title: "Show Date", action: #selector(toggleClockDate), keyEquivalent: "")
        clockDateToggle.state = Prefs.clockShowDate ? .on : .off
        clockSubmenu.addItem(clockDateToggle)

        let clock24hToggle = NSMenuItem(title: "24-Hour Time", action: #selector(toggleClock24h), keyEquivalent: "")
        clock24hToggle.state = Prefs.clockFormat24h ? .on : .off
        clockSubmenu.addItem(clock24hToggle)

        let clockSecondsToggle = NSMenuItem(title: "Show Seconds", action: #selector(toggleClockSeconds), keyEquivalent: "")
        clockSecondsToggle.state = Prefs.clockShowSeconds ? .on : .off
        clockSubmenu.addItem(clockSecondsToggle)

        clockSubmenu.addItem(NSMenuItem.separator())

        let clockDisplayItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        let clockDisplaySubmenu = NSMenu(title: "Display")
        for (label, value) in [("All Screens", "all"), ("Built-in", "builtin"), ("External", "external")] {
            let item = NSMenuItem(title: label, action: #selector(setClockScreen(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.clockScreen == value ? .on : .off
            clockDisplaySubmenu.addItem(item)
        }
        clockDisplayItem.submenu = clockDisplaySubmenu
        clockSubmenu.addItem(clockDisplayItem)

        let clockPositionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let clockPositionSubmenu = NSMenu(title: "Position")
        for (label, value) in [("Top Right", "topRight"), ("Top Left", "topLeft"), ("Bottom Right", "bottomRight"), ("Bottom Left", "bottomLeft")] {
            let item = NSMenuItem(title: label, action: #selector(setClockPosition(_:)), keyEquivalent: "")
            item.representedObject = value as AnyObject
            item.state = Prefs.clockPosition == value ? .on : .off
            clockPositionSubmenu.addItem(item)
        }
        clockPositionItem.submenu = clockPositionSubmenu
        clockSubmenu.addItem(clockPositionItem)

        let clockColorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let clockColorSubmenu = NSMenu(title: "Color")
        for color in ["Green", "Blue", "Red", "Orange", "White", "Purple"] {
            let item = NSMenuItem(title: color, action: #selector(setClockColor(_:)), keyEquivalent: "")
            item.representedObject = color as AnyObject
            item.state = Prefs.clockColor == color ? .on : .off
            clockColorSubmenu.addItem(item)
        }
        clockColorItem.submenu = clockColorSubmenu
        clockSubmenu.addItem(clockColorItem)

        let clockSizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let clockSizeSubmenu = NSMenu(title: "Size")
        for size in ["Compact", "Normal", "Large"] {
            let item = NSMenuItem(title: size, action: #selector(setClockSize(_:)), keyEquivalent: "")
            item.representedObject = size as AnyObject
            item.state = Prefs.clockSize == size ? .on : .off
            clockSizeSubmenu.addItem(item)
        }
        clockSizeItem.submenu = clockSizeSubmenu
        clockSubmenu.addItem(clockSizeItem)

        clockItem.submenu = clockSubmenu
        return clockItem
    }

    // MARK: - Lock (Overlays)

    func makeLockMenuItem() -> NSMenuItem {
        let lockItem = NSMenuItem(title: "Lock Screen", action: nil, keyEquivalent: "")
        let lockSubmenu = NSMenu(title: "Lock Screen")

        let lockNowItem = NSMenuItem(title: "Lock Now", action: #selector(lockScreenNow), keyEquivalent: "L")
        lockNowItem.keyEquivalentModifierMask = [.command, .shift]
        lockNowItem.isEnabled = Prefs.hasLockPassword
        lockSubmenu.addItem(lockNowItem)

        lockSubmenu.addItem(NSMenuItem.separator())

        let setPassTitle = Prefs.hasLockPassword ? "Change Password..." : "Set Password..."
        let setPassItem = NSMenuItem(title: setPassTitle, action: #selector(showSetPasswordDialog), keyEquivalent: "")
        lockSubmenu.addItem(setPassItem)

        if Prefs.hasLockPassword {
            let clearItem = NSMenuItem(title: "Clear Password", action: #selector(clearLockPasswordAction), keyEquivalent: "")
            lockSubmenu.addItem(clearItem)
        }

        lockItem.submenu = lockSubmenu
        return lockItem
    }

    // MARK: - Sleep (Overlays)

    func makeSleepMenuItem() -> NSMenuItem {
        let sleepItem = NSMenuItem(title: "Sleep", action: nil, keyEquivalent: "")
        let sleepSubmenu = NSMenu(title: "Sleep")

        if let endDate = sleepEndDate {
            let remaining = max(0, Int(endDate.timeIntervalSinceNow))
            let mins = remaining / 60
            let secs = remaining % 60
            let countdownItem = NSMenuItem(title: String(format: "  Sleep in %d:%02d", mins, secs), action: nil, keyEquivalent: "")
            countdownItem.isEnabled = false
            sleepSubmenu.addItem(countdownItem)
            let cancelItem = NSMenuItem(title: "Cancel Sleep Timer", action: #selector(cancelSleepTimer), keyEquivalent: "")
            sleepSubmenu.addItem(cancelItem)
        } else {
            let sleepNowItem = NSMenuItem(title: "Sleep Now", action: #selector(sleepNow), keyEquivalent: "")
            sleepSubmenu.addItem(sleepNowItem)

            sleepSubmenu.addItem(NSMenuItem.separator())

            for minutes in [90, 60, 45, 30, 15] {
                let item = NSMenuItem(title: "Sleep in \(minutes) min", action: #selector(startSleepTimer(_:)), keyEquivalent: "")
                item.representedObject = minutes as AnyObject
                sleepSubmenu.addItem(item)
            }
            let customSleepItem = NSMenuItem(title: "Custom...", action: #selector(startCustomSleepTimer), keyEquivalent: "")
            sleepSubmenu.addItem(customSleepItem)
        }

        sleepSubmenu.addItem(NSMenuItem.separator())
        let sleepAfterItem = NSMenuItem(title: "Sleep After Playback", action: #selector(toggleSleepAfterPlayback), keyEquivalent: "")
        sleepAfterItem.state = sleepAfterPlayback ? .on : .off
        sleepAfterItem.isEnabled = isPlaying || sleepAfterPlayback
        sleepSubmenu.addItem(sleepAfterItem)

        let sleepCountdownItem = NSMenuItem(title: "Countdown Overlay", action: #selector(toggleSleepCountdown), keyEquivalent: "")
        sleepCountdownItem.state = Prefs.sleepCountdownEnabled ? .on : .off
        sleepSubmenu.addItem(sleepCountdownItem)

        let resumeAfterSleepItem = NSMenuItem(title: "Resume Playback After Wake", action: #selector(toggleResumeAfterSleep), keyEquivalent: "")
        resumeAfterSleepItem.state = Prefs.resumeAfterSleep ? .on : .off
        sleepSubmenu.addItem(resumeAfterSleepItem)

        sleepItem.submenu = sleepSubmenu
        return sleepItem
    }
}

// MARK: - Menu Delegate (rebuild menu each time to detect screen changes)

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = buildMenu()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }
}

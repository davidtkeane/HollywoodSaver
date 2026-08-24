import Cocoa

// MARK: - Menu Construction & Delegate

extension AppDelegate {

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Version info / Update available
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
            menu.addItem(NSMenuItem.separator())
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
            menu.addItem(NSMenuItem.separator())
        }

        // If ambient mode is active, show stop option at the top
        if currentMode == .ambient, let name = nowPlayingName {
            let stopItem = NSMenuItem(title: "Stop \(name)", action: #selector(stopPlaying), keyEquivalent: "")
            menu.addItem(stopItem)
            menu.addItem(NSMenuItem.separator())
        }

        let media = findMedia()
        let screens = NSScreen.screens
        let builtIn = screens.first { $0.localizedName.contains("Built") }
        let externals = screens.filter { !$0.localizedName.contains("Built") }

        if media.isEmpty {
            let item = NSMenuItem(title: "No media found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let hint = NSMenuItem(title: "Add .mp4/.gif files next to the app", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        } else if media.count == 1 {
            selectedMedia = media[0]
            let name = displayName(for: media[0])
            let header = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(NSMenuItem.separator())
            addScreenItems(to: menu, file: media[0], builtIn: builtIn, externals: externals)
        } else {
            // Sequential Playlist & Shuffle options
            let playlistItem = NSMenuItem(title: "Play All (Sequential)", action: #selector(playAllVideosSequential), keyEquivalent: "")
            menu.addItem(playlistItem)

            let shuffleItem = NSMenuItem(title: "Shuffle Random", action: #selector(playShuffle), keyEquivalent: "")
            menu.addItem(shuffleItem)
            menu.addItem(NSMenuItem.separator())

            for file in media {
                let name = displayName(for: file)
                let submenu = NSMenu()
                addScreenItems(to: submenu, file: file, builtIn: builtIn, externals: externals)

                let menuItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                menuItem.submenu = submenu
                menu.addItem(menuItem)
            }
        }

        // Per-Display Setup (when multiple monitors attached)
        if screens.count > 1 {
            menu.addItem(NSMenuItem.separator())
            let displaysItem = NSMenuItem(title: "Displays (\(screens.count))", action: nil, keyEquivalent: "")
            let displaysSubmenu = NSMenu(title: "Displays")

            for screen in screens {
                let screenSubmenu = NSMenu()
                let active = mediaPlaying(on: screen)

                let statusTitle = active != nil ? "● Playing: \(displayName(for: active!.media)) (\(active!.mode == .ambient ? "Ambient" : "Screensaver"))" : "○ Status: Idle"
                let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
                statusItem.isEnabled = false
                screenSubmenu.addItem(statusItem)
                screenSubmenu.addItem(NSMenuItem.separator())

                // Quick Assign: Matrix Rain
                let matrixScreenItem = NSMenuItem(title: "Matrix Rain", action: nil, keyEquivalent: "")
                let matrixScreenMenu = NSMenu()
                let matrixSav = NSMenuItem(title: "Screensaver", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
                matrixSav.representedObject = (AppDelegate.matrixRainSentinel, [screen]) as AnyObject
                let matrixAmb = NSMenuItem(title: "Ambient", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
                matrixAmb.representedObject = (AppDelegate.matrixRainSentinel, [screen]) as AnyObject
                matrixScreenMenu.addItem(matrixSav)
                matrixScreenMenu.addItem(matrixAmb)
                matrixScreenItem.submenu = matrixScreenMenu
                screenSubmenu.addItem(matrixScreenItem)

                // Quick Assign: Starfield Warp
                let starfieldScreenItem = NSMenuItem(title: "Starfield Warp", action: nil, keyEquivalent: "")
                let starfieldScreenMenu = NSMenu()
                let starfieldSav = NSMenuItem(title: "Screensaver", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
                starfieldSav.representedObject = (AppDelegate.starfieldWarpSentinel, [screen]) as AnyObject
                let starfieldAmb = NSMenuItem(title: "Ambient", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
                starfieldAmb.representedObject = (AppDelegate.starfieldWarpSentinel, [screen]) as AnyObject
                starfieldScreenMenu.addItem(starfieldSav)
                starfieldScreenMenu.addItem(starfieldAmb)
                starfieldScreenItem.submenu = starfieldScreenMenu
                screenSubmenu.addItem(starfieldScreenItem)

                // Quick Assign: GPU Hyperspace ⚡
                let metalScreenItem = NSMenuItem(title: "GPU Hyperspace ⚡", action: nil, keyEquivalent: "")
                let metalScreenMenu = NSMenu()
                let metalSav = NSMenuItem(title: "Screensaver", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
                metalSav.representedObject = (AppDelegate.metalHyperspaceSentinel, [screen]) as AnyObject
                let metalAmb = NSMenuItem(title: "Ambient", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
                metalAmb.representedObject = (AppDelegate.metalHyperspaceSentinel, [screen]) as AnyObject
                metalScreenMenu.addItem(metalSav)
                metalScreenMenu.addItem(metalAmb)
                metalScreenItem.submenu = metalScreenMenu
                screenSubmenu.addItem(metalScreenItem)

                // Quick Assign: Photo Slideshow
                let photoScreenItem = NSMenuItem(title: "Photo Slideshow", action: nil, keyEquivalent: "")
                let photoScreenMenu = NSMenu()
                let photoSav = NSMenuItem(title: "Screensaver", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
                photoSav.representedObject = (AppDelegate.photoSlideshowSentinel, [screen]) as AnyObject
                let photoAmb = NSMenuItem(title: "Ambient", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
                photoAmb.representedObject = (AppDelegate.photoSlideshowSentinel, [screen]) as AnyObject
                photoScreenMenu.addItem(photoSav)
                photoScreenMenu.addItem(photoAmb)
                photoScreenItem.submenu = photoScreenMenu
                screenSubmenu.addItem(photoScreenItem)

                // Videos list
                if !media.isEmpty {
                    screenSubmenu.addItem(NSMenuItem.separator())
                    let videosHeader = NSMenuItem(title: "Videos & GIFs", action: nil, keyEquivalent: "")
                    videosHeader.isEnabled = false
                    screenSubmenu.addItem(videosHeader)

                    for file in media {
                        let name = displayName(for: file)
                        let fileItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                        let fileSubmenu = NSMenu()
                        let sav = NSMenuItem(title: "Screensaver", action: #selector(playMediaOnScreensScreensaver(_:)), keyEquivalent: "")
                        sav.representedObject = (file, [screen]) as AnyObject
                        let amb = NSMenuItem(title: "Ambient", action: #selector(playMediaAmbient(_:)), keyEquivalent: "")
                        amb.representedObject = (file, [screen]) as AnyObject
                        fileSubmenu.addItem(sav)
                        fileSubmenu.addItem(amb)
                        fileItem.submenu = fileSubmenu
                        screenSubmenu.addItem(fileItem)
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
                displaysSubmenu.addItem(screenMenuItem)
            }

            if isPlaying {
                displaysSubmenu.addItem(NSMenuItem.separator())
                let stopAllDisplays = NSMenuItem(title: "Stop All Displays", action: #selector(stopPlaying), keyEquivalent: "")
                displaysSubmenu.addItem(stopAllDisplays)
            }

            displaysItem.submenu = displaysSubmenu
            menu.addItem(displaysItem)
        }

        // Matrix Rain - built-in effect
        menu.addItem(NSMenuItem.separator())
        let matrixItem = NSMenuItem(title: "Matrix Rain", action: nil, keyEquivalent: "")
        let matrixSubmenu = NSMenu()

        // Matrix settings submenu
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let settingsSubmenu = NSMenu()

        // Color Theme
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

        // Speed
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

        // Characters
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

        // Density
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

        // Font Size
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

        // Trail Length
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
        matrixSubmenu.addItem(settingsItem)

        // Rain Effects submenu (sibling of Settings, inside Matrix Rain)
        let rainItem = NSMenuItem(title: "Rain Effects", action: nil, keyEquivalent: "")
        let rainSubmenu = NSMenu(title: "Rain Effects")

        // Rain Behind Windows toggle
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

        // Rain Over Windows toggle
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

        // Display selection for rain effects
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

        // Stop All Rain (only show when at least one rain mode is active)
        if !rainBehindWindows.isEmpty || !rainOverlayWindows.isEmpty {
            rainSubmenu.addItem(NSMenuItem.separator())
            let stopAllRain = NSMenuItem(title: "Stop All Rain", action: #selector(stopAllRainEffects), keyEquivalent: "")
            rainSubmenu.addItem(stopAllRain)
        }

        rainItem.submenu = rainSubmenu
        matrixSubmenu.addItem(rainItem)

        matrixSubmenu.addItem(NSMenuItem.separator())

        // Screen selection for Matrix Rain
        addScreenItems(to: matrixSubmenu, file: AppDelegate.matrixRainSentinel, builtIn: builtIn, externals: externals)

        matrixItem.submenu = matrixSubmenu
        menu.addItem(matrixItem)

        // Starfield Warp - built-in hyperspace effect
        let starfieldItem = NSMenuItem(title: "Starfield Warp", action: nil, keyEquivalent: "")
        let starfieldSubmenu = NSMenu()

        // Starfield settings submenu
        let starfieldSettingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let starfieldSettingsSubmenu = NSMenu()

        // Speed
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

        // Color
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

        // Density
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

        // Backdrop — layered cosmic background (each layer toggleable)
        starfieldSettingsSubmenu.addItem(NSMenuItem.separator())
        let starfieldBackdropItem = NSMenuItem(title: "Backdrop", action: nil, keyEquivalent: "")
        let starfieldBackdropMenu = NSMenu()

        // Backdrop layer toggles — use ToggleMenuItemView so the menu stays
        // open while the user flicks multiple layers on/off to compare.
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

        // Planets submenu with Show toggle + count override
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

        // Comets submenu — passing comets + screen-dive Easter egg
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

        // Debug trigger — forces the dive comet animation NOW for testing
        let triggerDive = NSMenuItem(title: "🎬 Trigger Screen-Dive Now", action: #selector(triggerStarfieldDiveCometNow), keyEquivalent: "")
        cometsMenu.addItem(triggerDive)

        cometsItem.submenu = cometsMenu
        starfieldBackdropMenu.addItem(cometsItem)

        // Spacecraft Easter egg submenu 🛸
        let spacecraftItem = NSMenuItem(title: "Spacecraft 🛸", action: nil, keyEquivalent: "")
        let spacecraftMenu = NSMenu()

        let spacecraftShowItem = NSMenuItem()
        spacecraftShowItem.view = ToggleMenuItemView(title: "Show Spacecraft", isOn: Prefs.starfieldSpacecraft) { newValue in
            Prefs.starfieldSpacecraft = newValue
        }
        spacecraftMenu.addItem(spacecraftShowItem)

        spacecraftMenu.addItem(NSMenuItem.separator())

        // Info header (disabled)
        let shipInfo = NSMenuItem(title: "Rare visitors: Falcon, Enterprise, TARDIS, Serenity, UFO", action: nil, keyEquivalent: "")
        shipInfo.isEnabled = false
        spacecraftMenu.addItem(shipInfo)

        spacecraftMenu.addItem(NSMenuItem.separator())

        // Debug trigger
        let triggerSpacecraft = NSMenuItem(title: "🎬 Spawn Random Spacecraft Now", action: #selector(triggerStarfieldSpacecraftNow), keyEquivalent: "")
        spacecraftMenu.addItem(triggerSpacecraft)

        spacecraftItem.submenu = spacecraftMenu
        starfieldBackdropMenu.addItem(spacecraftItem)

        starfieldBackdropItem.submenu = starfieldBackdropMenu
        starfieldSettingsSubmenu.addItem(starfieldBackdropItem)

        starfieldSettingsItem.submenu = starfieldSettingsSubmenu
        starfieldSubmenu.addItem(starfieldSettingsItem)

        starfieldSubmenu.addItem(NSMenuItem.separator())

        // Screen selection for Starfield Warp
        addScreenItems(to: starfieldSubmenu, file: AppDelegate.starfieldWarpSentinel, builtIn: builtIn, externals: externals)

        starfieldItem.submenu = starfieldSubmenu
        menu.addItem(starfieldItem)

        // GPU Hyperspace Warp - Metal GPU shader effect
        let metalItem = NSMenuItem(title: "GPU Hyperspace ⚡", action: nil, keyEquivalent: "")
        let metalSubmenu = NSMenu()
        addScreenItems(to: metalSubmenu, file: AppDelegate.metalHyperspaceSentinel, builtIn: builtIn, externals: externals)
        metalItem.submenu = metalSubmenu
        menu.addItem(metalItem)

        // Photo Slideshow (Ken Burns) — built-in effect
        let slideshowItem = NSMenuItem(title: "Photo Slideshow 📸", action: nil, keyEquivalent: "")
        let slideshowSubmenu = NSMenu()
        let photoCount = findPhotos().count

        if photoCount == 0 {
            let noPhotos = NSMenuItem(title: "No photos found", action: nil, keyEquivalent: "")
            noPhotos.isEnabled = false
            slideshowSubmenu.addItem(noPhotos)
            let hint = NSMenuItem(title: "Drop .jpg / .png / .heic into photos/", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            slideshowSubmenu.addItem(hint)
        } else {
            let countItem = NSMenuItem(title: "\(photoCount) photo\(photoCount == 1 ? "" : "s") ready", action: nil, keyEquivalent: "")
            countItem.isEnabled = false
            slideshowSubmenu.addItem(countItem)
            slideshowSubmenu.addItem(NSMenuItem.separator())

            // Slideshow Settings submenu
            let slideshowSettingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
            let slideshowSettingsSubmenu = NSMenu()

            // Duration options
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

            // Transition options
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
            slideshowSubmenu.addItem(slideshowSettingsItem)

            slideshowSubmenu.addItem(NSMenuItem.separator())

            // Screen selection for Photo Slideshow (reuses addScreenItems helper)
            addScreenItems(to: slideshowSubmenu, file: AppDelegate.photoSlideshowSentinel, builtIn: builtIn, externals: externals)
        }

        slideshowItem.submenu = slideshowSubmenu
        menu.addItem(slideshowItem)

        // Web / HTML5 Live Wallpapers
        let webItem = NSMenuItem(title: "Web Wallpapers 🌐", action: nil, keyEquivalent: "")
        let webSubmenu = NSMenu()
        let webPages = findWebWallpapers()

        if webPages.isEmpty {
            let noWeb = NSMenuItem(title: "No HTML wallpapers found", action: nil, keyEquivalent: "")
            noWeb.isEnabled = false
            webSubmenu.addItem(noWeb)
            let hint = NSMenuItem(title: "Drop .html files into web/ folder", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            webSubmenu.addItem(hint)
        } else {
            let countItem = NSMenuItem(title: "\(webPages.count) web background\(webPages.count == 1 ? "" : "s") ready", action: nil, keyEquivalent: "")
            countItem.isEnabled = false
            webSubmenu.addItem(countItem)
            webSubmenu.addItem(NSMenuItem.separator())

            for pageURL in webPages {
                let name = displayName(for: pageURL.path)
                let pageMenuItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                let pageSubmenu = NSMenu()
                addScreenItems(to: pageSubmenu, file: pageURL.path, builtIn: builtIn, externals: externals)
                pageMenuItem.submenu = pageSubmenu
                webSubmenu.addItem(pageMenuItem)
            }
        }

        webItem.submenu = webSubmenu
        menu.addItem(webItem)

        // Break Reminder
        menu.addItem(NSMenuItem.separator())
        let breakItem = NSMenuItem(title: "Break Reminder", action: nil, keyEquivalent: "")
        let breakSubmenu = NSMenu(title: "Break Reminder")

        // Session stats
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

            // Custom presets
            let presets = Prefs.customPresets
            if !presets.isEmpty {
                breakSubmenu.addItem(NSMenuItem.separator())
                for mins in presets {
                    let item = NSMenuItem(title: "Start \(mins) min \u{2605}", action: #selector(startBreakTimer(_:)), keyEquivalent: "")
                    item.representedObject = mins as AnyObject
                    breakSubmenu.addItem(item)
                }
            }

            // Manage Presets
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

        // Pomodoro
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

        // Sound settings
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

        // Countdown overlay settings
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

        // Style settings
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
        menu.addItem(breakItem)

        // Clock overlay submenu (top level, between Break Reminder and Lock Screen)
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

        // Clock Display
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

        // Clock Position
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

        // Clock Color
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

        // Clock Size
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
        menu.addItem(clockItem)

        menu.addItem(NSMenuItem.separator())

        // Lock Screen
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
        menu.addItem(lockItem)

        // Sleep (between Lock Screen and Contribute)
        menu.addItem(NSMenuItem.separator())
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
        menu.addItem(sleepItem)

        // Playback / App config toggles (moved to bottom for cleaner feature-first layout)
        menu.addItem(NSMenuItem.separator())

        // Sound toggle
        let soundItem = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.state = Prefs.soundEnabled ? .on : .off
        menu.addItem(soundItem)

        // Volume slider
        let volumeView = SliderMenuView(title: "Volume", minValue: 0, maxValue: 1, currentValue: Double(Prefs.volume)) { newVal in
            Prefs.volume = newVal
            // Update any currently playing video players
            for cv in self.contentViews {
                if let vp = cv as? VideoPlayerView {
                    vp.queuePlayer.volume = newVal
                }
            }
        }
        let volumeMenuItem = NSMenuItem()
        volumeMenuItem.view = volumeView
        menu.addItem(volumeMenuItem)

        // Opacity slider (ambient mode)
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

        // Loop toggle
        let loopItem = NSMenuItem(title: "Loop", action: #selector(toggleLoop), keyEquivalent: "")
        loopItem.state = Prefs.loopEnabled ? .on : .off
        menu.addItem(loopItem)

        // Sequential Playlist toggle
        let playlistToggle = NSMenuItem(title: "Sequential Playlist", action: #selector(togglePlaylistMode), keyEquivalent: "")
        playlistToggle.state = Prefs.playlistMode ? .on : .off
        menu.addItem(playlistToggle)

        // Low Power / Battery Saver Mode toggle
        let lowPowerToggle = NSMenuItem(title: "Battery Saver (30fps)", action: #selector(toggleLowPowerMode), keyEquivalent: "")
        lowPowerToggle.state = Prefs.lowPowerModeEnabled ? .on : .off
        menu.addItem(lowPowerToggle)

        // Auto Play toggle
        let autoPlayItem = NSMenuItem(title: "Auto Play on Launch", action: #selector(toggleAutoPlay), keyEquivalent: "")
        autoPlayItem.state = Prefs.autoPlayEnabled ? .on : .off
        menu.addItem(autoPlayItem)

        // Launch at login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = Prefs.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        // Show in Dock
        let dockItem = NSMenuItem(title: "Show in Dock", action: #selector(toggleDockIcon), keyEquivalent: "")
        dockItem.state = Prefs.showDockIcon ? .on : .off
        menu.addItem(dockItem)

        // Desktop Shortcut
        let desktopItem = NSMenuItem(title: "Desktop Shortcut", action: #selector(toggleDesktopShortcut), keyEquivalent: "")
        desktopItem.state = Prefs.showDesktopShortcut ? .on : .off
        menu.addItem(desktopItem)

        // About
        menu.addItem(NSMenuItem.separator())
        let aboutItem = NSMenuItem(title: "About HollywoodSaver…", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(aboutItem)

        // Contribute
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
        return menu
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

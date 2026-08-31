import Cocoa
import UserNotifications

// MARK: - Break Reminder, Pomodoro & Floating Countdown

extension AppDelegate {

    // MARK: - Break Timer

    @objc func startBreakTimer(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        startBreakWithMinutes(minutes)
    }

    @objc func startCustomBreakTimer() {
        let alert = NSAlert()
        alert.messageText = "Custom Break Timer"
        alert.informativeText = "Enter minutes:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        input.stringValue = "\(Prefs.breakDuration)"
        alert.accessoryView = input
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let mins = Int(input.stringValue), mins > 0, mins <= 1440 {
                startBreakWithMinutes(mins)
            }
        }
    }

    func startBreakWithMinutes(_ minutes: Int) {
        breakTimer?.invalidate()
        breakEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        Prefs.breakDuration = minutes

        // Warning at 5 minutes remaining
        if minutes > 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval((minutes - 5) * 60)) { [weak self] in
                guard self?.breakEndDate != nil else { return }
                self?.sendBreakNotification(title: "Break Reminder", body: "5 minutes until break time!")
            }
        }

        // Timer fires every 1s to update countdown overlay and fires the break screen at end
        breakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self, let endDate = self.breakEndDate else {
                timer.invalidate()
                return
            }
            self.updateCountdownOverlay()
            if Date() >= endDate {
                timer.invalidate()
                self.breakTimer = nil
                self.breakEndDate = nil
                self.showBreakScreen()
            }
        }

        showCountdownOverlay()
    }

    @objc func cancelBreakTimer() {
        breakTimer?.invalidate()
        breakTimer = nil
        breakEndDate = nil
        pomodoroActive = false
        pomodoroOnBreak = false
        hideCountdownOverlay()
    }

    @objc func saveCurrentPreset() {
        var presets = Prefs.customPresets
        let current = Prefs.breakDuration
        if !presets.contains(current) {
            presets.append(current)
            presets.sort(by: >)
            Prefs.customPresets = presets
        }
    }

    @objc func clearPresets() {
        Prefs.customPresets = []
    }

    @objc func toggleBreakSound() {
        Prefs.breakSoundEnabled = !Prefs.breakSoundEnabled
    }

    @objc func toggleBreakScreen() {
        Prefs.breakScreenEnabled = !Prefs.breakScreenEnabled
    }

    @objc func toggleResumeAfterBreak() {
        Prefs.resumeAfterBreak = !Prefs.resumeAfterBreak
    }

    @objc func setBreakSound(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.breakSoundName = value
        NSSound(named: NSSound.Name(value))?.play()
    }

    @objc func setCountdownColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.countdownColor = value
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
    }

    @objc func setCountdownSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.countdownSize = value
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
    }

    // MARK: - Pomodoro

    @objc func startPomodoro() {
        pomodoroActive = true
        pomodoroOnBreak = false
        startBreakWithMinutes(Prefs.pomodoroWork)
    }

    @objc func stopPomodoro() {
        pomodoroActive = false
        pomodoroOnBreak = false
        cancelBreakTimer()
    }

    @objc func setPomodoroWork(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        Prefs.pomodoroWork = value
    }

    @objc func setPomodoroBreak(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        Prefs.pomodoroBreak = value
    }

    // MARK: - Countdown Overlay

    func countdownNSColor() -> NSColor {
        switch Prefs.countdownColor {
        case "Blue": return NSColor(calibratedRed: 0.2, green: 0.6, blue: 1, alpha: 1)
        case "Red": return NSColor(calibratedRed: 1, green: 0.3, blue: 0.3, alpha: 1)
        case "Orange": return NSColor.orange
        case "White": return NSColor.white
        case "Purple": return NSColor(calibratedRed: 0.7, green: 0.4, blue: 1, alpha: 1)
        default: return NSColor(calibratedRed: 0, green: 1, blue: 0.4, alpha: 1)
        }
    }

    func countdownSizeConfig() -> (width: CGFloat, height: CGFloat, fontSize: CGFloat) {
        switch Prefs.countdownSize {
        case "Compact": return (140, 40, 20)
        case "Large": return (240, 65, 34)
        default: return (180, 50, 26)
        }
    }

    func showCountdownOverlay() {
        hideCountdownOverlay()

        let sizeConfig = countdownSizeConfig()
        let size = CGSize(width: sizeConfig.width, height: sizeConfig.height)
        let color = countdownNSColor()
        let padding: CGFloat = 20
        let menuBarHeight: CGFloat = 25

        for screen in targetScreens(for: Prefs.countdownScreen) {
            let origin: NSPoint
            switch Prefs.countdownPosition {
            case "topLeft":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.maxY - size.height - padding - menuBarHeight)
            case "bottomRight":
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.minY + padding)
            case "bottomLeft":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.minY + padding)
            default: // topRight
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.maxY - size.height - padding - menuBarHeight)
            }

            let overlay = CountdownOverlayView(frame: NSRect(origin: .zero, size: size), fontSize: sizeConfig.fontSize, color: color)
            let window = createFloatingOverlayWindow(rect: NSRect(origin: origin, size: size), content: overlay)
            window.orderFrontRegardless()
            countdownWindows.append(window)
        }

        updateCountdownOverlay()
    }

    func hideCountdownOverlay() {
        for window in countdownWindows {
            window.orderOut(nil)
        }
        countdownWindows.removeAll()
    }

    func updateCountdownOverlay() {
        guard let endDate = breakEndDate else {
            hideCountdownOverlay()
            return
        }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow))
        let subtitle = pomodoroActive ? (pomodoroOnBreak ? "Break" : "Work") : "Break in"
        for window in countdownWindows {
            (window.contentView as? CountdownOverlayView)?.update(remaining: remaining, subtitle: subtitle)
        }
    }

    @objc func setCountdownScreen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.countdownScreen = value
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
    }

    @objc func setCountdownPosition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        Prefs.countdownPosition = value
        if !countdownWindows.isEmpty {
            showCountdownOverlay()
        }
    }

    // MARK: - Fullscreen Break Screen

    func showBreakScreen() {
        // Skip if lock screen is active
        guard !lockScreenActive else { return }

        // Save current playback state for resume after break
        if isPlaying {
            savedMediaBeforeBreak = currentMediaPath
            savedModeBeforeBreak = currentMode
            stopPlaying()
        }

        // Remove floating countdown overlay (break screen replaces it)
        hideCountdownOverlay()

        // Track break stats
        Prefs.breaksTakenToday += 1
        Prefs.totalBreaksTaken += 1

        // Play break sound
        if Prefs.breakSoundEnabled {
            NSSound(named: NSSound.Name(Prefs.breakSoundName))?.play()
        }

        // Send notification
        sendBreakNotification(title: "Time for a Break!", body: "You've been working hard. Step away for a few minutes.")

        // Skip fullscreen break screen if disabled (countdown-only mode)
        if !Prefs.breakScreenEnabled {
            // Still handle Pomodoro cycling via dismissBreakScreen
            if pomodoroActive {
                dismissBreakScreen()
            }
            return
        }

        // Create fullscreen break overlay on all screens
        for screen in NSScreen.screens {
            let window = ScreensaverWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
            window.hasShadow = false
            window.ignoresMouseEvents = false

            // Create the break message view
            let breakView = BreakReminderView(frame: screen.frame)
            window.contentView = breakView

            window.makeKeyAndOrderFront(nil)
            screensaverWindows.append(window)
        }

        // Set up input monitoring to dismiss on click/key/mouse
        if inputMonitor == nil {
            inputMonitor = InputMonitor { [weak self] _ in
                self?.dismissBreakScreen()
            }
        }
        inputMonitor?.start()

        // Auto-dismiss after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if !(self?.screensaverWindows.isEmpty ?? true) {
                self?.dismissBreakScreen()
            }
        }
    }

    func dismissBreakScreen() {
        inputMonitor?.stop()
        inputMonitor = nil
        for window in screensaverWindows {
            window.orderOut(nil)
        }
        screensaverWindows.removeAll()
        contentViews.removeAll()

        // Pomodoro auto-cycle
        if pomodoroActive {
            if pomodoroOnBreak {
                // Break phase done → start work phase
                pomodoroOnBreak = false
                startBreakWithMinutes(Prefs.pomodoroWork)
            } else {
                // Work phase done → start break phase
                pomodoroOnBreak = true
                startBreakWithMinutes(Prefs.pomodoroBreak)
            }
        }

        // Resume playback if it was active before break
        if Prefs.resumeAfterBreak, let media = savedMediaBeforeBreak, let mode = savedModeBeforeBreak {
            savedMediaBeforeBreak = nil
            savedModeBeforeBreak = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startPlaying(media: media, on: NSScreen.screens, mode: mode)
            }
        } else {
            savedMediaBeforeBreak = nil
            savedModeBeforeBreak = nil
        }
    }
}

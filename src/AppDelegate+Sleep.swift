import Cocoa
import IOKit.pwr_mgt

// MARK: - Sleep Management

extension AppDelegate {

    func putMacToSleep() {
        // Save playback state for resume after wake
        if isPlaying {
            savedMediaBeforeSleep = currentMediaPath
            savedModeBeforeSleep = currentMode
        }
        stopPlaying()
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    @objc func sleepNow() {
        putMacToSleep()
    }

    @objc func startSleepTimer(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        startSleepWithMinutes(minutes)
    }

    @objc func startCustomSleepTimer() {
        let alert = NSAlert()
        alert.messageText = "Sleep Timer"
        alert.informativeText = "Enter minutes until sleep:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        input.stringValue = "30"
        alert.accessoryView = input
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let mins = Int(input.stringValue), mins > 0, mins <= 1440 {
                startSleepWithMinutes(mins)
            }
        }
    }

    func startSleepWithMinutes(_ minutes: Int) {
        cancelSleepTimer()
        sleepEndDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        showSleepCountdownOverlay()

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self, let endDate = self.sleepEndDate else {
                timer.invalidate()
                return
            }
            let remaining = Int(endDate.timeIntervalSinceNow)
            if remaining <= 0 {
                timer.invalidate()
                self.sleepTimer = nil
                self.sleepEndDate = nil
                self.hideSleepCountdownOverlay()
                self.putMacToSleep()
            } else {
                self.updateSleepCountdownOverlay()
                if remaining == 300 {
                    self.sendBreakNotification(title: "Sleep Timer", body: "Mac will sleep in 5 minutes")
                } else if remaining == 60 {
                    self.sendBreakNotification(title: "Sleep Timer", body: "Mac will sleep in 1 minute")
                }
            }
        }
    }

    @objc func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepEndDate = nil
        sleepAfterPlayback = false
        hideSleepCountdownOverlay()
    }

    @objc func toggleSleepAfterPlayback() {
        sleepAfterPlayback = !sleepAfterPlayback
    }

    @objc func toggleResumeAfterSleep() {
        Prefs.resumeAfterSleep = !Prefs.resumeAfterSleep
    }

    @objc func toggleSleepCountdown() {
        Prefs.sleepCountdownEnabled = !Prefs.sleepCountdownEnabled
        if Prefs.sleepCountdownEnabled && sleepEndDate != nil {
            showSleepCountdownOverlay()
        } else {
            hideSleepCountdownOverlay()
        }
    }

    func showSleepCountdownOverlay() {
        hideSleepCountdownOverlay()
        guard Prefs.sleepCountdownEnabled else { return }

        let sizeConfig = countdownSizeConfig()
        let size = CGSize(width: sizeConfig.width, height: sizeConfig.height)
        let padding: CGFloat = 20
        let sleepColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)

        for screen in targetScreens(for: Prefs.countdownScreen) {
            // Sleep countdown goes in the opposite corner from break countdown
            let origin: NSPoint
            switch Prefs.countdownPosition {
            case "topLeft":
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.minY + padding)
            case "bottomRight":
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.maxY - size.height - padding - 25)
            case "bottomLeft":
                origin = NSPoint(x: screen.frame.maxX - size.width - padding,
                                 y: screen.frame.maxY - size.height - padding - 25)
            default: // topRight — sleep goes to bottomLeft
                origin = NSPoint(x: screen.frame.minX + padding,
                                 y: screen.frame.minY + padding)
            }

            let overlay = CountdownOverlayView(frame: NSRect(origin: .zero, size: size), fontSize: sizeConfig.fontSize, color: sleepColor)
            let window = createFloatingOverlayWindow(rect: NSRect(origin: origin, size: size), content: overlay)
            window.orderFrontRegardless()
            sleepCountdownWindows.append(window)
        }

        updateSleepCountdownOverlay()
    }

    func hideSleepCountdownOverlay() {
        for window in sleepCountdownWindows {
            window.orderOut(nil)
        }
        sleepCountdownWindows.removeAll()
    }

    func updateSleepCountdownOverlay() {
        guard let endDate = sleepEndDate else {
            hideSleepCountdownOverlay()
            return
        }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow))
        for window in sleepCountdownWindows {
            (window.contentView as? CountdownOverlayView)?.update(remaining: remaining, subtitle: "Sleep in")
        }
    }
}

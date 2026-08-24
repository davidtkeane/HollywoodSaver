import Cocoa

// MARK: - Lock Screen Management

extension AppDelegate {

    @objc func lockScreenNow() {
        guard Prefs.hasLockPassword, !lockScreenActive else { return }

        // Dismiss break screen if showing
        if !screensaverWindows.isEmpty && breakEndDate == nil && currentMode == nil {
            dismissBreakScreen()
        }
        // Stop any active screensaver/ambient
        if isPlaying { stopPlaying() }

        lockScreenActive = true

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled],
            reason: "Screen locked"
        )

        let screens = NSScreen.screens
        let primaryScreen = NSScreen.main ?? screens[0]

        for screen in screens {
            let window = ScreensaverWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .init(rawValue: Int(CGShieldingWindowLevel()) + 1)
            window.isOpaque = false
            window.backgroundColor = .black
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let isPrimary = (screen == primaryScreen)
            let lockView = LockScreenView(frame: screen.frame, isPasswordScreen: isPrimary) { [weak self] in
                self?.unlockScreen()
            }
            window.contentView = lockView
            lockView.startMatrixRain()

            window.makeKeyAndOrderFront(nil)
            lockScreenWindows.append(window)

            if isPrimary {
                lockView.focusPasswordField()
            }
        }

        NSCursor.hide()
        NSApp.activate(ignoringOtherApps: true)
    }

    func unlockScreen() {
        lockScreenActive = false
        NSCursor.unhide()

        for window in lockScreenWindows {
            (window.contentView as? LockScreenView)?.stopMatrixRain()
            window.orderOut(nil)
        }
        lockScreenWindows.removeAll()

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    @objc func showSetPasswordDialog() {
        let alert = NSAlert()
        alert.alertStyle = .informational

        let width: CGFloat = 260

        if Prefs.hasLockPassword {
            alert.messageText = "Change Lock Password"
            alert.informativeText = "Enter your current password and choose a new one."

            let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 96))

            let currentLabel = NSTextField(labelWithString: "Current:")
            currentLabel.frame = NSRect(x: 0, y: 70, width: 70, height: 20)
            container.addSubview(currentLabel)

            let currentField = NSSecureTextField(frame: NSRect(x: 72, y: 68, width: width - 72, height: 24))
            container.addSubview(currentField)

            let newLabel = NSTextField(labelWithString: "New:")
            newLabel.frame = NSRect(x: 0, y: 38, width: 70, height: 20)
            container.addSubview(newLabel)

            let newField = NSSecureTextField(frame: NSRect(x: 72, y: 36, width: width - 72, height: 24))
            container.addSubview(newField)

            let confirmLabel = NSTextField(labelWithString: "Confirm:")
            confirmLabel.frame = NSRect(x: 0, y: 6, width: 70, height: 20)
            container.addSubview(confirmLabel)

            let confirmField = NSSecureTextField(frame: NSRect(x: 72, y: 4, width: width - 72, height: 24))
            container.addSubview(confirmField)

            alert.accessoryView = container
            alert.addButton(withTitle: "Change")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let currentPass = currentField.stringValue
                let newPass = newField.stringValue
                let confirmPass = confirmField.stringValue

                guard Prefs.verifyLockPassword(currentPass) else {
                    let err = NSAlert()
                    err.messageText = "Incorrect Password"
                    err.informativeText = "The current password you entered is wrong."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                guard !newPass.isEmpty else {
                    let err = NSAlert()
                    err.messageText = "Empty Password"
                    err.informativeText = "Password cannot be empty."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                guard newPass == confirmPass else {
                    let err = NSAlert()
                    err.messageText = "Passwords Don't Match"
                    err.informativeText = "New password and confirmation must match."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                Prefs.setLockPassword(newPass)
            }
        } else {
            alert.messageText = "Set Lock Password"
            alert.informativeText = "Choose a password for the lock screen."

            let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 64))

            let newLabel = NSTextField(labelWithString: "Password:")
            newLabel.frame = NSRect(x: 0, y: 38, width: 70, height: 20)
            container.addSubview(newLabel)

            let newField = NSSecureTextField(frame: NSRect(x: 72, y: 36, width: width - 72, height: 24))
            container.addSubview(newField)

            let confirmLabel = NSTextField(labelWithString: "Confirm:")
            confirmLabel.frame = NSRect(x: 0, y: 6, width: 70, height: 20)
            container.addSubview(confirmLabel)

            let confirmField = NSSecureTextField(frame: NSRect(x: 72, y: 4, width: width - 72, height: 24))
            container.addSubview(confirmField)

            alert.accessoryView = container
            alert.addButton(withTitle: "Set Password")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let newPass = newField.stringValue
                let confirmPass = confirmField.stringValue

                guard !newPass.isEmpty else {
                    let err = NSAlert()
                    err.messageText = "Empty Password"
                    err.informativeText = "Password cannot be empty."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                guard newPass == confirmPass else {
                    let err = NSAlert()
                    err.messageText = "Passwords Don't Match"
                    err.informativeText = "Password and confirmation must match."
                    err.alertStyle = .warning
                    err.runModal()
                    return
                }
                Prefs.setLockPassword(newPass)
            }
        }
    }

    @objc func clearLockPasswordAction() {
        let alert = NSAlert()
        alert.messageText = "Clear Lock Password?"
        alert.informativeText = "This will remove the lock screen password. You won't be able to lock the screen until you set a new one."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            Prefs.clearLockPassword()
        }
    }
}

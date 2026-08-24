import Cocoa
import CryptoKit

// MARK: - About, Support & Version Updates

extension AppDelegate {

    // MARK: - About & Support

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "HollywoodSaver v\(AppDelegate.appVersion)"
        alert.informativeText = """
Video screensaver & live wallpaper engine for macOS

━━━ CONTENT TYPES ━━━
🎬  Videos & GIFs — drop into videos/ and gifs/
🟢  Matrix Rain — built-in (6 themes, 3 speeds)
🌌  Starfield Warp — built-in hyperspace effect
     with 4 backdrop layers + planets + moons +
     comets + spacecraft Easter eggs
📸  Photo Slideshow — Ken Burns effect on your photos

━━━ FEATURES ━━━
• Screensaver + Ambient (live wallpaper) modes
• Multi-screen (built-in, external, or all)
• Break Reminder & Pomodoro timer
• Floating Clock Overlay
• Sleep Timer with resume-on-wake
• Lock Screen (SHA-256 password)
• Secure auto-update via GitHub Releases

━━━ CREDITS ━━━
Created by David Keane (IrishRanger 🎖️)
Cybersecurity Master's student • NCI Dublin
Built with Claude Code (Opus 4.6) — AIRanger

━━━ LICENSE ━━━
© 2026 David Keane — MIT License
Free forever, open source

github.com/davidtkeane/HollywoodSaver
"""
        alert.alertStyle = .informational

        // Try to use the custom app icon if one exists next to the app.
        if let iconPath = iconImagePath(), let icon = NSImage(contentsOfFile: iconPath) {
            alert.icon = icon
        }

        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Open GitHub Repo")
        alert.addButton(withTitle: "View Full README")

        // Menu bar apps need explicit activation for dialogs to come to front.
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        switch response {
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://github.com/davidtkeane/HollywoodSaver")!)
        case .alertThirdButtonReturn:
            // Try the bundled ABOUT.md first, fall back to the on-disk docs/ABOUT.md.
            if let bundled = Bundle.main.url(forResource: "ABOUT", withExtension: "md") {
                NSWorkspace.shared.open(bundled)
            } else {
                let onDiskPath = (appFolder as NSString).appendingPathComponent("docs/ABOUT.md")
                if FileManager.default.fileExists(atPath: onDiskPath) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: onDiskPath))
                } else {
                    NSWorkspace.shared.open(URL(string: "https://github.com/davidtkeane/HollywoodSaver/blob/main/docs/ABOUT.md")!)
                }
            }
        default:
            break
        }
    }

    @objc func openBuyMeACoffee() {
        NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/davidtkeane")!)
    }

    @objc func openH3llcoin() {
        NSWorkspace.shared.open(URL(string: "https://h3llcoin.com/how-to-buy.html")!)
    }

    // MARK: - Version Updates

    @objc func manualCheckForUpdate() {
        checkForUpdates(forceRefresh: true)
        // Show result after a short delay for the network request
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            if let latest = self.latestVersion, self.isNewerVersion(latest, than: AppDelegate.appVersion) {
                self.showUpdateDialog()
            } else {
                let alert = NSAlert()
                alert.messageText = "You're Up to Date"
                alert.informativeText = "HollywoodSaver v\(AppDelegate.appVersion) is the latest version."
                alert.alertStyle = .informational
                alert.runModal()
            }
        }
    }

    func checkForUpdates(forceRefresh: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !forceRefresh && now - Prefs.lastVersionCheckDate < 3600 {
            latestVersion = Prefs.cachedLatestVersion
            return
        }

        // Use Releases API (secure: provides pre-built assets with checksums)
        let urlString = "https://api.github.com/repos/\(AppDelegate.githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            // Fallback to tags API if releases URL fails
            checkForUpdatesFallback()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                // Fallback to tags API on network error
                DispatchQueue.main.async { self.checkForUpdatesFallback() }
                return
            }

            // Try parsing as a single release object
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                // No releases found — fallback to tags
                DispatchQueue.main.async { self.checkForUpdatesFallback() }
                return
            }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // Parse release assets for .app.zip and .sha256
            var zipURL: String?
            var checksumURL: String?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    guard let name = asset["name"] as? String,
                          let downloadURL = asset["browser_download_url"] as? String else { continue }
                    if name.hasSuffix(".app.zip") { zipURL = downloadURL }
                    if name.hasSuffix(".sha256") { checksumURL = downloadURL }
                }
            }

            DispatchQueue.main.async {
                self.latestVersion = remoteVersion
                self.latestReleaseZipURL = zipURL
                self.latestReleaseChecksumURL = checksumURL
                Prefs.cachedLatestVersion = remoteVersion
                Prefs.lastVersionCheckDate = Date().timeIntervalSince1970

                // Send notification if newer version found (once per version)
                if self.isNewerVersion(remoteVersion, than: AppDelegate.appVersion) {
                    if Prefs.lastNotifiedVersion != remoteVersion {
                        Prefs.lastNotifiedVersion = remoteVersion
                        self.sendBreakNotification(
                            title: "HollywoodSaver Update Available",
                            body: "v\(AppDelegate.appVersion) → v\(remoteVersion) — Click the menu bar icon to update."
                        )
                    }
                }
            }
        }.resume()
    }

    // Fallback: use Tags API when no GitHub Releases exist yet
    func checkForUpdatesFallback() {
        let urlString = "https://api.github.com/repos/\(AppDelegate.githubRepo)/tags"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let firstTag = json.first,
                  let tagName = firstTag["name"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            DispatchQueue.main.async {
                self.latestVersion = remoteVersion
                self.latestReleaseZipURL = nil
                self.latestReleaseChecksumURL = nil
                Prefs.cachedLatestVersion = remoteVersion
                Prefs.lastVersionCheckDate = Date().timeIntervalSince1970

                if self.isNewerVersion(remoteVersion, than: AppDelegate.appVersion) {
                    if Prefs.lastNotifiedVersion != remoteVersion {
                        Prefs.lastNotifiedVersion = remoteVersion
                        self.sendBreakNotification(
                            title: "HollywoodSaver Update Available",
                            body: "v\(AppDelegate.appVersion) → v\(remoteVersion) — Click the menu bar icon to update."
                        )
                    }
                }
            }
        }.resume()
    }

    func isNewerVersion(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(remoteParts.count, localParts.count)
        for i in 0..<maxLen {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    @objc func showUpdateDialog() {
        let latest = latestVersion ?? "unknown"
        let alert = NSAlert()
        alert.messageText = "Update Available"

        let hasRelease = latestReleaseZipURL != nil && latestReleaseChecksumURL != nil

        if hasRelease {
            alert.informativeText = """
            Current version: v\(AppDelegate.appVersion)
            Latest version: v\(latest)

            Click "Auto Update" to download and install the new version.
            The update is verified with a SHA-256 checksum for security.

            Or visit the GitHub Releases page to download manually.
            """
        } else {
            alert.informativeText = """
            Current version: v\(AppDelegate.appVersion)
            Latest version: v\(latest)

            Download the latest version from GitHub Releases:
            https://github.com/\(AppDelegate.githubRepo)/releases

            Or update from source:
            cd \(appFolder) && git pull && bash build.sh
            """
        }
        alert.alertStyle = .informational

        if hasRelease {
            alert.addButton(withTitle: "Auto Update")
        }
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if hasRelease && response == .alertFirstButtonReturn {
            performAutoUpdate()
        } else if (!hasRelease && response == .alertFirstButtonReturn) || (hasRelease && response == .alertSecondButtonReturn) {
            NSWorkspace.shared.open(URL(string: "https://github.com/\(AppDelegate.githubRepo)/releases")!)
        }
    }

    @objc func performAutoUpdate() {
        guard let zipURL = latestReleaseZipURL,
              let checksumURL = latestReleaseChecksumURL else { return }
        let currentVersion = AppDelegate.appVersion
        let latest = latestVersion ?? "unknown"

        let script = """
        #!/bin/bash
        set -e
        cd "\(appFolder)"

        echo ""
        echo "========================================="
        echo "  HollywoodSaver Auto-Update"
        echo "  v\(currentVersion) → v\(latest)"
        echo "========================================="
        echo ""

        # Download release
        echo "Downloading HollywoodSaver v\(latest)..."
        curl -L -o /tmp/HollywoodSaver.app.zip "\(zipURL)"
        curl -L -o /tmp/HollywoodSaver.app.zip.sha256 "\(checksumURL)"

        # Verify checksum
        echo ""
        echo "Verifying SHA-256 checksum..."
        EXPECTED=$(cat /tmp/HollywoodSaver.app.zip.sha256 | awk '{print $1}')
        ACTUAL=$(shasum -a 256 /tmp/HollywoodSaver.app.zip | awk '{print $1}')

        if [ "$EXPECTED" != "$ACTUAL" ]; then
            echo ""
            echo "╔══════════════════════════════════════╗"
            echo "║  CHECKSUM MISMATCH — UPDATE ABORTED  ║"
            echo "╚══════════════════════════════════════╝"
            echo ""
            echo "Expected: $EXPECTED"
            echo "Actual:   $ACTUAL"
            echo ""
            echo "The download may be corrupted or tampered with."
            echo "Please download manually from GitHub Releases."
            echo ""
            rm -f /tmp/HollywoodSaver.app.zip /tmp/HollywoodSaver.app.zip.sha256
            echo "Press Enter to close."
            read
            exit 1
        fi
        echo "Checksum verified ✓"

        # Backup current app
        if [ -d "HollywoodSaver.app" ]; then
            BACKUP_NAME="HollywoodSaver-v\(currentVersion).app"
            if [ -d "$BACKUP_NAME" ]; then
                rm -rf "$BACKUP_NAME"
            fi
            cp -R "HollywoodSaver.app" "$BACKUP_NAME"
            echo "Backed up to $BACKUP_NAME"
        fi

        # Install new version
        echo "Installing v\(latest)..."
        unzip -o /tmp/HollywoodSaver.app.zip -d .
        rm -f /tmp/HollywoodSaver.app.zip /tmp/HollywoodSaver.app.zip.sha256

        # Clear version cache
        defaults delete com.rangersmyth.hollywoodsaver lastVersionCheckDate 2>/dev/null || true
        defaults delete com.rangersmyth.hollywoodsaver cachedLatestVersion 2>/dev/null || true
        defaults delete com.rangersmyth.hollywoodsaver lastNotifiedVersion 2>/dev/null || true

        echo ""
        echo "========================================="
        echo "  Update complete! Launching v\(latest)..."
        echo "========================================="
        echo ""
        open "HollywoodSaver.app"
        """

        let tempScript = NSTemporaryDirectory() + "hollywoodsaver_update.sh"
        do {
            try script.write(toFile: tempScript, atomically: true, encoding: .utf8)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", tempScript]
            try chmod.run()
            chmod.waitUntilExit()

            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-a", "Terminal", tempScript]
            try open.run()
            open.waitUntilExit()

            if open.terminationStatus == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    NSApp.terminate(nil)
                }
            } else {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Update Failed"
                errorAlert.informativeText = "Could not open Terminal.\n\nPlease download manually from:\nhttps://github.com/\(AppDelegate.githubRepo)/releases"
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Update Failed"
            errorAlert.informativeText = "Could not start the update process: \(error.localizedDescription)\n\nPlease download manually from:\nhttps://github.com/\(AppDelegate.githubRepo)/releases"
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }
}

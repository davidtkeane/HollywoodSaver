import Cocoa
import CryptoKit

// MARK: - Preferences

class Prefs {
    static let defaults = UserDefaults.standard
    static let volumeKey = "volume"
    static let soundKey = "soundEnabled"
    static let launchAtLoginKey = "launchAtLogin"
    static let opacityKey = "ambientOpacity"

    static var volume: Float {
        get { defaults.object(forKey: volumeKey) != nil ? defaults.float(forKey: volumeKey) : 0.5 }
        set { defaults.set(newValue, forKey: volumeKey) }
    }
    static var soundEnabled: Bool {
        get { defaults.bool(forKey: soundKey) }
        set { defaults.set(newValue, forKey: soundKey) }
    }
    static var launchAtLogin: Bool {
        get { defaults.bool(forKey: launchAtLoginKey) }
        set { defaults.set(newValue, forKey: launchAtLoginKey) }
    }
    static var ambientOpacity: Float {
        get { defaults.object(forKey: opacityKey) != nil ? defaults.float(forKey: opacityKey) : 1.0 }
        set { defaults.set(newValue, forKey: opacityKey) }
    }
    static var loopEnabled: Bool {
        get { defaults.object(forKey: "loopEnabled") != nil ? defaults.bool(forKey: "loopEnabled") : true }
        set { defaults.set(newValue, forKey: "loopEnabled") }
    }
    static var autoPlayEnabled: Bool {
        get { defaults.bool(forKey: "autoPlayEnabled") }
        set { defaults.set(newValue, forKey: "autoPlayEnabled") }
    }
    static var lastMediaFilename: String? {
        get { defaults.string(forKey: "lastMediaFilename") }
        set { defaults.set(newValue, forKey: "lastMediaFilename") }
    }
    static var lastPlayMode: String? {
        get { defaults.string(forKey: "lastPlayMode") }
        set { defaults.set(newValue, forKey: "lastPlayMode") }
    }

    // Matrix Rain preferences
    static var matrixColorTheme: String {
        get { defaults.string(forKey: "matrixColorTheme") ?? "Classic Green" }
        set { defaults.set(newValue, forKey: "matrixColorTheme") }
    }
    static var matrixSpeed: String {
        get { defaults.string(forKey: "matrixSpeed") ?? "Medium" }
        set { defaults.set(newValue, forKey: "matrixSpeed") }
    }
    static var matrixCharacterSet: String {
        get { defaults.string(forKey: "matrixCharacterSet") ?? "Katakana" }
        set { defaults.set(newValue, forKey: "matrixCharacterSet") }
    }
    static var matrixDensity: String {
        get { defaults.string(forKey: "matrixDensity") ?? "Medium" }
        set { defaults.set(newValue, forKey: "matrixDensity") }
    }
    static var matrixFontSize: String {
        get { defaults.string(forKey: "matrixFontSize") ?? "Medium" }
        set { defaults.set(newValue, forKey: "matrixFontSize") }
    }
    static var matrixTrailLength: String {
        get { defaults.string(forKey: "matrixTrailLength") ?? "Medium" }
        set { defaults.set(newValue, forKey: "matrixTrailLength") }
    }

    // Rain Effects
    static var rainOverlayEnabled: Bool {
        get { defaults.bool(forKey: "rainOverlayEnabled") }
        set { defaults.set(newValue, forKey: "rainOverlayEnabled") }
    }
    static var rainOverlayOpacity: Float {
        get { defaults.object(forKey: "rainOverlayOpacity") != nil ? defaults.float(forKey: "rainOverlayOpacity") : 0.15 }
        set { defaults.set(newValue, forKey: "rainOverlayOpacity") }
    }
    static var rainBehindEnabled: Bool {
        get { defaults.bool(forKey: "rainBehindEnabled") }
        set { defaults.set(newValue, forKey: "rainBehindEnabled") }
    }
    static var rainBehindOpacity: Float {
        get { defaults.object(forKey: "rainBehindOpacity") != nil ? defaults.float(forKey: "rainBehindOpacity") : 1.0 }
        set { defaults.set(newValue, forKey: "rainBehindOpacity") }
    }
    static var rainScreen: String {
        get { defaults.string(forKey: "rainScreen") ?? "all" }
        set { defaults.set(newValue, forKey: "rainScreen") }
    }

    // Clock overlay
    static var clockEnabled: Bool {
        get { defaults.bool(forKey: "clockEnabled") }
        set { defaults.set(newValue, forKey: "clockEnabled") }
    }
    static var clockShowDate: Bool {
        get { defaults.bool(forKey: "clockShowDate") }
        set { defaults.set(newValue, forKey: "clockShowDate") }
    }
    static var clockScreen: String {
        get { defaults.string(forKey: "clockScreen") ?? "all" }
        set { defaults.set(newValue, forKey: "clockScreen") }
    }
    static var clockPosition: String {
        get { defaults.string(forKey: "clockPosition") ?? "topLeft" }
        set { defaults.set(newValue, forKey: "clockPosition") }
    }
    static var clockColor: String {
        get { defaults.string(forKey: "clockColor") ?? "Green" }
        set { defaults.set(newValue, forKey: "clockColor") }
    }
    static var clockSize: String {
        get { defaults.string(forKey: "clockSize") ?? "Normal" }
        set { defaults.set(newValue, forKey: "clockSize") }
    }

    // Break reminder
    static var breakDuration: Int {
        get { let v = defaults.integer(forKey: "breakDuration"); return v > 0 ? v : 60 }
        set { defaults.set(newValue, forKey: "breakDuration") }
    }
    static var countdownScreen: String {
        get { defaults.string(forKey: "countdownScreen") ?? "all" }
        set { defaults.set(newValue, forKey: "countdownScreen") }
    }
    static var countdownPosition: String {
        get { defaults.string(forKey: "countdownPosition") ?? "topRight" }
        set { defaults.set(newValue, forKey: "countdownPosition") }
    }
    static var countdownColor: String {
        get { defaults.string(forKey: "countdownColor") ?? "Green" }
        set { defaults.set(newValue, forKey: "countdownColor") }
    }
    static var countdownSize: String {
        get { defaults.string(forKey: "countdownSize") ?? "Normal" }
        set { defaults.set(newValue, forKey: "countdownSize") }
    }
    static var customPresets: [Int] {
        get { defaults.array(forKey: "breakPresets") as? [Int] ?? [] }
        set { defaults.set(newValue, forKey: "breakPresets") }
    }
    static var breakSoundEnabled: Bool {
        get { defaults.object(forKey: "breakSoundEnabled") != nil ? defaults.bool(forKey: "breakSoundEnabled") : true }
        set { defaults.set(newValue, forKey: "breakSoundEnabled") }
    }
    static var breakSoundName: String {
        get { defaults.string(forKey: "breakSoundName") ?? "Glass" }
        set { defaults.set(newValue, forKey: "breakSoundName") }
    }
    static var breakScreenEnabled: Bool {
        get { defaults.object(forKey: "breakScreenEnabled") != nil ? defaults.bool(forKey: "breakScreenEnabled") : true }
        set { defaults.set(newValue, forKey: "breakScreenEnabled") }
    }
    static var resumeAfterBreak: Bool {
        get { defaults.object(forKey: "resumeAfterBreak") != nil ? defaults.bool(forKey: "resumeAfterBreak") : true }
        set { defaults.set(newValue, forKey: "resumeAfterBreak") }
    }
    static var showDockIcon: Bool {
        get { defaults.bool(forKey: "showDockIcon") }
        set { defaults.set(newValue, forKey: "showDockIcon") }
    }
    static var showDesktopShortcut: Bool {
        get { defaults.bool(forKey: "showDesktopShortcut") }
        set { defaults.set(newValue, forKey: "showDesktopShortcut") }
    }
    static var sleepCountdownEnabled: Bool {
        get { defaults.object(forKey: "sleepCountdownEnabled") != nil ? defaults.bool(forKey: "sleepCountdownEnabled") : true }
        set { defaults.set(newValue, forKey: "sleepCountdownEnabled") }
    }
    static var resumeAfterSleep: Bool {
        get { defaults.object(forKey: "resumeAfterSleep") != nil ? defaults.bool(forKey: "resumeAfterSleep") : true }
        set { defaults.set(newValue, forKey: "resumeAfterSleep") }
    }
    static var pomodoroWork: Int {
        get { let v = defaults.integer(forKey: "pomodoroWork"); return v > 0 ? v : 25 }
        set { defaults.set(newValue, forKey: "pomodoroWork") }
    }
    static var pomodoroBreak: Int {
        get { let v = defaults.integer(forKey: "pomodoroBreak"); return v > 0 ? v : 5 }
        set { defaults.set(newValue, forKey: "pomodoroBreak") }
    }
    static var breaksTakenToday: Int {
        get {
            let lastDate = defaults.string(forKey: "breakStatsDate") ?? ""
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())
            if lastDate != today { return 0 }
            return defaults.integer(forKey: "breaksTakenToday")
        }
        set {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            defaults.set(formatter.string(from: Date()), forKey: "breakStatsDate")
            defaults.set(newValue, forKey: "breaksTakenToday")
        }
    }
    static var totalBreaksTaken: Int {
        get { defaults.integer(forKey: "totalBreaksTaken") }
        set { defaults.set(newValue, forKey: "totalBreaksTaken") }
    }

    // Version check cache
    static var lastVersionCheckDate: Double {
        get { defaults.double(forKey: "lastVersionCheckDate") }
        set { defaults.set(newValue, forKey: "lastVersionCheckDate") }
    }
    static var cachedLatestVersion: String? {
        get { defaults.string(forKey: "cachedLatestVersion") }
        set { defaults.set(newValue, forKey: "cachedLatestVersion") }
    }
    static var lastNotifiedVersion: String? {
        get { defaults.string(forKey: "lastNotifiedVersion") }
        set { defaults.set(newValue, forKey: "lastNotifiedVersion") }
    }

    // Lock screen password
    static var lockPasswordHash: String? {
        get { defaults.string(forKey: "lockPasswordHash") }
        set { defaults.set(newValue, forKey: "lockPasswordHash") }
    }
    static var lockPasswordSalt: String? {
        get { defaults.string(forKey: "lockPasswordSalt") }
        set { defaults.set(newValue, forKey: "lockPasswordSalt") }
    }
    static var hasLockPassword: Bool {
        return lockPasswordHash != nil && lockPasswordSalt != nil
    }
    static func setLockPassword(_ password: String) {
        let saltData = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let salt = saltData.map { String(format: "%02x", $0) }.joined()
        let combined = salt + password
        let hash = SHA256.hash(data: Data(combined.utf8))
        lockPasswordSalt = salt
        lockPasswordHash = hash.map { String(format: "%02x", $0) }.joined()
    }
    static func verifyLockPassword(_ password: String) -> Bool {
        guard let salt = lockPasswordSalt, let storedHash = lockPasswordHash else { return false }
        let combined = salt + password
        let hash = SHA256.hash(data: Data(combined.utf8))
        let computed = hash.map { String(format: "%02x", $0) }.joined()
        return computed == storedHash
    }
    static func clearLockPassword() {
        defaults.removeObject(forKey: "lockPasswordHash")
        defaults.removeObject(forKey: "lockPasswordSalt")
    }
}

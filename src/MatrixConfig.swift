import Cocoa

// MARK: - Matrix Rain Configuration

enum MatrixColorTheme: String, CaseIterable {
    case green = "Classic Green"
    case blue = "Blue"
    case red = "Red"
    case amber = "Amber"
    case white = "White"
    case rainbow = "Rainbow"

    var primaryColor: NSColor {
        switch self {
        case .green:   return NSColor(red: 0, green: 1, blue: 0, alpha: 1)
        case .blue:    return NSColor(red: 0.2, green: 0.6, blue: 1, alpha: 1)
        case .red:     return NSColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        case .amber:   return NSColor(red: 1, green: 0.75, blue: 0, alpha: 1)
        case .white:   return NSColor.white
        case .rainbow: return NSColor.green
        }
    }
}

enum MatrixSpeed: String, CaseIterable {
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"

    var updatesPerSecond: Double {
        switch self {
        case .slow:   return 8
        case .medium: return 15
        case .fast:   return 25
        }
    }
}

enum MatrixCharacterSet: String, CaseIterable {
    case katakana = "Katakana"
    case latin = "Latin"
    case numbers = "Numbers"
    case mixed = "Mixed"
}

enum MatrixDensity: String, CaseIterable {
    case light = "Light"
    case medium = "Medium"
    case heavy = "Heavy"

    var columnSkip: Int {
        switch self {
        case .light:  return 3
        case .medium: return 2
        case .heavy:  return 1
        }
    }
}

enum MatrixFontSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var pointSize: CGFloat {
        switch self {
        case .small:  return 10
        case .medium: return 14
        case .large:  return 20
        }
    }
}

enum MatrixTrailLength: String, CaseIterable {
    case short = "Short"
    case medium = "Medium"
    case long = "Long"

    var fadeSteps: Int {
        switch self {
        case .short:  return 8
        case .medium: return 16
        case .long:   return 30
        }
    }
}

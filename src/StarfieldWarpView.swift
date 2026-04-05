import Cocoa
import QuartzCore

// MARK: - Starfield Warp Configuration

enum StarfieldSpeed: String, CaseIterable {
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"
    case lightspeed = "Lightspeed"

    /// Delta-z per frame at 60fps (how fast stars approach the viewer).
    var deltaZPerFrame: CGFloat {
        switch self {
        case .slow:       return 0.004
        case .medium:     return 0.010
        case .fast:       return 0.020
        case .lightspeed: return 0.040
        }
    }
}

enum StarfieldColor: String, CaseIterable {
    case white = "White"
    case blue = "Blue"
    case amber = "Amber"
    case rainbow = "Rainbow"

    func color(for hue: CGFloat, brightness: CGFloat) -> NSColor {
        switch self {
        case .white:
            return NSColor(white: 1, alpha: brightness)
        case .blue:
            return NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: brightness)
        case .amber:
            return NSColor(red: 1.0, green: 0.75, blue: 0.35, alpha: brightness)
        case .rainbow:
            return NSColor(hue: hue, saturation: 0.7, brightness: 1, alpha: brightness)
        }
    }
}

enum StarfieldDensity: String, CaseIterable {
    case light = "Light"
    case medium = "Medium"
    case heavy = "Heavy"

    var starCount: Int {
        switch self {
        case .light:  return 200
        case .medium: return 400
        case .heavy:  return 800
        }
    }
}

// MARK: - Starfield Warp View

/// Hyperspace warp effect — stars streaming outward from screen center, like
/// jumping to lightspeed in Star Wars. Uses 3D perspective projection: each
/// star has an (x, y, z) position, and as z decreases each frame the star
/// appears to accelerate away from the center, stretching into a streak.
class StarfieldWarpView: NSView, ScreensaverContent {
    /// Foreground warp-stars (the streaking hyperspace effect).
    struct Star {
        var x: CGFloat      // world-space, -1...1
        var y: CGFloat      // world-space, -1...1
        var z: CGFloat      // depth, 0...1 (0 = at viewer, 1 = far away)
        var prevScreenX: CGFloat
        var prevScreenY: CGFloat
        var hue: CGFloat    // for rainbow mode
        var hasPrev: Bool   // false after respawn → draw a dot instead of a line
    }

    /// Background cosmic dust — static twinkling stars that fill the void
    /// behind the warp streaks. These don't warp; they sit at fixed screen
    /// positions and pulse their alpha.
    struct BackgroundStar {
        var x: CGFloat              // screen space, 0...bounds.width
        var y: CGFloat              // screen space, 0...bounds.height
        var baseAlpha: CGFloat      // 0.3...1.0
        var twinklePhase: CGFloat   // 0...2π (desyncs stars so they pulse independently)
        var twinkleSpeed: CGFloat   // 0.4...1.8 (Hz-ish, varies per star)
        var size: CGFloat           // 0.8...2.2 pixels
        var isBlueTinted: Bool      // ~12% of stars get a cool blue tint for variety
    }

    var stars: [Star] = []
    var backgroundStars: [BackgroundStar] = []
    var speed: StarfieldSpeed
    var colorTheme: StarfieldColor
    var density: StarfieldDensity

    var displayLink: CVDisplayLink?
    var lastTimestamp: Double = 0

    /// ~300 background stars for ~1920x1080. Scales with frame area for
    /// consistent density on larger displays.
    var backgroundStarCount: Int {
        let area = bounds.width * bounds.height
        let baseArea: CGFloat = 1920 * 1080
        let base: CGFloat = 300
        return max(150, min(600, Int(base * area / baseArea)))
    }

    override init(frame: NSRect) {
        speed = StarfieldSpeed(rawValue: Prefs.starfieldSpeed) ?? .medium
        colorTheme = StarfieldColor(rawValue: Prefs.starfieldColor) ?? .white
        density = StarfieldDensity(rawValue: Prefs.starfieldDensity) ?? .medium

        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        spawnStars()
        spawnBackgroundStars()
    }

    required init?(coder: NSCoder) { fatalError() }

    func spawnStars() {
        stars = (0..<density.starCount).map { _ in
            Star(
                x: CGFloat.random(in: -1...1),
                y: CGFloat.random(in: -1...1),
                z: CGFloat.random(in: 0.05...1),
                prevScreenX: 0,
                prevScreenY: 0,
                hue: CGFloat.random(in: 0...1),
                hasPrev: false
            )
        }
    }

    func spawnBackgroundStars() {
        backgroundStars = (0..<backgroundStarCount).map { _ in
            BackgroundStar(
                x: CGFloat.random(in: 0...bounds.width),
                y: CGFloat.random(in: 0...bounds.height),
                baseAlpha: CGFloat.random(in: 0.3...1.0),
                twinklePhase: CGFloat.random(in: 0...(2 * .pi)),
                twinkleSpeed: CGFloat.random(in: 0.4...1.8),
                size: CGFloat.random(in: 0.8...2.2),
                isBlueTinted: CGFloat.random(in: 0...1) < 0.12  // ~12% blue stars
            )
        }
    }

    // MARK: - Playback lifecycle

    func startPlayback() {
        lastTimestamp = 0

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, inNow, _, _, _, userInfo -> CVReturn in
            let view = Unmanaged<StarfieldWarpView>.fromOpaque(userInfo!).takeUnretainedValue()
            let timestamp = Double(inNow.pointee.videoTime) / Double(inNow.pointee.videoTimeScale)

            if view.lastTimestamp == 0 { view.lastTimestamp = timestamp }
            let dt = timestamp - view.lastTimestamp
            view.lastTimestamp = timestamp

            DispatchQueue.main.async {
                view.updateState(dt: dt)
                view.setNeedsDisplay(view.bounds)
            }
            return kCVReturnSuccess
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, callback, pointer)
        CVDisplayLinkStart(link)
    }

    func stopPlayback() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    // MARK: - Simulation

    func updateState(dt: Double) {
        // Scale speed by frame time so animation speed is consistent regardless
        // of actual framerate (handles 60Hz vs 120Hz ProMotion displays).
        let dz = speed.deltaZPerFrame * CGFloat(dt * 60)

        let centerX = bounds.width / 2
        let centerY = bounds.height / 2
        let scale = min(bounds.width, bounds.height) / 2

        for i in 0..<stars.count {
            // Save old screen projection so draw() can render a streak from
            // the star's previous position to its new (further-out) position.
            if stars[i].z > 0 {
                stars[i].prevScreenX = stars[i].x / stars[i].z * scale + centerX
                stars[i].prevScreenY = stars[i].y / stars[i].z * scale + centerY
                stars[i].hasPrev = true
            }

            stars[i].z -= dz

            // Respawn stars that passed the viewer or flew off-screen.
            let offscreen = stars[i].z <= 0.005
            if offscreen {
                stars[i].x = CGFloat.random(in: -1...1)
                stars[i].y = CGFloat.random(in: -1...1)
                stars[i].z = 1.0
                stars[i].hue = CGFloat.random(in: 0...1)
                stars[i].hasPrev = false   // first frame after spawn: draw dot, not line
            }
        }
    }

    // MARK: - Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        // ──────────────────────────────────────────────
        // BACKDROP LAYER A — Background stars (cosmic dust)
        // Static twinkling dots filling the void behind the warp streaks.
        // Read the pref each frame so the toggle works live.
        // ──────────────────────────────────────────────
        if Prefs.starfieldBackgroundStars {
            let now = CACurrentMediaTime()
            for star in backgroundStars {
                // Twinkle: alpha oscillates between ~50% and 100% of base.
                let pulse = (sin(now * Double(star.twinkleSpeed) + Double(star.twinklePhase)) + 1) / 2
                let alpha = star.baseAlpha * CGFloat(0.5 + pulse * 0.5)

                let color: NSColor
                if star.isBlueTinted {
                    color = NSColor(red: 0.65, green: 0.85, blue: 1.0, alpha: alpha)
                } else {
                    color = NSColor(white: 1.0, alpha: alpha)
                }

                context.setFillColor(color.cgColor)
                context.fillEllipse(in: CGRect(
                    x: star.x - star.size / 2,
                    y: star.y - star.size / 2,
                    width: star.size,
                    height: star.size
                ))
            }
        }

        // ──────────────────────────────────────────────
        // FOREGROUND — Warp streaks
        // ──────────────────────────────────────────────
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2
        let scale = min(bounds.width, bounds.height) / 2

        context.setLineCap(.round)

        for star in stars {
            guard star.z > 0 else { continue }

            let screenX = star.x / star.z * scale + centerX
            let screenY = star.y / star.z * scale + centerY

            // Skip stars that projected off-screen (common near the edges
            // once they're very close to the viewer).
            if screenX < -50 || screenX > bounds.width + 50 ||
               screenY < -50 || screenY > bounds.height + 50 {
                continue
            }

            // Brightness + line thickness scale with proximity (closer = brighter + fatter).
            let proximity = 1 - star.z
            let brightness = max(0.15, min(1, proximity * 1.4))
            let thickness = max(0.5, proximity * 3.5)

            let color = colorTheme.color(for: star.hue, brightness: brightness)
            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)
            context.setLineWidth(thickness)

            if star.hasPrev {
                // Draw the warp streak from previous position to new outer position.
                context.move(to: CGPoint(x: star.prevScreenX, y: star.prevScreenY))
                context.addLine(to: CGPoint(x: screenX, y: screenY))
                context.strokePath()
            } else {
                // First frame after respawn — render as a small dot.
                let dot = max(1, thickness)
                context.fillEllipse(in: CGRect(
                    x: screenX - dot / 2,
                    y: screenY - dot / 2,
                    width: dot,
                    height: dot
                ))
            }
        }
    }
}

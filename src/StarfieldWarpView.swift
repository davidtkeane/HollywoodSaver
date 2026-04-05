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

    /// Distant galaxies — soft elliptical glows painted with radial gradients.
    /// Rotate slowly over time. Each one picks a color palette on spawn.
    struct Galaxy {
        var centerX: CGFloat        // screen space
        var centerY: CGFloat        // screen space
        var width: CGFloat          // major axis (pre-rotation)
        var height: CGFloat         // minor axis (makes it elliptical)
        var baseRotation: CGFloat   // starting angle in radians
        var rotationSpeed: CGFloat  // rad/sec — very slow drift
        var coreColor: NSColor      // bright center of the gradient
        var midColor: NSColor       // mid stop color
        var maxAlpha: CGFloat       // peak alpha so galaxies don't overwhelm warp stars
    }

    /// Planet types — 5 variants, each with its own size range and base color.
    enum PlanetType: CaseIterable {
        case gasGiant      // Jupiter — big, warm amber
        case ringedGiant   // Saturn — cream with ring ellipse
        case iceGiant      // Neptune — deep blue
        case rocky         // Mars — small red-orange
        case alien         // Fantasy — small teal-green

        var sizeRange: ClosedRange<CGFloat> {
            switch self {
            case .gasGiant:    return 80...120
            case .ringedGiant: return 70...100
            case .iceGiant:    return 50...80
            case .rocky:       return 30...50
            case .alien:       return 30...50
            }
        }

        var baseColor: NSColor {
            switch self {
            case .gasGiant:    return NSColor(red: 0.92, green: 0.75, blue: 0.50, alpha: 1)
            case .ringedGiant: return NSColor(red: 0.95, green: 0.85, blue: 0.65, alpha: 1)
            case .iceGiant:    return NSColor(red: 0.35, green: 0.55, blue: 0.90, alpha: 1)
            case .rocky:       return NSColor(red: 0.80, green: 0.35, blue: 0.20, alpha: 1)
            case .alien:       return NSColor(red: 0.40, green: 0.88, blue: 0.55, alpha: 1)
            }
        }

        var hasRing: Bool { self == .ringedGiant }
    }

    /// A planet with optional orbiting moon. Planets are static in position
    /// (they don't drift like nebulae) but moons orbit slowly around them.
    struct Planet {
        var centerX: CGFloat
        var centerY: CGFloat
        var radius: CGFloat
        var type: PlanetType
        var baseColor: NSColor
        var hasMoon: Bool
        var moonDistance: CGFloat      // from planet center
        var moonRadius: CGFloat
        var moonBasePhase: CGFloat     // starting angle in radians
        var moonOrbitSpeed: CGFloat    // rad/sec — slow
    }

    /// Drifting nebula clouds — huge diffuse color blobs that slowly wash
    /// across the scene. Much softer than galaxies (no bright core, very low
    /// alpha), much bigger, and they actually move instead of just rotating.
    struct Nebula {
        var centerX: CGFloat        // screen space — mutates as it drifts
        var centerY: CGFloat
        var velocityX: CGFloat      // px/sec — very slow
        var velocityY: CGFloat      // px/sec
        var radius: CGFloat         // 450–850 px (much bigger than galaxies)
        var color: NSColor          // diffuse wash color
        var maxAlpha: CGFloat       // 0.08–0.16 (very subtle — atmospheric)
        var pulsePhase: CGFloat     // for gentle breathe effect
    }

    /// Atmospheric cloud colors — deep purples, pinks, teals, violets.
    static let nebulaPalettes: [NSColor] = [
        NSColor(red: 0.70, green: 0.30, blue: 0.90, alpha: 1),   // deep purple
        NSColor(red: 0.90, green: 0.40, blue: 0.70, alpha: 1),   // pink/magenta
        NSColor(red: 0.30, green: 0.70, blue: 0.90, alpha: 1),   // teal/cyan
        NSColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1),   // amber/rose
        NSColor(red: 0.50, green: 0.30, blue: 0.85, alpha: 1),   // violet
    ]

    /// Preset color palettes — each galaxy randomly picks one on spawn.
    static let galaxyPalettes: [(core: NSColor, mid: NSColor)] = [
        // Warm spiral — Milky Way / Sombrero vibe
        (NSColor(red: 1.00, green: 0.95, blue: 0.82, alpha: 1),
         NSColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1)),
        // Cool spiral — Andromeda
        (NSColor(red: 0.70, green: 0.85, blue: 1.00, alpha: 1),
         NSColor(red: 0.35, green: 0.25, blue: 0.70, alpha: 1)),
        // Pink nebula — Helix / NGC 2392
        (NSColor(red: 1.00, green: 0.70, blue: 0.90, alpha: 1),
         NSColor(red: 0.70, green: 0.20, blue: 0.55, alpha: 1)),
        // Teal cluster — Cat's Eye vibe
        (NSColor(red: 0.50, green: 1.00, blue: 0.90, alpha: 1),
         NSColor(red: 0.20, green: 0.50, blue: 0.70, alpha: 1)),
        // Amber nebula — Orion-ish
        (NSColor(red: 1.00, green: 0.85, blue: 0.50, alpha: 1),
         NSColor(red: 0.80, green: 0.30, blue: 0.10, alpha: 1)),
    ]

    var stars: [Star] = []
    var backgroundStars: [BackgroundStar] = []
    var galaxies: [Galaxy] = []
    var nebulae: [Nebula] = []
    var planets: [Planet] = []
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
        spawnGalaxies()
        spawnNebulae()
        spawnPlanets()
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

    func spawnGalaxies() {
        galaxies = []
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        // Keep galaxies away from the warp vanishing point so they don't
        // obscure the center (which is where the warp streaks emerge).
        let minDistFromCenter = min(bounds.width, bounds.height) * 0.22
        // Scale inter-galaxy spacing with screen size so the distribution
        // feels right on both a 13" laptop and a 32" external.
        let minDistBetweenGalaxies = min(bounds.width, bounds.height) * 0.28

        // Distance tiers create depth perception: big bright galaxies feel
        // close, small dim ones feel far away. Each tier is (widthRange,
        // heightRange, alphaRange). Count is randomized 2–5 per launch
        // (always 1 NEAR guaranteed + 1–4 random MID/FAR fillers) so each
        // scene has a different cosmic mood.
        typealias Tier = (
            widthRange: ClosedRange<CGFloat>,
            heightRange: ClosedRange<CGFloat>,
            alphaRange: ClosedRange<CGFloat>
        )
        let nearTier: Tier = (480...700, 150...230, 0.40...0.55)
        let midTier:  Tier = (300...440, 100...170, 0.28...0.42)
        let farTier:  Tier = (150...260, 55...110,  0.18...0.30)

        // Always include one NEAR galaxy as the focal point.
        var tiers: [Tier] = [nearTier]
        let extraCount = Int.random(in: 1...4)  // 1–4 extras → total 2–5 galaxies
        for _ in 0..<extraCount {
            // Weight slightly toward mid so the scene isn't mostly tiny specks.
            tiers.append(CGFloat.random(in: 0...1) < 0.6 ? midTier : farTier)
        }
        tiers.shuffle()

        // Track which palettes are used so we get color variety across
        // all galaxies in the scene (no two the same if we can help it).
        var availablePalettes = StarfieldWarpView.galaxyPalettes.shuffled()

        for tier in tiers {
            var posX: CGFloat = 0
            var posY: CGFloat = 0
            var attempts = 0
            let edgePadding: CGFloat = 60
            while attempts < 40 {
                posX = CGFloat.random(in: edgePadding...(bounds.width - edgePadding))
                posY = CGFloat.random(in: edgePadding...(bounds.height - edgePadding))
                let okFromCenter = hypot(posX - cx, posY - cy) >= minDistFromCenter
                let okSpacing = galaxies.allSatisfy { existing in
                    hypot(posX - existing.centerX, posY - existing.centerY) >= minDistBetweenGalaxies
                }
                if okFromCenter && okSpacing { break }
                attempts += 1
            }

            // Pop a palette (refill if exhausted — for 5 galaxies on 5 palettes
            // this means each galaxy gets a unique color).
            if availablePalettes.isEmpty {
                availablePalettes = StarfieldWarpView.galaxyPalettes.shuffled()
            }
            let palette = availablePalettes.removeLast()

            galaxies.append(Galaxy(
                centerX: posX,
                centerY: posY,
                width: CGFloat.random(in: tier.widthRange),
                height: CGFloat.random(in: tier.heightRange),
                baseRotation: CGFloat.random(in: 0...(2 * .pi)),
                rotationSpeed: CGFloat.random(in: 0.01...0.04),
                coreColor: palette.core,
                midColor: palette.mid,
                maxAlpha: CGFloat.random(in: tier.alphaRange)
            ))
        }
    }

    func spawnNebulae() {
        nebulae = []
        let count = 3  // 3 drifting color washes — enough to tint the scene without smothering
        var availableColors = StarfieldWarpView.nebulaPalettes.shuffled()

        for _ in 0..<count {
            if availableColors.isEmpty {
                availableColors = StarfieldWarpView.nebulaPalettes.shuffled()
            }
            let color = availableColors.removeLast()

            // Random drift direction + slow speed (4–12 px/sec). At 12 px/sec
            // a nebula takes about 160 seconds to cross a 1920 px screen.
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 4...12)

            nebulae.append(Nebula(
                centerX: CGFloat.random(in: 0...bounds.width),
                centerY: CGFloat.random(in: 0...bounds.height),
                velocityX: cos(angle) * speed,
                velocityY: sin(angle) * speed,
                radius: CGFloat.random(in: 450...850),
                color: color,
                maxAlpha: CGFloat.random(in: 0.08...0.16),
                pulsePhase: CGFloat.random(in: 0...(2 * .pi))
            ))
        }
    }

    func spawnPlanets() {
        planets = []

        // Count is driven by Prefs: "random" = 0–3 randomly, or a fixed "0"/"1"/"2"/"3".
        let count: Int
        switch Prefs.starfieldPlanetsCount {
        case "0": count = 0
        case "1": count = 1
        case "2": count = 2
        case "3": count = 3
        default:  count = Int.random(in: 0...3)   // "random"
        }
        guard count > 0 else { return }

        // Unique types per planet — draw from a shuffled stack so the
        // same planet type doesn't appear twice in one scene.
        var availableTypes = PlanetType.allCases.shuffled()

        let cx = bounds.width / 2
        let cy = bounds.height / 2
        let minDistFromCenter = min(bounds.width, bounds.height) * 0.22
        let minDistFromGalaxies: CGFloat = 180
        let minDistFromOtherPlanets: CGFloat = 200
        let edgePadding: CGFloat = 90

        for _ in 0..<count {
            if availableTypes.isEmpty {
                availableTypes = PlanetType.allCases.shuffled()
            }
            let type = availableTypes.removeLast()

            var posX: CGFloat = 0
            var posY: CGFloat = 0
            var attempts = 0
            while attempts < 40 {
                posX = CGFloat.random(in: edgePadding...(bounds.width - edgePadding))
                posY = CGFloat.random(in: edgePadding...(bounds.height - edgePadding))
                let okFromCenter = hypot(posX - cx, posY - cy) >= minDistFromCenter
                let okFromGalaxies = galaxies.allSatisfy {
                    hypot(posX - $0.centerX, posY - $0.centerY) >= minDistFromGalaxies
                }
                let okFromPlanets = planets.allSatisfy {
                    hypot(posX - $0.centerX, posY - $0.centerY) >= minDistFromOtherPlanets
                }
                if okFromCenter && okFromGalaxies && okFromPlanets { break }
                attempts += 1
            }

            let radius = CGFloat.random(in: type.sizeRange)
            let hasMoon = CGFloat.random(in: 0...1) < 0.4   // ~40% chance

            planets.append(Planet(
                centerX: posX,
                centerY: posY,
                radius: radius,
                type: type,
                baseColor: type.baseColor,
                hasMoon: hasMoon,
                moonDistance: radius * CGFloat.random(in: 1.8...2.4),
                moonRadius: CGFloat.random(in: 4...9),
                moonBasePhase: CGFloat.random(in: 0...(2 * .pi)),
                moonOrbitSpeed: CGFloat.random(in: 0.08...0.25)  // slow orbit
            ))
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

        // Drift nebulae across the scene and wrap around screen edges
        // (toroidal space — when a nebula goes off one side it re-emerges
        // from the opposite side). Uses dt so drift is framerate-independent.
        let dtF = CGFloat(dt)
        for i in 0..<nebulae.count {
            nebulae[i].centerX += nebulae[i].velocityX * dtF
            nebulae[i].centerY += nebulae[i].velocityY * dtF

            let r = nebulae[i].radius
            if nebulae[i].centerX > bounds.width + r {
                nebulae[i].centerX = -r
            } else if nebulae[i].centerX < -r {
                nebulae[i].centerX = bounds.width + r
            }
            if nebulae[i].centerY > bounds.height + r {
                nebulae[i].centerY = -r
            } else if nebulae[i].centerY < -r {
                nebulae[i].centerY = bounds.height + r
            }
        }
    }

    // MARK: - Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // ──────────────────────────────────────────────
        // BACKDROP LAYER D — Deep Space Gradient
        // Very subtle radial gradient: pure black at center (warp vanishing
        // point stays infinite) → deep purple-blue at edges (distant cosmic
        // haze). When disabled, falls back to pure black fill.
        // ──────────────────────────────────────────────
        if Prefs.starfieldGradient {
            let colors = [
                NSColor.black.cgColor,
                NSColor(red: 0.05, green: 0.04, blue: 0.12, alpha: 1).cgColor
            ]
            let locations: [CGFloat] = [0, 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: locations
            ) {
                let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
                let maxRadius = max(bounds.width, bounds.height) * 0.75
                context.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: maxRadius,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            } else {
                context.setFillColor(NSColor.black.cgColor)
                context.fill(bounds)
            }
        } else {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(bounds)
        }

        // ──────────────────────────────────────────────
        // BACKDROP LAYER C — Nebula Clouds
        // Huge soft color blobs that slowly drift across the scene. Much
        // bigger + softer + more diffuse than galaxies. Very low alpha
        // (0.08–0.16) so they wash the backdrop with color without
        // competing with the foreground warp streaks. 4 color stops for
        // extra-smooth falloff. Gentle pulse via CACurrentMediaTime.
        // ──────────────────────────────────────────────
        if Prefs.starfieldNebulae {
            let nowC = CGFloat(CACurrentMediaTime())
            let nebulaColorSpace = CGColorSpaceCreateDeviceRGB()
            for nebula in nebulae {
                // Subtle breathe — alpha oscillates between 70% and 100% of max.
                let pulse = (sin(nowC * 0.25 + nebula.pulsePhase) + 1) / 2
                let alpha = nebula.maxAlpha * (0.7 + pulse * 0.3)

                let colors = [
                    nebula.color.withAlphaComponent(alpha).cgColor,
                    nebula.color.withAlphaComponent(alpha * 0.6).cgColor,
                    nebula.color.withAlphaComponent(alpha * 0.2).cgColor,
                    NSColor.clear.cgColor
                ]
                let locations: [CGFloat] = [0, 0.35, 0.7, 1]

                if let gradient = CGGradient(
                    colorsSpace: nebulaColorSpace,
                    colors: colors as CFArray,
                    locations: locations
                ) {
                    context.drawRadialGradient(
                        gradient,
                        startCenter: CGPoint(x: nebula.centerX, y: nebula.centerY),
                        startRadius: 0,
                        endCenter: CGPoint(x: nebula.centerX, y: nebula.centerY),
                        endRadius: nebula.radius,
                        options: []
                    )
                }
            }
        }

        // ──────────────────────────────────────────────
        // BACKDROP LAYER B — Distant Galaxies
        // Soft elliptical glows painted with radial gradients. Slowly
        // rotate over time. 4 galaxies per scene, placed away from the
        // warp vanishing point. Rendered between the gradient (back)
        // and the background stars (front), so dust specks sit on top.
        // ──────────────────────────────────────────────
        if Prefs.starfieldGalaxies {
            let now = CGFloat(CACurrentMediaTime())
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            for galaxy in galaxies {
                let rotation = galaxy.baseRotation + now * galaxy.rotationSpeed

                context.saveGState()
                context.translateBy(x: galaxy.centerX, y: galaxy.centerY)
                context.rotate(by: rotation)
                // Scale Y to flatten the circular gradient into an ellipse.
                // Use larger dimension as the "radius" we draw, then scale down.
                let aspectY = galaxy.height / galaxy.width
                context.scaleBy(x: 1, y: aspectY)

                let colors = [
                    galaxy.coreColor.withAlphaComponent(galaxy.maxAlpha).cgColor,
                    galaxy.midColor.withAlphaComponent(galaxy.maxAlpha * 0.45).cgColor,
                    NSColor.clear.cgColor
                ]
                let locations: [CGFloat] = [0, 0.45, 1]

                if let gradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: colors as CFArray,
                    locations: locations
                ) {
                    context.drawRadialGradient(
                        gradient,
                        startCenter: .zero,
                        startRadius: 0,
                        endCenter: .zero,
                        endRadius: galaxy.width / 2,
                        options: []
                    )
                }

                context.restoreGState()
            }
        }

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
        // PLANETS — closer "mid-distance" objects
        // Rendered after background stars (dust sits behind planets) but
        // before warp streaks (so streaks pass over the planets). Each
        // planet has a 3D-lit radial gradient body, optional Saturn ring,
        // and optional slowly orbiting moon.
        // ──────────────────────────────────────────────
        if Prefs.starfieldPlanets && !planets.isEmpty {
            let planetColorSpace = CGColorSpaceCreateDeviceRGB()
            let now = CGFloat(CACurrentMediaTime())

            for planet in planets {
                // 1. Saturn-style ring drawn BEHIND the planet body (back half of the ring).
                if planet.type.hasRing {
                    let ringWidth = planet.radius * 3.6
                    let ringHeight = planet.radius * 0.55
                    context.saveGState()
                    context.translateBy(x: planet.centerX, y: planet.centerY)
                    context.rotate(by: -0.18)   // slight tilt
                    // Back half of ring (behind planet) — slightly dimmer.
                    context.setStrokeColor(NSColor(red: 0.85, green: 0.8, blue: 0.65, alpha: 0.55).cgColor)
                    context.setLineWidth(2.5)
                    context.strokeEllipse(in: CGRect(x: -ringWidth/2, y: -ringHeight/2, width: ringWidth, height: ringHeight))
                    // Inner rim
                    context.setStrokeColor(NSColor(red: 0.95, green: 0.88, blue: 0.70, alpha: 0.35).cgColor)
                    context.setLineWidth(1.0)
                    let inner = CGRect(x: -ringWidth/2 + 5, y: -ringHeight/2 + 1.5, width: ringWidth - 10, height: ringHeight - 3)
                    context.strokeEllipse(in: inner)
                    context.restoreGState()
                }

                // 2. Planet body — 3D gradient (highlight offset to upper-left, shadow at lower-right).
                let highlight = planet.baseColor.blended(withFraction: 0.35, of: .white) ?? planet.baseColor
                let shadow = planet.baseColor.blended(withFraction: 0.55, of: .black) ?? planet.baseColor
                let colors = [
                    highlight.cgColor,
                    planet.baseColor.cgColor,
                    shadow.cgColor
                ]
                let locations: [CGFloat] = [0, 0.55, 1]
                if let gradient = CGGradient(colorsSpace: planetColorSpace, colors: colors as CFArray, locations: locations) {
                    let lightOffset = CGPoint(x: -planet.radius * 0.35, y: planet.radius * 0.35)
                    context.saveGState()
                    // Clip to planet circle so the gradient doesn't bleed past the edge.
                    let planetRect = CGRect(
                        x: planet.centerX - planet.radius,
                        y: planet.centerY - planet.radius,
                        width: planet.radius * 2,
                        height: planet.radius * 2
                    )
                    context.addEllipse(in: planetRect)
                    context.clip()
                    context.drawRadialGradient(
                        gradient,
                        startCenter: CGPoint(x: planet.centerX + lightOffset.x, y: planet.centerY + lightOffset.y),
                        startRadius: 0,
                        endCenter: CGPoint(x: planet.centerX, y: planet.centerY),
                        endRadius: planet.radius,
                        options: []
                    )
                    context.restoreGState()

                    // Subtle darker rim around the whole planet for definition.
                    context.setStrokeColor(NSColor(white: 0, alpha: 0.35).cgColor)
                    context.setLineWidth(0.8)
                    context.strokeEllipse(in: planetRect)
                }

                // 3. Front half of ring (in front of planet body) for ringed giants.
                if planet.type.hasRing {
                    let ringWidth = planet.radius * 3.6
                    let ringHeight = planet.radius * 0.55
                    context.saveGState()
                    context.translateBy(x: planet.centerX, y: planet.centerY)
                    context.rotate(by: -0.18)
                    // Clip to the bottom half so only the "front" of the ring shows over the body.
                    context.clip(to: CGRect(x: -ringWidth, y: 0, width: ringWidth * 2, height: ringHeight))
                    context.setStrokeColor(NSColor(red: 0.95, green: 0.88, blue: 0.70, alpha: 0.75).cgColor)
                    context.setLineWidth(2.5)
                    context.strokeEllipse(in: CGRect(x: -ringWidth/2, y: -ringHeight/2, width: ringWidth, height: ringHeight))
                    context.restoreGState()
                }

                // 4. Orbiting moon — small bright dot that circles the planet over time.
                if planet.hasMoon {
                    let phase = planet.moonBasePhase + now * planet.moonOrbitSpeed
                    let moonX = planet.centerX + cos(phase) * planet.moonDistance
                    let moonY = planet.centerY + sin(phase) * planet.moonDistance
                    // Subtle glow around the moon
                    context.setFillColor(NSColor(white: 0.95, alpha: 0.25).cgColor)
                    context.fillEllipse(in: CGRect(
                        x: moonX - planet.moonRadius * 1.8,
                        y: moonY - planet.moonRadius * 1.8,
                        width: planet.moonRadius * 3.6,
                        height: planet.moonRadius * 3.6
                    ))
                    // Moon body
                    context.setFillColor(NSColor(white: 0.9, alpha: 0.98).cgColor)
                    context.fillEllipse(in: CGRect(
                        x: moonX - planet.moonRadius,
                        y: moonY - planet.moonRadius,
                        width: planet.moonRadius * 2,
                        height: planet.moonRadius * 2
                    ))
                }
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

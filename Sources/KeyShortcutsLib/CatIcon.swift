import Cocoa

/// Custom-drawn cat for the menu bar and app windows, rendered as NSImage frames.
///
/// Asleep (keep-awake off): a curled-up cat that breathes slowly, twitches an
/// ear every few seconds, flicks the tip of its tail, and exhales little "z"
/// glyphs that drift up-right, grow, and fade in a continuous loop.
/// Awake (keep-awake on): the cat strolls across the icon, pauses at each edge
/// to sit down, swish its tail and blink, then strolls back the other way.
/// The stroll and sit poses are also exposed on their own canvases (with a
/// `scale` factor) so app windows can host an ambient wandering cat.
enum CatIcon {
    static let canvasSize = NSSize(width: 34, height: 18)
    /// Canvas width of the walk-in-place stroller frame.
    static let strollerWidth: CGFloat = 22
    /// Canvas width of the sitting-pose frame.
    static let sitWidth: CGFloat = 18
    static let fps: Double = 12

    // MARK: - Public frames (menu bar)

    static func sleepFrame(at t: TimeInterval, tint: NSColor?, scale: CGFloat = 1) -> NSImage {
        render(tint: tint, scale: scale) { color in
            drawCurledCat(at: t, color: color)
            drawZs(floatingZs(at: t), color: color)
        }
    }

    static func sleepStatic(tint: NSColor?, scale: CGFloat = 1) -> NSImage {
        render(tint: tint, scale: scale) { color in
            drawCurledCat(at: 0.8, color: color)
            drawZs([
                Z(x: 15.5, y: 7.0,  size: 5.0, alpha: 0.85),
                Z(x: 20.0, y: 10.0, size: 6.5, alpha: 0.60),
                Z(x: 25.0, y: 13.0, size: 8.0, alpha: 0.40),
            ], color: color)
        }
    }

    /// Menu-bar awake loop: stroll right → sit & blink → stroll left → sit.
    static func walkFrame(at t: TimeInterval, tint: NSColor?) -> NSImage {
        let period: Double = 26
        let ph = t.truncatingRemainder(dividingBy: period)
        return render(tint: tint) { color in
            switch ph {
            case ..<7:      // stroll to the right edge
                let p = CGFloat(ph / 7)
                drawWalkingCat(offsetX: 0.5 + p * 12, facingRight: true,
                               legPhase: CGFloat(t * 7), color: color)
            case ..<13:     // sit at the right edge: tail swish, blinks
                drawSittingCat(offsetX: 16.5, facingRight: true, at: t, color: color)
            case ..<20:     // stroll back to the left edge
                let p = CGFloat((ph - 13) / 7)
                drawWalkingCat(offsetX: 12.5 - p * 12, facingRight: false,
                               legPhase: CGFloat(t * 7), color: color)
            default:        // sit at the left edge
                drawSittingCat(offsetX: 0.3, facingRight: false, at: t, color: color)
            }
        }
    }

    static func walkStatic(tint: NSColor?) -> NSImage {
        render(tint: tint) { color in
            drawWalkingCat(offsetX: 6, facingRight: true, legPhase: 0.8, color: color)
        }
    }

    // MARK: - Public frames (window stroller)

    /// Walk-in-place frame on its own compact canvas; the caller moves it.
    static func strollFrame(at t: TimeInterval, facingRight: Bool,
                            tint: NSColor?, scale: CGFloat = 1) -> NSImage {
        render(size: NSSize(width: strollerWidth, height: canvasSize.height),
               tint: tint, scale: scale) { color in
            drawWalkingCat(offsetX: 0.5, facingRight: facingRight,
                           legPhase: CGFloat(t * 7), color: color)
        }
    }

    /// Sitting cat (tail swish, ear twitch, blinking) on its own canvas.
    static func sitFrame(at t: TimeInterval, facingRight: Bool,
                         tint: NSColor?, scale: CGFloat = 1) -> NSImage {
        render(size: NSSize(width: sitWidth, height: canvasSize.height),
               tint: tint, scale: scale) { color in
            drawSittingCat(offsetX: 0.4, facingRight: facingRight, at: t, color: color)
        }
    }

    // MARK: - Floating z model

    private struct Z {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var alpha: CGFloat
    }

    /// A new z is born every `spawnInterval`; each lives `life` seconds while
    /// rising from the cat's head toward the top-right, growing, swaying, fading.
    private static func floatingZs(at t: TimeInterval) -> [Z] {
        let life: Double = 2.6
        let spawnInterval: Double = 0.9
        var out: [Z] = []
        let newest = Int(t / spawnInterval)
        for i in max(0, newest - 3)...newest {
            let age = t - Double(i) * spawnInterval
            guard age >= 0, age < life else { continue }
            let p = CGFloat(age / life)
            let sway = sin(p * .pi * 2 + CGFloat(i)) * 1.2
            let alpha = p < 0.12 ? p / 0.12 : 1 - (p - 0.12) / 0.88
            out.append(Z(x: 14.5 + p * 11 + sway,
                         y: 5.5 + p * 9,
                         size: 4.5 + p * 3.5,
                         alpha: alpha * 0.9))
        }
        return out
    }

    // MARK: - Rendering

    private static func render(size: NSSize = canvasSize, tint: NSColor?,
                               scale: CGFloat = 1,
                               _ draw: @escaping (NSColor) -> Void) -> NSImage {
        let color = tint ?? .black
        let img = NSImage(size: NSSize(width: size.width * scale,
                                       height: size.height * scale),
                          flipped: false) { _ in
            NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
            draw(color)
            return true
        }
        // Template only when untinted so the system adapts it to the menu bar appearance
        img.isTemplate = (tint == nil)
        return img
    }

    private static func drawZs(_ zs: [Z], color: NSColor) {
        for z in zs where z.alpha > 0.02 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: z.size, weight: .bold),
                .foregroundColor: color.withAlphaComponent(z.alpha),
            ]
            ("z" as NSString).draw(at: NSPoint(x: z.x, y: z.y - z.size / 2), withAttributes: attrs)
        }
    }

    /// Curled sleeping cat: round body that swells with a slow breath, two
    /// ears poking up (the outer one twitches every few seconds), tail
    /// wrapped around the lower edge with an occasional tip flick.
    private static func drawCurledCat(at t: TimeInterval, color: NSColor) {
        color.set()

        // Slow breathing: the body swells from its base
        let rise = CGFloat(sin(t * 2 * .pi / 3.4)) * 0.4

        // Body
        NSBezierPath(ovalIn: NSRect(x: 2.5 - rise * 0.15, y: 1.5,
                                    width: 11 + rise * 0.3, height: 11 + rise)).fill()

        // Ears ride the breath
        let ey = rise * 0.6
        let ear1 = NSBezierPath()
        ear1.move(to: NSPoint(x: 6.4, y: 11.6 + ey))
        ear1.line(to: NSPoint(x: 8.6, y: 12.2 + ey))
        ear1.line(to: NSPoint(x: 6.8, y: 14.7 + ey))
        ear1.close()
        ear1.fill()

        // Outer ear twitches briefly every few seconds
        let eph = t.truncatingRemainder(dividingBy: 6.4)
        let twitch: CGFloat = eph > 6.1 ? CGFloat(sin((eph - 6.1) / 0.3 * .pi * 2)) * 0.9 : 0
        let ear2 = NSBezierPath()
        ear2.move(to: NSPoint(x: 9.6, y: 12.2 + ey))
        ear2.line(to: NSPoint(x: 11.5, y: 11.3 + ey))
        ear2.line(to: NSPoint(x: 11.4 + twitch, y: 14.3 + ey))
        ear2.close()
        ear2.fill()

        // Tail wrapped around the bottom; the tip lifts in a rare flick
        let fph = t.truncatingRemainder(dividingBy: 9.0)
        let flick: CGFloat = fph > 8.5 ? CGFloat(sin((fph - 8.5) / 0.5 * .pi)) * 8 : 0
        let tail = NSBezierPath()
        tail.appendArc(withCenter: NSPoint(x: 8, y: 7), radius: 6.4,
                       startAngle: 200, endAngle: 335 + flick, clockwise: false)
        tail.lineWidth = 1.8
        tail.lineCapStyle = .round
        tail.stroke()
    }

    /// Side-view walking cat at `offsetX`, drawn facing right and mirrored
    /// when walking left. `legPhase` drives the diagonal-gait leg swing;
    /// the head bobs slightly out of phase with the body.
    private static func drawWalkingCat(offsetX: CGFloat, facingRight: Bool,
                                       legPhase: CGFloat, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let catWidth: CGFloat = 21
        if facingRight {
            ctx.translateBy(x: offsetX, y: 0)
        } else {
            ctx.translateBy(x: offsetX + catWidth, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        color.set()

        let bob = sin(legPhase * 2) * 0.4
        let headBob = sin(legPhase * 2 + 1.2) * 0.3

        // Legs first, so the body overlaps their tops. Diagonal pairs swing
        // in anti-phase like a real walk cycle.
        let anchors: [CGFloat] = [5.5, 8.5, 12.5, 15.5]
        let phases:  [CGFloat] = [0, .pi, .pi, 0]
        for (i, ax) in anchors.enumerated() {
            let swing = sin(legPhase + phases[i]) * 0.45
            let leg = NSBezierPath()
            leg.move(to: NSPoint(x: ax, y: 6 + bob))
            leg.line(to: NSPoint(x: ax + sin(swing) * 4.2, y: 6 + bob - cos(swing) * 4.6))
            leg.lineWidth = 1.7
            leg.lineCapStyle = .round
            leg.stroke()
        }

        // Raised tail, swaying gently with the stride
        let sway = sin(legPhase * 0.9) * 0.6
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4.2, y: 8.6 + bob))
        tail.curve(to: NSPoint(x: 0.9 + sway, y: 13.6 + bob),
                   controlPoint1: NSPoint(x: 2.2, y: 9.4 + bob),
                   controlPoint2: NSPoint(x: 0.6 + sway, y: 11.2 + bob))
        tail.lineWidth = 1.6
        tail.lineCapStyle = .round
        tail.stroke()

        // Body
        NSBezierPath(ovalIn: NSRect(x: 3.4, y: 5.2 + bob, width: 12.6, height: 5.6)).fill()

        // Head
        NSBezierPath(ovalIn: NSRect(x: 14.6, y: 6.6 + bob + headBob, width: 6.4, height: 6.4)).fill()

        // Ears
        let e1 = NSBezierPath()
        e1.move(to: NSPoint(x: 15.2, y: 11.6 + bob + headBob))
        e1.line(to: NSPoint(x: 17.2, y: 12.6 + bob + headBob))
        e1.line(to: NSPoint(x: 15.4, y: 14.6 + bob + headBob))
        e1.close()
        e1.fill()
        let e2 = NSBezierPath()
        e2.move(to: NSPoint(x: 18.2, y: 12.6 + bob + headBob))
        e2.line(to: NSPoint(x: 20.2, y: 11.6 + bob + headBob))
        e2.line(to: NSPoint(x: 20.4, y: 14.4 + bob + headBob))
        e2.close()
        e2.fill()
    }

    /// Side-view sitting cat: round haunch, upright chest, head on top.
    /// The tail sweeps behind it, the front ear twitches now and then, and
    /// a punched-out eye blinks (visible against whatever is behind the icon).
    private static func drawSittingCat(offsetX: CGFloat, facingRight: Bool,
                                       at t: TimeInterval, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let catWidth: CGFloat = 17.2
        if facingRight {
            ctx.translateBy(x: offsetX, y: 0)
        } else {
            ctx.translateBy(x: offsetX + catWidth, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        color.set()

        // Tail sweeps out behind, tip rising and falling
        let swish = CGFloat(sin(t * 2.2))
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4.6, y: 2.6))
        tail.curve(to: NSPoint(x: 0.9, y: 2.0 + max(0, swish) * 2.8),
                   controlPoint1: NSPoint(x: 3.0, y: 1.2),
                   controlPoint2: NSPoint(x: 1.2, y: 1.0))
        tail.lineWidth = 1.7
        tail.lineCapStyle = .round
        tail.stroke()

        // Haunch, chest, head
        NSBezierPath(ovalIn: NSRect(x: 3.4, y: 1.3, width: 8.6, height: 8.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 9.2, y: 1.3, width: 5.6, height: 9.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.6, y: 9.0, width: 6.6, height: 6.6)).fill()

        // Ears; the front one twitches every few seconds
        let eph = t.truncatingRemainder(dividingBy: 5.3)
        let twitch: CGFloat = eph > 5.0 ? CGFloat(sin((eph - 5.0) / 0.3 * .pi * 2)) * 0.9 : 0
        let back = NSBezierPath()
        back.move(to: NSPoint(x: 11.4, y: 14.4))
        back.line(to: NSPoint(x: 13.5, y: 15.2))
        back.line(to: NSPoint(x: 11.9, y: 17.4))
        back.close()
        back.fill()
        let front = NSBezierPath()
        front.move(to: NSPoint(x: 14.7, y: 15.2))
        front.line(to: NSPoint(x: 16.9, y: 14.4))
        front.line(to: NSPoint(x: 17.0 + twitch, y: 17.2))
        front.close()
        front.fill()

        // Blinking eye, punched out of the head silhouette
        let bph = t.truncatingRemainder(dividingBy: 3.6)
        let eyeOpen: CGFloat = bph > 3.35 ? 0.12 : 1.0
        ctx.setBlendMode(.clear)
        NSBezierPath(ovalIn: NSRect(x: 14.6, y: 12.3 - 0.85 * eyeOpen,
                                    width: 1.4, height: 1.7 * eyeOpen)).fill()
        ctx.setBlendMode(.normal)
    }
}

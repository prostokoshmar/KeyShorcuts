import Cocoa

/// Custom-drawn cat for the menu bar, rendered as NSImage frames.
///
/// Asleep (keep-awake off): the cat cycles through sleeping poses — curled
/// ball, loaf (dozing off with slow head-nods), and side sprawl — breathing,
/// twitching an ear, flicking its tail, and exhaling little "z" glyphs.
/// Awake (keep-awake on): a day-in-the-life loop — it strolls across the
/// icon, sits, grooms with a paw, eats from a bowl, does a big
/// stretch, and bats a ball around before settling down to sit again.
enum CatIcon {
    static let canvasSize = NSSize(width: 34, height: 18)
    static let fps: Double = 12

    // MARK: - Public frames

    /// Sleeping loop: curled → loaf doze → side sprawl (80 s cycle).
    static func sleepFrame(at t: TimeInterval, tint: NSColor?) -> NSImage {
        let ph = t.truncatingRemainder(dividingBy: 80)
        return render(tint: tint) { color in
            switch ph {
            case ..<34:
                drawCurledCat(at: t, color: color)
                drawZs(floatingZs(at: t, origin: NSPoint(x: 14.5, y: 5.5)), color: color)
            case ..<58:
                drawLoafCat(at: t, color: color)
                drawZs(floatingZs(at: t, origin: NSPoint(x: 17.5, y: 9.0)), color: color)
            default:
                drawSprawlCat(at: t, color: color)
                drawZs(floatingZs(at: t, origin: NSPoint(x: 21.0, y: 6.0)), color: color)
            }
        }
    }

    static func sleepStatic(tint: NSColor?) -> NSImage {
        render(tint: tint) { color in
            drawCurledCat(at: 0.8, color: color)
            drawZs([
                Z(x: 15.5, y: 7.0,  size: 5.0, alpha: 0.85),
                Z(x: 20.0, y: 10.0, size: 6.5, alpha: 0.60),
                Z(x: 25.0, y: 13.0, size: 8.0, alpha: 0.40),
            ], color: color)
        }
    }

    /// Awake loop (56 s): walk right → sit → groom → walk left → eat →
    /// stretch → play with a ball → sit, then around again.
    static func walkFrame(at t: TimeInterval, tint: NSColor?) -> NSImage {
        let ph = t.truncatingRemainder(dividingBy: 56)
        return render(tint: tint) { color in
            switch ph {
            case ..<7:      // stroll to the right edge
                let p = CGFloat(ph / 7)
                drawWalkingCat(offsetX: 0.5 + p * 12, facingRight: true,
                               legPhase: CGFloat(t * 7), color: color)
            case ..<13:     // sit: tail swish, ear twitch
                drawSittingCat(offsetX: 16.5, facingRight: true, at: t, color: color)
            case ..<19:     // groom: quick paw strokes over the face
                drawGroomingCat(offsetX: 16.5, facingRight: true, at: t, color: color)
            case ..<26:     // stroll back to the left edge
                let p = CGFloat((ph - 19) / 7)
                drawWalkingCat(offsetX: 12.5 - p * 12, facingRight: false,
                               legPhase: CGFloat(t * 7), color: color)
            case ..<33:     // eat from the bowl at the left edge
                drawEatingCat(offsetX: 0.5, facingRight: false, at: t, color: color)
            case ..<36:     // big stretch, butt up
                drawStretchingCat(offsetX: 0.5, facingRight: true, at: t, color: color)
            case ..<48:     // bat the ball around
                drawPlayingCat(offsetX: 0.5, facingRight: true, at: t, color: color)
            default:        // sit and watch where the ball went
                drawSittingCat(offsetX: 0.3, facingRight: true, at: t, color: color)
            }
        }
    }

    static func walkStatic(tint: NSColor?) -> NSImage {
        render(tint: tint) { color in
            drawWalkingCat(offsetX: 6, facingRight: true, legPhase: 0.8, color: color)
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
    /// rising from `origin` toward the top-right, growing, swaying, fading.
    private static func floatingZs(at t: TimeInterval, origin: NSPoint) -> [Z] {
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
            out.append(Z(x: origin.x + p * 11 + sway,
                         y: origin.y + p * 9,
                         size: 4.5 + p * 3.5,
                         alpha: alpha * 0.9))
        }
        return out
    }

    // MARK: - Rendering

    private static func render(tint: NSColor?, _ draw: @escaping (NSColor) -> Void) -> NSImage {
        let color = tint ?? .black
        let img = NSImage(size: canvasSize, flipped: false) { _ in
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

    /// Flips the context around a pose of the given width when facing left.
    private static func withFacing(_ facingRight: Bool, offsetX: CGFloat,
                                   poseWidth: CGFloat, _ body: () -> Void) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if facingRight {
            ctx.translateBy(x: offsetX, y: 0)
        } else {
            ctx.translateBy(x: offsetX + poseWidth, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        body()
    }

    private static func strokePath(width: CGFloat, _ build: (NSBezierPath) -> Void) {
        let p = NSBezierPath()
        build(p)
        p.lineWidth = width
        p.lineCapStyle = .round
        p.stroke()
    }

    /// Brief ear-twitch wiggle every `every` seconds.
    private static func earTwitch(at t: TimeInterval, every: Double) -> CGFloat {
        let ph = t.truncatingRemainder(dividingBy: every)
        return ph > every - 0.3 ? CGFloat(sin((ph - every + 0.3) / 0.3 * .pi * 2)) * 0.9 : 0
    }

    private static func ear(from a: NSPoint, base b: NSPoint, tip: NSPoint) {
        let p = NSBezierPath()
        p.move(to: a)
        p.line(to: b)
        p.line(to: tip)
        p.close()
        p.fill()
    }

    // MARK: - Sleeping poses

    /// Curled ball: round body that swells with a slow breath, ears poking
    /// up (the outer one twitches), tail wrapped around with a rare tip flick.
    private static func drawCurledCat(at t: TimeInterval, color: NSColor) {
        color.set()
        let rise = CGFloat(sin(t * 2 * .pi / 3.4)) * 0.4

        NSBezierPath(ovalIn: NSRect(x: 2.5 - rise * 0.15, y: 1.5,
                                    width: 11 + rise * 0.3, height: 11 + rise)).fill()

        let ey = rise * 0.6
        ear(from: NSPoint(x: 6.4, y: 11.6 + ey), base: NSPoint(x: 8.6, y: 12.2 + ey),
            tip: NSPoint(x: 6.8, y: 14.7 + ey))
        let twitch = earTwitch(at: t, every: 6.4)
        ear(from: NSPoint(x: 9.6, y: 12.2 + ey), base: NSPoint(x: 11.5, y: 11.3 + ey),
            tip: NSPoint(x: 11.4 + twitch, y: 14.3 + ey))

        // Tail tip waves slowly all through the nap, with a bigger rare flick
        let wave = CGFloat(sin(t * 1.2)) * 4
        let fph = t.truncatingRemainder(dividingBy: 9.0)
        let flick: CGFloat = fph > 8.5 ? CGFloat(sin((fph - 8.5) / 0.5 * .pi)) * 8 : 0
        let tail = NSBezierPath()
        tail.appendArc(withCenter: NSPoint(x: 8, y: 7), radius: 6.4,
                       startAngle: 200, endAngle: 335 + wave + flick, clockwise: false)
        tail.lineWidth = 1.8
        tail.lineCapStyle = .round
        tail.stroke()
    }

    /// Loaf: bread-shaped body with paws tucked, head up front. The head
    /// slowly sinks as the cat dozes off, then pops back up.
    private static func drawLoafCat(at t: TimeInterval, color: NSColor) {
        color.set()
        let breath = CGFloat(sin(t * 2 * .pi / 3.4)) * 0.3

        // Body loaf
        NSBezierPath(ovalIn: NSRect(x: 2.8, y: 1.4, width: 12.6, height: 6.8 + breath)).fill()

        // Doze cycle: sink slowly for 5 s, pop back up in 0.4 s, hold
        let dph = t.truncatingRemainder(dividingBy: 7.0)
        let nod: CGFloat
        switch dph {
        case ..<5.0:  nod = -1.7 * CGFloat(dph / 5.0)
        case ..<5.4:  nod = -1.7 * CGFloat(1 - (dph - 5.0) / 0.4)
        default:      nod = 0
        }

        // Head resting on the front of the loaf
        NSBezierPath(ovalIn: NSRect(x: 9.8, y: 5.6 + nod, width: 6.2, height: 6.2)).fill()
        let twitch = earTwitch(at: t, every: 5.7)
        ear(from: NSPoint(x: 10.3, y: 10.4 + nod), base: NSPoint(x: 12.3, y: 11.2 + nod),
            tip: NSPoint(x: 10.7, y: 13.4 + nod))
        ear(from: NSPoint(x: 13.4, y: 11.2 + nod), base: NSPoint(x: 15.4, y: 10.4 + nod),
            tip: NSPoint(x: 15.6 + twitch, y: 13.2 + nod))

        // Tail curled along the loaf's base, tip waving gently
        let wave = CGFloat(sin(t * 1.1)) * 1.1
        strokePath(width: 1.6) { p in
            p.move(to: NSPoint(x: 3.4, y: 1.9))
            p.curve(to: NSPoint(x: 0.9, y: 3.2 + wave),
                    controlPoint1: NSPoint(x: 1.9, y: 1.4),
                    controlPoint2: NSPoint(x: 0.8, y: 2.0))
        }
    }

    /// Side sprawl: stretched out flat, paws poking forward, tail trailing.
    private static func drawSprawlCat(at t: TimeInterval, color: NSColor) {
        color.set()
        let breath = CGFloat(sin(t * 2 * .pi / 3.8)) * 0.4

        // Long low body
        NSBezierPath(ovalIn: NSRect(x: 2.2, y: 1.3, width: 14.5, height: 5.2 + breath)).fill()

        // Head lying at the front
        NSBezierPath(ovalIn: NSRect(x: 14.4, y: 1.6, width: 5.8, height: 5.4)).fill()
        let twitch = earTwitch(at: t, every: 7.1)
        ear(from: NSPoint(x: 14.9, y: 5.8), base: NSPoint(x: 16.7, y: 6.7),
            tip: NSPoint(x: 15.1, y: 8.9))
        ear(from: NSPoint(x: 17.6, y: 6.7), base: NSPoint(x: 19.4, y: 5.6),
            tip: NSPoint(x: 19.6 + twitch, y: 8.5))

        // Relaxed front paws poking out past the chin
        strokePath(width: 1.6) { p in
            p.move(to: NSPoint(x: 18.6, y: 2.9))
            p.line(to: NSPoint(x: 21.8, y: 2.6))
        }
        strokePath(width: 1.6) { p in
            p.move(to: NSPoint(x: 18.2, y: 1.6))
            p.line(to: NSPoint(x: 21.2, y: 1.4))
        }

        // Tail trailing out behind, waving slowly
        let drift = CGFloat(sin(t * 0.9)) * 1.3
        strokePath(width: 1.6) { p in
            p.move(to: NSPoint(x: 2.8, y: 2.4))
            p.curve(to: NSPoint(x: 0.6, y: 3.4 + drift),
                    controlPoint1: NSPoint(x: 1.6, y: 1.6),
                    controlPoint2: NSPoint(x: 0.6, y: 2.2))
        }
    }

    // MARK: - Awake poses

    /// Side-view walking cat, diagonal-gait legs, bobbing body and head.
    private static func drawWalkingCat(offsetX: CGFloat, facingRight: Bool,
                                       legPhase: CGFloat, color: NSColor) {
        withFacing(facingRight, offsetX: offsetX, poseWidth: 21) {
            color.set()
            // One shared bob so body, head, tail, and hips move as a unit
            let bob = sin(legPhase * 2) * 0.4

            // Legs first, so the body overlaps their tops. Diagonal pairs
            // swing in anti-phase like a real walk cycle.
            let anchors: [CGFloat] = [5.5, 8.5, 12.5, 15.5]
            let phases:  [CGFloat] = [0, .pi, .pi, 0]
            for (i, ax) in anchors.enumerated() {
                let swing = sin(legPhase + phases[i]) * 0.45
                strokePath(width: 1.7) { p in
                    p.move(to: NSPoint(x: ax, y: 6 + bob))
                    p.line(to: NSPoint(x: ax + sin(swing) * 4.2, y: 6 + bob - cos(swing) * 4.6))
                }
            }

            // Raised tail
            strokePath(width: 1.6) { p in
                p.move(to: NSPoint(x: 4.2, y: 8.6 + bob))
                p.curve(to: NSPoint(x: 0.9, y: 13.6 + bob),
                        controlPoint1: NSPoint(x: 2.2, y: 9.4 + bob),
                        controlPoint2: NSPoint(x: 0.6, y: 11.2 + bob))
            }

            NSBezierPath(ovalIn: NSRect(x: 3.4, y: 5.2 + bob, width: 12.6, height: 5.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 14.6, y: 6.6 + bob, width: 6.4, height: 6.4)).fill()
            ear(from: NSPoint(x: 15.2, y: 11.6 + bob),
                base: NSPoint(x: 17.2, y: 12.6 + bob),
                tip: NSPoint(x: 15.4, y: 14.6 + bob))
            ear(from: NSPoint(x: 18.2, y: 12.6 + bob),
                base: NSPoint(x: 20.2, y: 11.6 + bob),
                tip: NSPoint(x: 20.4, y: 14.4 + bob))
        }
    }

    /// Sitting upright: round haunch, chest, head. Tail sweeps behind,
    /// and the front ear twitches.
    private static func drawSittingCat(offsetX: CGFloat, facingRight: Bool,
                                       at t: TimeInterval, color: NSColor) {
        withFacing(facingRight, offsetX: offsetX, poseWidth: 17.2) {
            color.set()

            let swish = CGFloat(sin(t * 2.2))
            strokePath(width: 1.7) { p in
                p.move(to: NSPoint(x: 4.6, y: 2.6))
                p.curve(to: NSPoint(x: 0.9, y: 2.0 + max(0, swish) * 2.8),
                        controlPoint1: NSPoint(x: 3.0, y: 1.2),
                        controlPoint2: NSPoint(x: 1.2, y: 1.0))
            }

            NSBezierPath(ovalIn: NSRect(x: 3.4, y: 1.3, width: 8.6, height: 8.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.2, y: 1.3, width: 5.6, height: 9.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.6, y: 9.0, width: 6.6, height: 6.6)).fill()

            let twitch = earTwitch(at: t, every: 5.3)
            ear(from: NSPoint(x: 11.4, y: 14.4), base: NSPoint(x: 13.5, y: 15.2),
                tip: NSPoint(x: 11.9, y: 17.4))
            ear(from: NSPoint(x: 14.7, y: 15.2), base: NSPoint(x: 16.9, y: 14.4),
                tip: NSPoint(x: 17.0 + twitch, y: 17.2))
        }
    }

    /// Grooming: the sitting pose with the head dipped and a
    /// front paw making quick strokes over the face.
    private static func drawGroomingCat(offsetX: CGFloat, facingRight: Bool,
                                        at t: TimeInterval, color: NSColor) {
        withFacing(facingRight, offsetX: offsetX, poseWidth: 17.2) {
            color.set()

            // Calm tail while concentrating
            strokePath(width: 1.7) { p in
                p.move(to: NSPoint(x: 4.6, y: 2.6))
                p.curve(to: NSPoint(x: 0.9, y: 2.2 + CGFloat(sin(t * 1.1)) * 0.6),
                        controlPoint1: NSPoint(x: 3.0, y: 1.2),
                        controlPoint2: NSPoint(x: 1.2, y: 1.0))
            }

            NSBezierPath(ovalIn: NSRect(x: 3.4, y: 1.3, width: 8.6, height: 8.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.2, y: 1.3, width: 5.6, height: 9.6)).fill()

            // Head dipped toward the working paw
            NSBezierPath(ovalIn: NSRect(x: 10.9, y: 8.0, width: 6.4, height: 6.4)).fill()
            ear(from: NSPoint(x: 11.6, y: 13.2), base: NSPoint(x: 13.6, y: 14.0),
                tip: NSPoint(x: 12.0, y: 16.2))
            ear(from: NSPoint(x: 14.8, y: 14.0), base: NSPoint(x: 16.9, y: 13.2),
                tip: NSPoint(x: 17.0, y: 16.0))

            // Front paw strokes over the face, quick little circles
            let lick = CGFloat(sin(t * 6))
            strokePath(width: 1.7) { p in
                p.move(to: NSPoint(x: 12.4, y: 3.6))
                p.curve(to: NSPoint(x: 14.2 + lick * 0.5, y: 7.9 + lick * 0.9),
                        controlPoint1: NSPoint(x: 14.4, y: 4.6),
                        controlPoint2: NSPoint(x: 14.6, y: 6.2))
            }
        }
    }

    /// Standing with the head down in a bowl, little bobs as it munches.
    private static func drawEatingCat(offsetX: CGFloat, facingRight: Bool,
                                      at t: TimeInterval, color: NSColor) {
        withFacing(facingRight, offsetX: offsetX, poseWidth: 23) {
            color.set()

            // Four planted legs
            for ax in [5.5, 8.5, 12.5, 15.0] as [CGFloat] {
                strokePath(width: 1.7) { p in
                    p.move(to: NSPoint(x: ax, y: 6))
                    p.line(to: NSPoint(x: ax, y: 1.5))
                }
            }

            // Relaxed low tail
            let sway = CGFloat(sin(t * 1.3)) * 0.5
            strokePath(width: 1.6) { p in
                p.move(to: NSPoint(x: 4.2, y: 8.4))
                p.curve(to: NSPoint(x: 1.0, y: 10.6 + sway),
                        controlPoint1: NSPoint(x: 2.4, y: 8.8),
                        controlPoint2: NSPoint(x: 1.0, y: 9.4))
            }

            NSBezierPath(ovalIn: NSRect(x: 3.4, y: 5.2, width: 12.6, height: 5.6)).fill()

            // Head down at the bowl, bobbing as it eats; a thick neck keeps
            // it joined to the shoulders as it moves
            let munch = abs(CGFloat(sin(t * 2.8)))
            strokePath(width: 4.6) { p in
                p.move(to: NSPoint(x: 14.4, y: 8.2))
                p.line(to: NSPoint(x: 17.8, y: 5.6 + munch))
            }
            NSBezierPath(ovalIn: NSRect(x: 15.6, y: 2.4 + munch, width: 5.8, height: 5.8)).fill()
            ear(from: NSPoint(x: 16.0, y: 6.8 + munch), base: NSPoint(x: 17.9, y: 7.8 + munch),
                tip: NSPoint(x: 16.3, y: 9.9 + munch))
            ear(from: NSPoint(x: 18.9, y: 7.8 + munch), base: NSPoint(x: 20.8, y: 6.6 + munch),
                tip: NSPoint(x: 21.0, y: 9.5 + munch))

            // The bowl
            NSBezierPath(ovalIn: NSRect(x: 17.3, y: 0.7, width: 5.4, height: 2.6)).fill()
        }
    }

    /// Big downward stretch: forelegs out, chest low, butt high, tail up.
    private static func drawStretchingCat(offsetX: CGFloat, facingRight: Bool,
                                          at t: TimeInterval, color: NSColor) {
        withFacing(facingRight, offsetX: offsetX, poseWidth: 22) {
            color.set()

            // Back legs under the raised haunch
            for ax in [5.5, 7.5] as [CGFloat] {
                strokePath(width: 1.7) { p in
                    p.move(to: NSPoint(x: ax, y: 5))
                    p.line(to: NSPoint(x: ax, y: 1.5))
                }
            }

            // Forelegs stretched out along the ground
            strokePath(width: 1.7) { p in
                p.move(to: NSPoint(x: 13.2, y: 4.2))
                p.line(to: NSPoint(x: 17.6, y: 1.5))
            }
            strokePath(width: 1.7) { p in
                p.move(to: NSPoint(x: 14.0, y: 3.4))
                p.line(to: NSPoint(x: 18.6, y: 1.5))
            }

            // One sloping body: high haunch bridged into the low chest so
            // the silhouette stays a single connected mass
            NSBezierPath(ovalIn: NSRect(x: 3.2, y: 3.4, width: 8.4, height: 7.0)).fill()
            NSBezierPath(ovalIn: NSRect(x: 6.5, y: 2.2, width: 8.5, height: 5.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11.0, y: 1.7, width: 6.4, height: 4.6)).fill()

            // Head up at the front, resting on the chest
            NSBezierPath(ovalIn: NSRect(x: 14.6, y: 3.6, width: 5.8, height: 5.8)).fill()
            ear(from: NSPoint(x: 15.0, y: 8.2), base: NSPoint(x: 16.9, y: 9.1),
                tip: NSPoint(x: 15.3, y: 11.2))
            ear(from: NSPoint(x: 17.9, y: 9.1), base: NSPoint(x: 19.8, y: 8.0),
                tip: NSPoint(x: 20.0, y: 10.9))

            // Tail curling high off the raised butt
            strokePath(width: 1.6) { p in
                p.move(to: NSPoint(x: 4.4, y: 9.6))
                p.curve(to: NSPoint(x: 1.4, y: 14.0),
                        controlPoint1: NSPoint(x: 2.6, y: 10.6),
                        controlPoint2: NSPoint(x: 1.0, y: 12.2))
            }
        }
    }

    /// Play crouch: body low, tail flicking, a front paw batting a ball
    /// that gets knocked away, bounces, and rolls back.
    private static func drawPlayingCat(offsetX: CGFloat, facingRight: Bool,
                                       at t: TimeInterval, color: NSColor) {
        withFacing(facingRight, offsetX: offsetX, poseWidth: 32) {
            color.set()

            // Excited tail, whipping up and down
            let flick = CGFloat(sin(t * 4)) * 1.5
            strokePath(width: 1.6) { p in
                p.move(to: NSPoint(x: 3.8, y: 6.2))
                p.curve(to: NSPoint(x: 0.9, y: 10.6 + flick),
                        controlPoint1: NSPoint(x: 2.2, y: 7.2),
                        controlPoint2: NSPoint(x: 0.7, y: 8.6))
            }

            // Crouched body: haunch up a touch, chest low
            NSBezierPath(ovalIn: NSRect(x: 3.0, y: 2.8, width: 7.4, height: 5.6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 4.4, y: 2.0, width: 11.2, height: 4.6)).fill()

            // Head low and forward, locked on the ball
            NSBezierPath(ovalIn: NSRect(x: 13.8, y: 2.8, width: 5.8, height: 5.8)).fill()
            ear(from: NSPoint(x: 14.2, y: 7.4), base: NSPoint(x: 16.1, y: 8.4),
                tip: NSPoint(x: 14.5, y: 10.5))
            ear(from: NSPoint(x: 17.1, y: 8.4), base: NSPoint(x: 19.0, y: 7.2),
                tip: NSPoint(x: 19.2, y: 10.1))

            // Batting paw, jabbing at the ball
            let bat = CGFloat(sin(t * 5.5))
            strokePath(width: 1.7) { p in
                p.move(to: NSPoint(x: 15.2, y: 3.8))
                p.line(to: NSPoint(x: 17.6 + bat * 1.6, y: 1.6))
            }

            // The ball: knocked away, small bounces, rolls back (3 s cycle)
            let bph = CGFloat(t.truncatingRemainder(dividingBy: 3.0) / 3.0)
            let ballX = 20.5 + sin(bph * .pi) * 8.5
            let ballY = 2.2 + abs(sin(bph * .pi * 3)) * 1.6 * (1 - bph)
            NSBezierPath(ovalIn: NSRect(x: ballX - 1.5, y: ballY - 1.5,
                                        width: 3.0, height: 3.0)).fill()
        }
    }
}

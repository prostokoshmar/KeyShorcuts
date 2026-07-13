import Cocoa

/// Custom-drawn cat for the menu bar, rendered as NSImage frames.
///
/// Asleep (keep-awake off): a curled-up cat with little "z" glyphs that spawn
/// at its head, drift up-right, grow, and fade in a continuous loop.
/// Awake (keep-awake on): the cat strolls back and forth across the icon,
/// legs scissoring in a diagonal gait, tail raised, with a subtle body bob.
enum CatIcon {
    static let canvasSize = NSSize(width: 34, height: 18)
    static let fps: Double = 12

    // MARK: - Public frames

    static func sleepFrame(at t: TimeInterval, tint: NSColor?) -> NSImage {
        render(tint: tint) { color in
            drawCurledCat(color: color)
            drawZs(floatingZs(at: t), color: color)
        }
    }

    static func sleepStatic(tint: NSColor?) -> NSImage {
        render(tint: tint) { color in
            drawCurledCat(color: color)
            drawZs([
                Z(x: 15.5, y: 7.0,  size: 5.0, alpha: 0.85),
                Z(x: 20.0, y: 10.0, size: 6.5, alpha: 0.60),
                Z(x: 25.0, y: 13.0, size: 8.0, alpha: 0.40),
            ], color: color)
        }
    }

    static func walkFrame(at t: TimeInterval, tint: NSColor?) -> NSImage {
        // Stroll back and forth across the canvas, flipping at the edges.
        let travel: CGFloat = 12
        let period: Double = 7.0
        let ph = (t / period).truncatingRemainder(dividingBy: 1)
        let tri = ph < 0.5 ? CGFloat(ph * 2) : CGFloat(2 - ph * 2)   // 0 → 1 → 0
        let x = 0.5 + tri * travel
        return render(tint: tint) { color in
            drawWalkingCat(offsetX: x, facingRight: ph < 0.5,
                           legPhase: CGFloat(t * 7), color: color)
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

    /// Curled sleeping cat: round body, two ears poking up, tail wrapped
    /// around the lower edge.
    private static func drawCurledCat(color: NSColor) {
        color.set()

        // Body
        NSBezierPath(ovalIn: NSRect(x: 2.5, y: 1.5, width: 11, height: 11)).fill()

        // Ears
        let ear1 = NSBezierPath()
        ear1.move(to: NSPoint(x: 6.4, y: 11.6))
        ear1.line(to: NSPoint(x: 8.6, y: 12.2))
        ear1.line(to: NSPoint(x: 6.8, y: 14.7))
        ear1.close()
        ear1.fill()
        let ear2 = NSBezierPath()
        ear2.move(to: NSPoint(x: 9.6, y: 12.2))
        ear2.line(to: NSPoint(x: 11.5, y: 11.3))
        ear2.line(to: NSPoint(x: 11.4, y: 14.3))
        ear2.close()
        ear2.fill()

        // Tail wrapped around the bottom
        let tail = NSBezierPath()
        tail.appendArc(withCenter: NSPoint(x: 8, y: 7), radius: 6.4,
                       startAngle: 200, endAngle: 335, clockwise: false)
        tail.lineWidth = 1.8
        tail.lineCapStyle = .round
        tail.stroke()
    }

    /// Side-view walking cat at `offsetX`, drawn facing right and mirrored
    /// when walking left. `legPhase` drives the diagonal-gait leg swing.
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

        // Raised tail
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4.2, y: 8.6 + bob))
        tail.curve(to: NSPoint(x: 0.9, y: 13.6 + bob),
                   controlPoint1: NSPoint(x: 2.2, y: 9.4 + bob),
                   controlPoint2: NSPoint(x: 0.6, y: 11.2 + bob))
        tail.lineWidth = 1.6
        tail.lineCapStyle = .round
        tail.stroke()

        // Body
        NSBezierPath(ovalIn: NSRect(x: 3.4, y: 5.2 + bob, width: 12.6, height: 5.6)).fill()

        // Head
        NSBezierPath(ovalIn: NSRect(x: 14.6, y: 6.6 + bob, width: 6.4, height: 6.4)).fill()

        // Ears
        let e1 = NSBezierPath()
        e1.move(to: NSPoint(x: 15.2, y: 11.6 + bob))
        e1.line(to: NSPoint(x: 17.2, y: 12.6 + bob))
        e1.line(to: NSPoint(x: 15.4, y: 14.6 + bob))
        e1.close()
        e1.fill()
        let e2 = NSBezierPath()
        e2.move(to: NSPoint(x: 18.2, y: 12.6 + bob))
        e2.line(to: NSPoint(x: 20.2, y: 11.6 + bob))
        e2.line(to: NSPoint(x: 20.4, y: 14.4 + bob))
        e2.close()
        e2.fill()
    }
}

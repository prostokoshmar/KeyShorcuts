import SwiftUI

/// Ambient window cat. Most of the time it's off doing cat things, but once
/// a cycle it strolls in along the bottom edge of the window, sits for a
/// while (tail swish, ear twitch, blinks), then wanders off the other side.
/// Alternates its entry side each cycle. Purely decorative — never
/// intercepts clicks — and disabled via the "window cat" preference.
struct CatStrollerOverlay: View {
    @ObservedObject private var settings = AppSettings.shared

    /// Keeps the cat clear of rounded window corners.
    var bottomInset: CGFloat = 8

    private static let period: Double = 44
    private static let scale: CGFloat = 1.5

    var body: some View {
        if settings.windowCatEnabled {
            GeometryReader { geo in
                TimelineView(.periodic(from: .now, by: 1.0 / CatIcon.fps)) { tl in
                    let now = tl.date.timeIntervalSinceReferenceDate
                    let cycle = (now / Self.period).rounded(.down)
                    let ph = now - cycle * Self.period
                    cat(phase: ph, now: now,
                        fromLeft: Int(cycle) % 2 == 0, size: geo.size)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // Cycle: hidden 0–24 s, walk in 24–31, sit 31–38, walk out 38–44.
    @ViewBuilder
    private func cat(phase: Double, now: TimeInterval,
                     fromLeft: Bool, size: CGSize) -> some View {
        if phase >= 24 {
            let tint = settings.accentTheme.nsAccent ?? .secondaryLabelColor
            let catW = CatIcon.strollerWidth * Self.scale
            let restX = size.width * 0.62
            let walking = phase < 31 || phase >= 38

            // Distance along the walk, measured from the entry side
            let x: CGFloat = {
                switch phase {
                case ..<31: return -catW + (restX + catW) * CGFloat((phase - 24) / 7)
                case ..<38: return restX
                default:    return restX + (size.width + catW - restX) * CGFloat((phase - 38) / 6)
                }
            }()

            let image = walking
                ? CatIcon.strollFrame(at: now, facingRight: fromLeft, tint: tint, scale: Self.scale)
                : CatIcon.sitFrame(at: now, facingRight: fromLeft, tint: tint, scale: Self.scale)

            Image(nsImage: image)
                .position(x: fromLeft ? x : size.width - x,
                          y: size.height - image.size.height / 2 - bottomInset)
        }
    }
}

/// The curled-up sleeping cat (breathing, ear twitch, drifting z's) as a
/// SwiftUI view, for empty states and other cozy corners.
struct SleepingCatView: View {
    @ObservedObject private var settings = AppSettings.shared
    var scale: CGFloat = 2.4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / CatIcon.fps)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Image(nsImage: CatIcon.sleepFrame(
                at: t,
                tint: settings.accentTheme.nsAccent ?? .secondaryLabelColor,
                scale: scale))
        }
    }
}

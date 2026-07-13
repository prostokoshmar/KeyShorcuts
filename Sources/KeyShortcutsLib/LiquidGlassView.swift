import SwiftUI
import AppKit

// Wraps NSVisualEffectView for use in SwiftUI layouts
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}

extension AppSettings {
    /// Active theme accent — nil when the neutral (None) theme is selected.
    var themeAccent: Color? {
        accentTheme.accentRGB.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }

    /// Lightened accent for labels/badge text on dark overlays.
    var themeAccentSoft: Color? {
        accentTheme.accentRGB.map {
            Color(red:   min(1, $0.r * 0.55 + 0.45),
                  green: min(1, $0.g * 0.55 + 0.45),
                  blue:  min(1, $0.b * 0.55 + 0.45))
        }
    }

    /// Deep dark variant for classic (non-glass) overlay backgrounds.
    var themeDark: Color? {
        accentTheme.darkRGB.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }

    // Bottom-fade color for scroll gradients
    var overlayFadeColor: Color {
        if let dark = themeDark {
            return liquidGlassEnabled ? dark.opacity(0.55) : dark.opacity(0.92)
        }
        return liquidGlassEnabled
            ? .black.opacity(0.35)
            : Color(NSColor.windowBackgroundColor).opacity(0.92)
    }
}

// Full-area rounded-rect background — liquid glass or classic depending on settings.
// Drop it as the first layer inside a ZStack that defines the panel.
struct LiquidGlassBackground: View {
    var cornerRadius: CGFloat = 18
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if settings.liquidGlassEnabled {
            glassLayer(intensity: settings.liquidGlassIntensity)
        } else {
            classicLayer
        }
    }

    private func glassLayer(intensity: LiquidGlassIntensity) -> some View {
        let accent = settings.themeAccent
        return ZStack {
            VisualEffectView(material: intensity.material)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // Tint gradient — warm whites simulate refracted light
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(intensity.tint + 0.04), location: 0),
                        .init(color: Color.white.opacity(intensity.tint * 0.5),  location: 0.45),
                        .init(color: Color.white.opacity(intensity.tint * 0.2),  location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))

            // Theme accent wash blended over the frost
            if let accent {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: accent.opacity(0.28), location: 0),
                            .init(color: accent.opacity(0.14), location: 0.5),
                            .init(color: accent.opacity(0.22), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .blendMode(.overlay)
            }

            // Specular crescent — bright top highlight, blended as screen
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(RadialGradient(
                    stops: [
                        .init(color: (accent ?? Color.white).opacity(intensity.spec),
                              location: 0),
                        .init(color: (accent ?? Color.white).opacity(intensity.spec * 0.4),
                              location: 0.22),
                        .init(color: .clear, location: 0.55),
                    ],
                    center: UnitPoint(x: 0.5, y: -0.05),
                    startRadius: 0,
                    endRadius: 700
                ))
                .blendMode(.screen)

            // Bevel edge: accent-tinted when themed, white otherwise
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: (accent ?? Color.white).opacity(intensity.edge + 0.15),
                                  location: 0),
                            .init(color: (accent ?? Color.white).opacity(intensity.edge * 0.35),
                                  location: 0.5),
                            .init(color: Color.black.opacity(intensity.edge * 0.5), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )

            // Chromatic fringe (balanced+max only)
            if intensity.chroma > 0 {
                let leftCol  = settings.themeAccentSoft ?? Color(red: 0.47, green: 0.71, blue: 1)
                let rightCol = accent ?? Color(red: 1, green: 0.55, blue: 0.71)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(leftCol.opacity(0.18 * intensity.chroma), lineWidth: 1)
                    .offset(x: -1)
                    .blendMode(.screen)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(rightCol.opacity(0.18 * intensity.chroma), lineWidth: 1)
                    .offset(x: 1)
                    .blendMode(.screen)
            }
        }
        .shadow(
            color: (accent ?? Color.black).opacity(intensity.drop * (accent != nil ? 0.5 : 1)),
            radius: 40, x: 0, y: 16
        )
        .animation(.easeInOut(duration: 0.25), value: settings.accentTheme)
    }

    private var classicLayer: some View {
        let fill: Color = settings.themeDark.map { $0.opacity(0.92) }
            ?? Color(NSColor.windowBackgroundColor).opacity(0.92)
        let border: Color = settings.themeAccent.map { $0.opacity(0.28) }
            ?? Color.white.opacity(0.12)
        let shadow: Color = settings.themeAccent.map { $0.opacity(0.25) }
            ?? Color.black.opacity(0.55)

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .shadow(color: shadow, radius: 40, x: 0, y: 16)
    }
}

// Circular glass disc — for app-switcher icon cells and similar round elements.
struct LiquidGlassCircle: View {
    var size: CGFloat
    var isHovered: Bool = false
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if settings.liquidGlassEnabled {
            glassCircle(intensity: settings.liquidGlassIntensity)
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(settings.themeAccent != nil
                    ? (isHovered ? settings.themeAccent!.opacity(0.45) : (settings.themeDark ?? .black).opacity(0.60))
                    : (isHovered ? Color.white.opacity(0.18) : Color.black.opacity(0.42)))
                .frame(width: size, height: size)
        }
    }

    private func glassCircle(intensity: LiquidGlassIntensity) -> some View {
        let accent = settings.themeAccent
        return ZStack {
            VisualEffectView(material: intensity.material)

            Circle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(intensity.tint + 0.04), location: 0),
                        .init(color: Color.white.opacity(intensity.tint * 0.5),  location: 0.5),
                        .init(color: Color.white.opacity(intensity.tint * 0.2),  location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))

            // Theme accent wash
            if let accent {
                Circle()
                    .fill(accent.opacity(isHovered ? 0.30 : 0.18))
                    .blendMode(.overlay)
            }

            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: (accent ?? Color.white).opacity(intensity.spec),       location: 0),
                        .init(color: (accent ?? Color.white).opacity(intensity.spec * 0.4), location: 0.22),
                        .init(color: .clear, location: 0.55),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.1),
                    startRadius: 0,
                    endRadius: size * 0.7
                ))
                .blendMode(.screen)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: (accent ?? Color.white)
                                    .opacity(isHovered ? intensity.edge + 0.35 : intensity.edge + 0.15),
                                  location: 0),
                            .init(color: (accent ?? Color.white)
                                    .opacity(intensity.edge * 0.35),
                                  location: 0.5),
                            .init(color: Color.black.opacity(intensity.edge * 0.5), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isHovered ? 2 : 1
                )
        }
        .clipShape(Circle())
        .shadow(
            color: (accent ?? Color.black)
                .opacity(isHovered ? intensity.drop * 0.7 : intensity.drop * 0.4),
            radius: isHovered ? 14 : 8,
            x: 0, y: isHovered ? 4 : 2
        )
    }
}

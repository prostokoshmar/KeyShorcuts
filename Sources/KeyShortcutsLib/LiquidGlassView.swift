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

// Deep pink used by cute mode
private let cuteAccent = Color(red: 1.0, green: 0.08, blue: 0.45)
private let cuteDark   = Color(red: 0.38, green: 0.03, blue: 0.18)

extension AppSettings {
    // Shared accent color for cute-mode tinting (use this across all views)
    var accentPink: Color { cuteAccent }

    // Bottom-fade color for scroll gradients
    var overlayFadeColor: Color {
        if cuteMode {
            return liquidGlassEnabled
                ? cuteDark.opacity(0.55)
                : cuteDark.opacity(0.92)
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
        ZStack {
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

            // Cute-mode: deep pink wash blended over the frost
            if settings.cuteMode {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        stops: [
                            .init(color: cuteAccent.opacity(0.28), location: 0),
                            .init(color: cuteAccent.opacity(0.14), location: 0.5),
                            .init(color: cuteAccent.opacity(0.22), location: 1),
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
                        .init(color: (settings.cuteMode ? cuteAccent : Color.white).opacity(intensity.spec),
                              location: 0),
                        .init(color: (settings.cuteMode ? cuteAccent : Color.white).opacity(intensity.spec * 0.4),
                              location: 0.22),
                        .init(color: .clear, location: 0.55),
                    ],
                    center: UnitPoint(x: 0.5, y: -0.05),
                    startRadius: 0,
                    endRadius: 700
                ))
                .blendMode(.screen)

            // Bevel edge: pink-tinted in cute mode, white otherwise
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: (settings.cuteMode ? cuteAccent : Color.white).opacity(intensity.edge + 0.15),
                                  location: 0),
                            .init(color: (settings.cuteMode ? cuteAccent : Color.white).opacity(intensity.edge * 0.35),
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
                let leftCol  = settings.cuteMode ? Color(red: 1, green: 0.4, blue: 0.7) : Color(red: 0.47, green: 0.71, blue: 1)
                let rightCol = settings.cuteMode ? Color(red: 0.85, green: 0, blue: 0.4) : Color(red: 1, green: 0.55, blue: 0.71)
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
            color: (settings.cuteMode ? cuteAccent : Color.black).opacity(intensity.drop * (settings.cuteMode ? 0.5 : 1)),
            radius: 40, x: 0, y: 16
        )
    }

    private var classicLayer: some View {
        let fill: Color = settings.cuteMode
            ? cuteDark.opacity(0.92)
            : Color(NSColor.windowBackgroundColor).opacity(0.92)
        let border: Color = settings.cuteMode
            ? cuteAccent.opacity(0.28)
            : Color.white.opacity(0.12)
        let shadow: Color = settings.cuteMode
            ? cuteAccent.opacity(0.25)
            : Color.black.opacity(0.55)

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
                .fill(settings.cuteMode
                    ? (isHovered ? cuteAccent.opacity(0.45) : cuteDark.opacity(0.60))
                    : (isHovered ? Color.white.opacity(0.18) : Color.black.opacity(0.42)))
                .frame(width: size, height: size)
        }
    }

    private func glassCircle(intensity: LiquidGlassIntensity) -> some View {
        ZStack {
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

            // Cute wash
            if settings.cuteMode {
                Circle()
                    .fill(cuteAccent.opacity(isHovered ? 0.30 : 0.18))
                    .blendMode(.overlay)
            }

            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: (settings.cuteMode ? cuteAccent : Color.white).opacity(intensity.spec),       location: 0),
                        .init(color: (settings.cuteMode ? cuteAccent : Color.white).opacity(intensity.spec * 0.4), location: 0.22),
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
                            .init(color: (settings.cuteMode ? cuteAccent : Color.white)
                                    .opacity(isHovered ? intensity.edge + 0.35 : intensity.edge + 0.15),
                                  location: 0),
                            .init(color: (settings.cuteMode ? cuteAccent : Color.white)
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
            color: (settings.cuteMode ? cuteAccent : Color.black)
                .opacity(isHovered ? intensity.drop * 0.7 : intensity.drop * 0.4),
            radius: isHovered ? 14 : 8,
            x: 0, y: isHovered ? 4 : 2
        )
    }
}

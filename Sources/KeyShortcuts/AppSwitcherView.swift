import SwiftUI

struct AppWindowInfo: Identifiable {
    let id: Int
    let title: String
    let axElement: AXUIElement
}

struct RunningAppEntry: Identifiable {
    let id: pid_t
    let app: NSRunningApplication
    let windows: [AppWindowInfo]
}

// MARK: - Top-level dispatcher

struct AppSwitcherView: View {
    let apps: [RunningAppEntry]
    let onAppChosen: (RunningAppEntry) -> Void
    let onWindowChosen: (RunningAppEntry, AppWindowInfo) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    static func containerSize(for count: Int, layout: AppSwitcherLayout = .radialRing) -> CGFloat {
        switch layout {
        case .segmentedTorus, .concentric: return 840
        case .radialRing: return (dynamicRadius(for: count) + 220) * 2
        }
    }

    static func dynamicRadius(for count: Int) -> CGFloat {
        max(100, CGFloat(count) * 80 / (2 * .pi))
    }

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).onTapGesture { onDismiss() }

            switch settings.appSwitcherLayout {
            case .radialRing:
                RadialRingLayout(apps: apps, onAppChosen: onAppChosen,
                                 onWindowChosen: onWindowChosen, onDismiss: onDismiss)
            case .segmentedTorus:
                SegmentedTorusLayout(apps: apps, onAppChosen: onAppChosen,
                                     onWindowChosen: onWindowChosen, onDismiss: onDismiss)
            case .concentric:
                ConcentricLayout(apps: apps, onAppChosen: onAppChosen,
                                 onWindowChosen: onWindowChosen, onDismiss: onDismiss)
            }
        }
        .frame(
            width:  Self.containerSize(for: apps.count, layout: settings.appSwitcherLayout),
            height: Self.containerSize(for: apps.count, layout: settings.appSwitcherLayout)
        )
    }
}

// MARK: - Radial Ring (original layout)

private struct RadialRingLayout: View {
    let apps: [RunningAppEntry]
    let onAppChosen: (RunningAppEntry) -> Void
    let onWindowChosen: (RunningAppEntry, AppWindowInfo) -> Void
    let onDismiss: () -> Void

    @State private var hoveredAppID: pid_t? = nil
    @State private var hoverGeneration: Int = 0

    static let iconSize: CGFloat = 52

    private var radius: CGFloat { AppSwitcherView.dynamicRadius(for: apps.count) }

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color.black.opacity(0.55), Color.clear],
                center: .center, startRadius: 0, endRadius: radius + 24
            )
            .frame(width: (radius + 24) * 2, height: (radius + 24) * 2)
            .allowsHitTesting(false)

            ForEach(Array(apps.enumerated()), id: \.element.id) { index, entry in
                let angle = itemAngle(index: index, total: apps.count)
                let dx = cos(angle) * Double(radius)
                let dy = -sin(angle) * Double(radius)

                AppIconCell(
                    entry: entry, iconSize: Self.iconSize,
                    isHovered: hoveredAppID == entry.id,
                    onHover: { over in if over { enter(entry.id) } else { scheduleLeave() } },
                    onTap: { onAppChosen(entry) }
                )
                .offset(x: dx, y: dy)

                if hoveredAppID == entry.id && entry.windows.count > 1 {
                    let cardDist = Double(radius) + Double(Self.iconSize) * 0.6 + 70
                    WindowListCard(
                        windows: entry.windows,
                        onWindowChosen: { win in onWindowChosen(entry, win) }
                    )
                    .onHover { over in if over { enter(entry.id) } else { scheduleLeave() } }
                    .offset(x: cos(angle) * cardDist, y: -sin(angle) * cardDist)
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
    }

    private func enter(_ id: pid_t) {
        hoverGeneration += 1
        withAnimation(.easeOut(duration: 0.12)) { hoveredAppID = id }
    }

    private func scheduleLeave() {
        let gen = hoverGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard hoverGeneration == gen else { return }
            withAnimation(.easeOut(duration: 0.12)) { hoveredAppID = nil }
        }
    }

    private func itemAngle(index: Int, total: Int) -> Double {
        guard total > 1 else { return -.pi / 2 }
        return Double(index) / Double(total) * 2 * .pi - .pi / 2
    }
}

// MARK: - Segmented Torus

private struct SegmentedTorusLayout: View {
    let apps: [RunningAppEntry]
    let onAppChosen: (RunningAppEntry) -> Void
    let onWindowChosen: (RunningAppEntry, AppWindowInfo) -> Void
    let onDismiss: () -> Void

    @State private var hoveredAppID: pid_t? = nil
    @State private var hoverGen: Int = 0
    @ObservedObject private var settings = AppSettings.shared

    private let outerR: CGFloat = 200
    private let innerR: CGFloat = 96
    private let canvasSize: CGFloat = 840

    var body: some View {
        ZStack {
            ForEach(Array(apps.enumerated()), id: \.element.id) { i, entry in
                TorusWedge(
                    index: i, total: apps.count,
                    outerR: outerR, innerR: innerR, canvasSize: canvasSize,
                    entry: entry,
                    isHovered: hoveredAppID == entry.id,
                    onTap: { onAppChosen(entry) }
                )
            }

            Circle().stroke(Color.white.opacity(0.18), lineWidth: 1).frame(width: outerR * 2, height: outerR * 2)
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 1).frame(width: innerR * 2, height: innerR * 2)
            Circle().fill(Color.white.opacity(0.55)).frame(width: 8, height: 8)
                .shadow(color: .white.opacity(0.3), radius: 8)

            ForEach(apps) { entry in
                if hoveredAppID == entry.id && entry.windows.count > 1 {
                    let i = apps.firstIndex(where: { $0.id == entry.id }) ?? 0
                    let angle = -Double.pi / 2 + Double(i) / Double(apps.count) * 2 * .pi
                    let cardR = Double(outerR) + 90
                    WindowListCard(
                        windows: entry.windows,
                        onWindowChosen: { win in onWindowChosen(entry, win) }
                    )
                    .onHover { over in
                        if over { hoverGen += 1 } else { scheduleHoverClear() }
                    }
                    .offset(x: cos(angle) * cardR, y: sin(angle) * cardR)
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .onContinuousHover { phase in
            handleHover(phase)
        }
    }

    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let pt):
            let cx = canvasSize / 2
            let cy = canvasSize / 2
            let dx = pt.x - cx
            let dy = pt.y - cy
            let dist = sqrt(dx * dx + dy * dy)

            if dist >= Double(innerR) && dist <= Double(outerR) + 14 {
                let angle = atan2(Double(dy), Double(dx))
                let sliceAngle = 2 * .pi / Double(apps.count)
                var found: pid_t? = nil
                for (i, entry) in apps.enumerated() {
                    let mid = -.pi / 2 + Double(i) * sliceAngle
                    var diff = angle - mid
                    while diff >  .pi { diff -= 2 * .pi }
                    while diff < -.pi { diff += 2 * .pi }
                    if abs(diff) < sliceAngle / 2 { found = entry.id; break }
                }
                if found != hoveredAppID {
                    hoverGen += 1
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                        hoveredAppID = found
                    }
                }
            } else {
                scheduleHoverClear()
            }

        case .ended:
            scheduleHoverClear()
        }
    }

    private func scheduleHoverClear() {
        hoverGen += 1
        let gen = hoverGen
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard hoverGen == gen else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                hoveredAppID = nil
            }
        }
    }
}

private struct TorusWedge: View {
    let index: Int
    let total: Int
    let outerR: CGFloat
    let innerR: CGFloat
    let canvasSize: CGFloat
    let entry: RunningAppEntry
    let isHovered: Bool
    let onTap: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    private var sliceAngle: Double { 2 * .pi / Double(total) }
    private var midAngle: Double { -.pi / 2 + Double(index) * sliceAngle }
    private var gap: Double { isHovered ? 0.055 : 0.004 }
    private var startRad: Double { midAngle - sliceAngle / 2 + gap / 2 }
    private var endRad: Double   { midAngle + sliceAngle / 2 - gap / 2 }

    private var currentOuterR: CGFloat { isHovered ? outerR + 7 : outerR }
    private var currentInnerR: CGFloat { isHovered ? innerR - 4 : innerR }
    private var radialPush:    CGFloat { isHovered ? 5 : 0 }
    private var tileR:         CGFloat { (outerR + innerR) / 2 }

    var body: some View {
        ZStack {
            // Frosted wedge fill
            DonutSegmentShape(innerR: currentInnerR, outerR: currentOuterR,
                              startRad: startRad, endRad: endRad)
                .fill(wedgeFill)
                .offset(x: cos(midAngle) * radialPush, y: sin(midAngle) * radialPush)

            // Glass tint overlay (liquid glass mode)
            if settings.liquidGlassEnabled {
                DonutSegmentShape(innerR: currentInnerR, outerR: currentOuterR,
                                  startRad: startRad, endRad: endRad)
                    .fill(glassTint)
                    .offset(x: cos(midAngle) * radialPush, y: sin(midAngle) * radialPush)
                    .blendMode(.screen)
            }

            // Hover edge glow
            if isHovered {
                DonutSegmentShape(innerR: currentInnerR, outerR: currentOuterR,
                                  startRad: startRad, endRad: endRad)
                    .stroke(settings.cuteMode
                        ? Color(red: 1, green: 0.45, blue: 0.75).opacity(0.85)
                        : Color.white.opacity(0.75), lineWidth: 1.5)
                    .offset(x: cos(midAngle) * radialPush, y: sin(midAngle) * radialPush)
            }

            // App icon
            let iconX = cos(midAngle) * tileR + (isHovered ? cos(midAngle) * 5 : 0)
            let iconY = sin(midAngle) * tileR + (isHovered ? sin(midAngle) * 5 : 0)

            Group {
                if let icon = entry.app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 38, height: 38)
                }
            }
            .scaleEffect(isHovered ? 1.18 : 1.0)
            .offset(x: iconX, y: iconY)
        }
        .frame(width: canvasSize, height: canvasSize)
        .contentShape(
            DonutSegmentShape(innerR: innerR - 2, outerR: outerR + 2,
                              startRad: midAngle - sliceAngle / 2,
                              endRad:   midAngle + sliceAngle / 2)
        )
        .onTapGesture { onTap() }
    }

    private var wedgeFill: LinearGradient {
        if settings.cuteMode {
            return LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.02, blue: 0.22).opacity(isHovered ? 0.90 : 0.72),
                    Color(red: 0.35, green: 0.01, blue: 0.14).opacity(isHovered ? 0.85 : 0.65),
                ],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.white.opacity(isHovered ? 0.26 : 0.16),
                    Color.white.opacity(isHovered ? 0.10 : 0.06),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var glassTint: LinearGradient {
        let base = settings.cuteMode ? Color(red: 1, green: 0.08, blue: 0.45) : Color.white
        return LinearGradient(
            colors: [base.opacity(0.22), base.opacity(0.06)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Concentric

private struct ConcentricLayout: View {
    let apps: [RunningAppEntry]
    let onAppChosen: (RunningAppEntry) -> Void
    let onWindowChosen: (RunningAppEntry, AppWindowInfo) -> Void
    let onDismiss: () -> Void

    @State private var hoveredAppID: pid_t? = nil
    @State private var hoverGeneration: Int = 0

    private let innerRadius: CGFloat = 82
    private let outerRadius: CGFloat = 182
    private let innerIconSize: CGFloat = 52
    private let outerIconSize: CGFloat = 62

    private var innerApps: [RunningAppEntry] { Array(apps.prefix(4)) }
    private var outerApps: [RunningAppEntry] { Array(apps.dropFirst(4)) }

    var body: some View {
        ZStack {
            // Faint guide ring
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                .frame(width: outerRadius * 2, height: outerRadius * 2)

            // Center cue
            Circle().fill(Color.white.opacity(0.55)).frame(width: 8, height: 8)
                .shadow(color: .white.opacity(0.3), radius: 8)

            // Inner ring (first ≤4 apps, 45° rotated)
            ForEach(Array(innerApps.enumerated()), id: \.element.id) { i, entry in
                let total = innerApps.count
                let angle = Double(i) / Double(total) * 2 * .pi - .pi / 2 + (total == 4 ? .pi/4 : 0)
                let dx = cos(angle) * Double(innerRadius)
                let dy = sin(angle) * Double(innerRadius)
                concentricCell(entry: entry, size: innerIconSize, dx: dx, dy: dy)
            }

            // Outer ring (remaining apps)
            ForEach(Array(outerApps.enumerated()), id: \.element.id) { i, entry in
                let total = max(outerApps.count, 1)
                let angle = Double(i) / Double(total) * 2 * .pi - .pi / 2
                let dx = cos(angle) * Double(outerRadius)
                let dy = sin(angle) * Double(outerRadius)
                concentricCell(entry: entry, size: outerIconSize, dx: dx, dy: dy)
            }

            // Window cards
            ForEach(apps) { entry in
                if hoveredAppID == entry.id && entry.windows.count > 1 {
                    let i = apps.firstIndex(where: { $0.id == entry.id }) ?? 0
                    let isInner = i < 4
                    let ring: [RunningAppEntry] = isInner ? innerApps : outerApps
                    let localI = isInner ? i : i - 4
                    let total = max(ring.count, 1)
                    let angle = Double(localI) / Double(total) * 2 * .pi - .pi / 2 + (isInner && ring.count == 4 ? .pi/4 : 0)
                    let r = isInner ? Double(innerRadius) : Double(outerRadius)
                    WindowListCard(
                        windows: entry.windows,
                        onWindowChosen: { win in onWindowChosen(entry, win) }
                    )
                    .offset(x: cos(angle) * (r + 90), y: sin(angle) * (r + 90))
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .frame(width: 840, height: 840)
    }

    @ViewBuilder
    private func concentricCell(entry: RunningAppEntry, size: CGFloat, dx: Double, dy: Double) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(
                        hoveredAppID == entry.id
                            ? Color(red: 1, green: 0.08, blue: 0.45).opacity(0.85)
                            : Color.white.opacity(0),
                        lineWidth: 2
                    )
                    .frame(width: size + 14, height: size + 14)

                LiquidGlassCircle(size: size + 8, isHovered: hoveredAppID == entry.id)

                if let icon = entry.app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
                }
            }
            .scaleEffect(hoveredAppID == entry.id ? 1.16 : 1.0)
            .animation(.easeOut(duration: 0.12), value: hoveredAppID)

            if hoveredAppID == entry.id {
                Text(entry.app.localizedName ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
            }
        }
        .offset(x: dx, y: dy)
        .onHover { over in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredAppID = over ? entry.id : nil
            }
        }
        .onTapGesture { onAppChosen(entry) }
        .contentShape(Rectangle())
    }
}

// MARK: - Donut Segment Shape

struct DonutSegmentShape: Shape {
    var innerR: CGFloat
    var outerR: CGFloat
    var startRad: Double
    var endRad: Double

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<Double, Double>> {
        get { .init(.init(innerR, outerR), .init(startRad, endRad)) }
        set {
            innerR = newValue.first.first
            outerR = newValue.first.second
            startRad = newValue.second.first
            endRad   = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        var p = Path()
        p.addArc(center: CGPoint(x: cx, y: cy), radius: outerR,
                 startAngle: .init(radians: startRad), endAngle: .init(radians: endRad), clockwise: false)
        p.addArc(center: CGPoint(x: cx, y: cy), radius: innerR,
                 startAngle: .init(radians: endRad), endAngle: .init(radians: startRad), clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Icon Cell (Radial Ring)

private struct AppIconCell: View {
    let entry: RunningAppEntry
    let iconSize: CGFloat
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(
                        (settings.cuteMode
                            ? Color(red: 1, green: 0.08, blue: 0.45)
                            : Color.white).opacity(isHovered ? 0.85 : 0),
                        lineWidth: 2
                    )
                    .frame(width: iconSize + 16, height: iconSize + 16)

                LiquidGlassCircle(size: iconSize + 10, isHovered: isHovered)
                    .shadow(color: .black.opacity(0.5), radius: isHovered ? 10 : 5, x: 0, y: 3)

                if let icon = entry.app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22))
                }
            }
            .scaleEffect(isHovered ? 1.16 : 1.0)

            Text(entry.app.localizedName ?? "")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 6))
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 0.85, anchor: .top)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .contentShape(Rectangle())
    }
}

// MARK: - Window List Card

private struct WindowListCard: View {
    let windows: [AppWindowInfo]
    let onWindowChosen: (AppWindowInfo) -> Void

    @State private var hoveredID: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(windows) { win in
                HStack(spacing: 6) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11))
                        .foregroundStyle(hoveredID == win.id ? .white : .secondary)

                    Text(win.title.isEmpty ? "Untitled" : win.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(hoveredID == win.id ? Color.white : Color.primary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hoveredID == win.id ? Color.accentColor : Color.clear)
                .contentShape(Rectangle())
                .onHover { over in hoveredID = over ? win.id : nil }
                .onTapGesture { onWindowChosen(win) }

                if win.id != windows.last?.id {
                    Divider().padding(.horizontal, 8).opacity(0.35)
                }
            }
        }
        .frame(width: 220)
        .background(LiquidGlassBackground(cornerRadius: 11))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
    }
}

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

struct AppSwitcherView: View {
    let apps: [RunningAppEntry]
    let onAppChosen: (RunningAppEntry) -> Void
    let onWindowChosen: (RunningAppEntry, AppWindowInfo) -> Void
    let onDismiss: () -> Void

    @State private var hoveredAppID: pid_t? = nil
    // Incremented on every hover-enter; lets the scheduled hide bail if another hover arrived.
    @State private var hoverGeneration: Int = 0

    static let iconSize: CGFloat = 52

    static func dynamicRadius(for count: Int) -> CGFloat {
        max(100, CGFloat(count) * 80 / (2 * .pi))
    }

    static func containerSize(for count: Int) -> CGFloat {
        (dynamicRadius(for: count) + 220) * 2
    }

    private var radius: CGFloat { Self.dynamicRadius(for: apps.count) }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            RadialGradient(
                colors: [Color.black.opacity(0.55), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: radius + 24
            )
            .frame(width: (radius + 24) * 2, height: (radius + 24) * 2)
            .allowsHitTesting(false)

            ForEach(Array(apps.enumerated()), id: \.element.id) { index, entry in
                let angle  = itemAngle(index: index, total: apps.count)
                let dx     = cos(angle) * Double(radius)
                let dy     = -sin(angle) * Double(radius)

                AppIconCell(
                    entry: entry,
                    iconSize: Self.iconSize,
                    isHovered: hoveredAppID == entry.id,
                    onHover: { over in
                        if over { enter(entry.id) } else { scheduleLeave() }
                    },
                    onTap: { onAppChosen(entry) }
                )
                .offset(x: dx, y: dy)

                if hoveredAppID == entry.id && entry.windows.count > 1 {
                    let cardDist = Double(radius) + Double(Self.iconSize) * 0.6 + 70
                    WindowListCard(
                        windows: entry.windows,
                        onWindowChosen: { win in onWindowChosen(entry, win) }
                    )
                    // Keep hover alive while mouse is inside the card.
                    .onHover { over in
                        if over { enter(entry.id) } else { scheduleLeave() }
                    }
                    .offset(x: cos(angle) * cardDist, y: -sin(angle) * cardDist)
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .frame(
            width:  Self.containerSize(for: apps.count),
            height: Self.containerSize(for: apps.count)
        )
    }

    // MARK: - Hover debounce

    private func enter(_ id: pid_t) {
        hoverGeneration += 1
        withAnimation(.easeOut(duration: 0.12)) { hoveredAppID = id }
    }

    // 100 ms grace period so the mouse can travel from the icon to the popup card
    // without flickering. If another hover-enter fires within that window, the hide is cancelled.
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

// MARK: - Icon Cell

private struct AppIconCell: View {
    let entry: RunningAppEntry
    let iconSize: CGFloat
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(isHovered ? 0.65 : 0), lineWidth: 2)
                    .frame(width: iconSize + 16, height: iconSize + 16)

                Circle()
                    .fill(isHovered
                          ? Color.white.opacity(0.18)
                          : Color.black.opacity(0.42))
                    .frame(width: iconSize + 10, height: iconSize + 10)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
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

// MARK: - Window List Popup

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
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
    }
}

import SwiftUI

struct AppWindowInfo: Identifiable {
    let id: Int        // index in AX window list, stable within one fetch
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

    static let iconSize: CGFloat = 56
    static let radius: CGFloat = 118
    static let containerSize: CGFloat = (radius + iconSize + 44) * 2

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            ForEach(Array(apps.enumerated()), id: \.element.id) { index, entry in
                let angle  = itemAngle(index: index, total: apps.count)
                let dx     = cos(angle) * Double(Self.radius)
                let dy     = -sin(angle) * Double(Self.radius)

                AppIconCell(
                    entry: entry,
                    iconSize: Self.iconSize,
                    isHovered: hoveredAppID == entry.id,
                    onHover: { over in
                        withAnimation(.easeOut(duration: 0.1)) {
                            hoveredAppID = over ? entry.id : nil
                        }
                    },
                    onTap: { onAppChosen(entry) }
                )
                .offset(x: dx, y: dy)

                if hoveredAppID == entry.id && entry.windows.count > 1 {
                    let cardDist = Double(Self.radius) + Double(Self.iconSize) * 0.6 + 70
                    WindowListCard(
                        windows: entry.windows,
                        onWindowChosen: { win in onWindowChosen(entry, win) }
                    )
                    .offset(x: cos(angle) * cardDist, y: -sin(angle) * cardDist)
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .frame(width: Self.containerSize, height: Self.containerSize)
    }

    private func itemAngle(index: Int, total: Int) -> Double {
        guard total > 1 else { return -.pi / 2 }
        return Double(index) / Double(total) * 2 * .pi - .pi / 2
    }
}

private struct AppIconCell: View {
    let entry: RunningAppEntry
    let iconSize: CGFloat
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color.white.opacity(0.28) : Color.black.opacity(0.38))
                    .frame(width: iconSize + 14, height: iconSize + 14)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)

                if let icon = entry.app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22))
                }
            }
            .scaleEffect(isHovered ? 1.12 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isHovered)

            Text(entry.app.localizedName ?? "")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2, x: 0, y: 1)
                .lineLimit(1)
                .frame(maxWidth: iconSize + 36)
        }
        .onHover(perform: onHover)
        .onTapGesture(perform: onTap)
        .contentShape(Rectangle())
    }
}

private struct WindowListCard: View {
    let windows: [AppWindowInfo]
    let onWindowChosen: (AppWindowInfo) -> Void

    @State private var hoveredID: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(windows) { win in
                Text(win.title.isEmpty ? "Untitled" : win.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(hoveredID == win.id ? Color.accentColor : Color.clear)
                    .foregroundStyle(hoveredID == win.id ? Color.white : Color.primary)
                    .contentShape(Rectangle())
                    .onHover { over in hoveredID = over ? win.id : nil }
                    .onTapGesture { onWindowChosen(win) }

                if win.id != windows.last?.id {
                    Divider().padding(.horizontal, 6).opacity(0.4)
                }
            }
        }
        .frame(width: 210)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 5)
    }
}

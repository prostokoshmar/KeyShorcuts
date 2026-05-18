import SwiftUI

struct ShortcutsOverlayView: View {
    let shortcuts: [String: [ShortcutItem]]
    let appName: String
    let appIcon: NSImage?

    @ObservedObject private var settings = AppSettings.shared

    private var sortedCategories: [String] {
        shortcuts.keys.sorted()
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground(cornerRadius: 18)

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Divider().opacity(0.25)

                if shortcuts.isEmpty {
                    emptyStateView
                } else {
                    scrollContent
                }
            }
        }
        .frame(width: 920, height: 620)
    }

    private var scrollContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(sortedCategories, id: \.self) { cat in
                        if let items = shortcuts[cat] {
                            CategorySectionView(title: cat, items: items)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            }

            // Bottom fade — adapts color to glass vs classic mode
            LinearGradient(
                colors: [.clear, settings.overlayFadeColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 44)
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var headerView: some View {
        let settings = AppSettings.shared
        let symbol = settings.triggerKey.symbol
        let actionLabel = settings.triggerMode == .hold
            ? "Hold \(symbol)"
            : "Double press \(symbol)"

        return HStack(spacing: 10) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
            }
            Text(appName)
                .font(.system(size: 16, weight: .semibold))
            Text("Keyboard Shortcuts")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Text(actionLabel)
                    .foregroundStyle(.tertiary)
                KeyBadge(label: symbol)
                Text("to view · Release to dismiss")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No shortcuts found")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("This app may not expose keyboard shortcuts via accessibility APIs.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CategorySectionView: View {
    let title: String
    let items: [ShortcutItem]
    @ObservedObject private var settings = AppSettings.shared

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settings.cuteMode
                    ? Color(red: 1, green: 0.45, blue: 0.72)
                    : Color.secondary)
                .tracking(0.8)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    ShortcutRowView(item: item)
                }
            }
        }
    }
}

struct ShortcutRowView: View {
    let item: ShortcutItem
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            KeyBadge(label: item.keys)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(settings.cuteMode
            ? Color(red: 1, green: 0.08, blue: 0.45).opacity(0.07)
            : Color.primary.opacity(0.04))
        .cornerRadius(7)
    }
}

struct KeyBadge: View {
    let label: String
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        let fg: Color   = settings.cuteMode ? Color(red: 1, green: 0.55, blue: 0.80) : .primary
        let bg: Color   = settings.cuteMode ? Color(red: 1, green: 0.08, blue: 0.45).opacity(0.14) : .primary.opacity(0.1)
        let bdr: Color  = settings.cuteMode ? Color(red: 1, green: 0.08, blue: 0.45).opacity(0.32) : .primary.opacity(0.15)

        return Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bg)
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(bdr, lineWidth: 0.5)
            )
    }
}

// MARK: - Preview

#if DEBUG
struct PreviewShortcutItem: Identifiable {
    let id = UUID()
    let title: String
    let keys: String
    let category: String
}

extension ShortcutItem {
    static func mock(title: String, keys: String, category: String) -> ShortcutItem {
        ShortcutItem(title: title, keys: keys, category: category)
    }
}
#Preview {
    ShortcutsOverlayView(
        shortcuts: [
            "File": [
                .mock(title: "New Window", keys: "⌘N", category: "File"),
                .mock(title: "Open…", keys: "⌘O", category: "File")
            ],
            "Edit": [
                .mock(title: "Cut", keys: "⌘X", category: "Edit"),
                .mock(title: "Copy", keys: "⌘C", category: "Edit"),
                .mock(title: "Paste", keys: "⌘V", category: "Edit")
            ]
        ],
        appName: "Mock App",
        appIcon: nil
    )
}
#endif

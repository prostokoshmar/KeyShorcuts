import SwiftUI

struct ShortcutsOverlayView: View {
    let shortcuts: [String: [ShortcutItem]]
    let appName: String
    let appIcon: NSImage?

    private var sortedCategories: [String] {
        shortcuts.keys.sorted()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 40, x: 0, y: 16)

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
                .padding(.bottom, 32) // room for fade
            }

            // Bottom fade hint — indicates more content below
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor).opacity(0),
                    Color(NSColor.windowBackgroundColor).opacity(0.92)
                ],
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

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
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
        .background(Color.primary.opacity(0.04))
        .cornerRadius(7)
    }
}

struct KeyBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.1))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

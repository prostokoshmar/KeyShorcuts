import SwiftUI

struct ConversionQueueView: View {
    @ObservedObject private var manager = ConversionManager.shared
    @ObservedObject private var settings = AppSettings.shared
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            LiquidGlassBackground(cornerRadius: 18)
            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                Divider().opacity(0.25)
                contentView
            }
        }
        .frame(width: 500, height: 560)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Convert")
                .font(.system(size: 15, weight: .semibold))
            if manager.pendingCount > 0 {
                Text("\(manager.pendingCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(settings.themeAccent ?? .accentColor)
                    .clipShape(Capsule())
            }
            Spacer()
            HStack(spacing: 10) {
                if manager.pendingCount > 0 {
                    Button("Approve All") { manager.approveAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(settings.themeAccent ?? .accentColor)
                    Button("Dismiss All") { manager.dismissAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        Group {
            if manager.queue.isEmpty && manager.recentResults.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        if !manager.queue.isEmpty {
                            sectionHeader("Pending")
                            ForEach(manager.queue) { item in
                                ConversionRowView(item: item)
                            }
                        }
                        if !manager.recentResults.isEmpty {
                            sectionHeader("Recent")
                            ForEach(manager.recentResults) { item in
                                ConversionRowView(item: item)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No conversions pending")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Rename a file's extension in a watched folder\nand it will appear here for approval.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
    }
}

// MARK: - Row

private struct ConversionRowView: View {
    let item: ConversionItem
    @ObservedObject private var manager = ConversionManager.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            stateIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.detectedSourceFormat.displayName)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                    Text(item.targetFormat.displayName)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))

                if case .converting(let p) = item.state {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(settings.themeAccent ?? .accentColor)
                        .frame(height: 4)
                        .padding(.top, 2)
                }
                if case .failed(let reason) = item.state {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if case .pending = item.state {
                HStack(spacing: 6) {
                    Button("Approve") { manager.approve(item) }
                        .buttonStyle(ConvertButtonStyle(primary: true))
                    Button("Dismiss") { manager.dismiss(item) }
                        .buttonStyle(ConvertButtonStyle(primary: false))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground)
        .cornerRadius(10)
    }

    private var rowBackground: some View {
        if case .pending = item.state {
            return Color.primary.opacity(0.04)
        }
        return Color.clear
    }

    private var stateIcon: some View {
        Group {
            switch item.state {
            case .pending:
                Image(systemName: "clock")
                    .foregroundStyle(.orange)
            case .converting:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .dismissed:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 16))
        .frame(width: 20)
    }
}

// MARK: - Button style

private struct ConvertButtonStyle: ButtonStyle {
    let primary: Bool
    @ObservedObject private var settings = AppSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(primary
                ? (settings.themeAccent ?? Color.accentColor).opacity(configuration.isPressed ? 0.7 : 1)
                : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .cornerRadius(6)
    }
}

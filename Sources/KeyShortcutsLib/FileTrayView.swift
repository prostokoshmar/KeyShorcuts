import SwiftUI
import UniformTypeIdentifiers

struct FileTrayView: View {
    @ObservedObject private var tray = FileTrayManager.shared
    @ObservedObject private var settings = AppSettings.shared
    let onDismiss: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            LiquidGlassBackground(cornerRadius: 18)

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider().opacity(0.25)

                if tray.items.isEmpty {
                    emptyStateView
                } else {
                    itemListView
                }
            }

            // Drop highlight ring
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((settings.themeAccent ?? Color.accentColor).opacity(isDropTargeted ? 0.9 : 0),
                        lineWidth: 2)
                .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        }
        .frame(width: 380, height: 480)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            Self.loadFileURLs(from: providers) { urls in
                FileTrayManager.shared.add(urls)
            }
            return true
        }
        .onAppear { tray.pruneMissing() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "tray.full")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("File Tray")
                .font(.system(size: 15, weight: .semibold))
            if !tray.items.isEmpty {
                Text("\(tray.items.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(settings.themeAccent ?? .accentColor)
                    .clipShape(Capsule())
            }
            Spacer()
            HStack(spacing: 10) {
                if !tray.items.isEmpty {
                    Button("AirDrop All") { tray.airDrop(tray.items) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(settings.themeAccent ?? .accentColor)
                    Button("Clear") { tray.clear() }
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
                .help("Close (Esc)")
            }
        }
    }

    // MARK: - List

    private var itemListView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 4) {
                ForEach(tray.items, id: \.self) { url in
                    FileTrayRowView(url: url)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Drop files here")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Park files for later — drag them back out anywhere,\nor shake a dragged file to add it from anywhere.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Provider helper

    /// Collect file URLs from drag providers, delivering them on the main queue.
    static func loadFileURLs(from providers: [NSItemProvider], into handler: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { handler(urls) }
    }
}

// MARK: - Row

private struct FileTrayRowView: View {
    let url: URL
    @State private var isHovered = false
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(fileDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button { FileTrayManager.shared.airDrop([url]) } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Send via AirDrop")

                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                Button { FileTrayManager.shared.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from tray")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered
                    ? (settings.themeAccent.map { $0.opacity(0.16) } ?? Color.primary.opacity(0.1))
                    : (settings.themeAccent.map { $0.opacity(0.06) } ?? Color.primary.opacity(0.04)))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
    }

    private var fileDetail: String {
        let dir = url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
            return "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) — \(dir)"
        }
        return dir
    }
}

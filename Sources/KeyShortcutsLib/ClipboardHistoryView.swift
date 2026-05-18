import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject private var manager = ClipboardHistoryManager.shared
    @ObservedObject private var settings = AppSettings.shared
    let onItemChosen: (ClipboardItem) -> Void
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

                if manager.items.isEmpty {
                    emptyStateView
                } else {
                    itemListView
                }
            }
        }
        .frame(width: 480, height: 620)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Clipboard History")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 8) {
                if !manager.items.isEmpty {
                    Button("Clear All") { manager.clearAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(AppSettings.shared.clipboardHotkey.displayString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(5)
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
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 4) {
                    ForEach(Array(manager.items.enumerated()), id: \.element.id) { index, item in
                        ClipboardItemRowView(item: item, index: index + 1, onChosen: onItemChosen)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.bottom, 16)
            }

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

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No clipboard history yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Copy some text or images to get started.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct ClipboardItemRowView: View {
    let item: ClipboardItem
    let index: Int
    let onChosen: (ClipboardItem) -> Void

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText  = ""
    @ObservedObject private var settings = AppSettings.shared

    private var pinkAccent: Color { Color(red: 1, green: 0.08, blue: 0.45) }

    var body: some View {
        Group {
            if isEditing {
                editingView
            } else {
                normalView
            }
        }
    }

    // MARK: - Editing view

    private var editingView: some View {
        let editAccent = settings.cuteMode ? pinkAccent : Color.accentColor
        return VStack(alignment: .trailing, spacing: 6) {
            FocusedTextEditor(text: $editText)
                .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 120)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(editAccent.opacity(0.4), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button("Cancel") { isEditing = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button("Save") {
                    ClipboardHistoryManager.shared.updateText(item: item, newText: editText)
                    isEditing = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(editAccent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(editAccent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(editAccent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - Normal view

    private var normalView: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)

            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                // Edit (text only)
                if case .text = item.content {
                    Button {
                        if case .text(let s) = item.content { editText = s }
                        isEditing = true
                        NotificationCenter.default.post(name: .clipboardEditingBegan, object: nil)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit text")
                }

                Button { shareViaAirDrop() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Share via AirDrop")

                Button { ClipboardHistoryManager.shared.delete(item: item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            } else {
                Text(relativeTime)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered
                    ? (settings.cuteMode ? pinkAccent.opacity(0.16) : Color.primary.opacity(0.1))
                    : (settings.cuteMode ? pinkAccent.opacity(0.06) : Color.primary.opacity(0.04)))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onChosen(item) }
        .onDrag { makeItemProvider() }
    }

    // MARK: - Content preview

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let s):
            Text(s)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundStyle(.primary)

        case .table(_, let rows):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Table — \(rows.count) rows × \(rows.first?.count ?? 0) cols")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                TablePreviewView(rows: rows)
            }

        case .image(let img):
            HStack(spacing: 8) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .cornerRadius(5)
                    .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Image")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(Int(img.size.width)) × \(Int(img.size.height))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private var relativeTime: String {
        let interval = Date().timeIntervalSince(item.date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }

    private func makeItemProvider() -> NSItemProvider {
        switch item.content {
        case .text(let s):
            return NSItemProvider(object: s as NSString)
        case .table(_, let rows):
            let tsv = ClipboardHistoryManager.shared.tsvString(from: rows)
            return NSItemProvider(object: tsv as NSString)
        case .image(let img):
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: "public.png", visibility: .all) { completion in
                let rep = NSBitmapImageRep(data: img.tiffRepresentation ?? Data())
                let png = rep?.representation(using: .png, properties: [:]) ?? Data()
                completion(png, nil)
                return nil
            }
            return provider
        }
    }

    private func shareViaAirDrop() {
        var shareItems: [Any]
        switch item.content {
        case .text(let s):    shareItems = [s]
        case .table(_, let rows): shareItems = [ClipboardHistoryManager.shared.tsvString(from: rows)]
        case .image(let img): shareItems = [img]
        }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: shareItems)
    }
}

// MARK: - NSTextView wrapper that grabs first responder in non-activating panels

private struct FocusedTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTextView()
        tv.isEditable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 12)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.delegate = context.coordinator
        context.coordinator.textView = tv

        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.backgroundColor = .clear
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        guard !context.coordinator.didFocus else { return }
        context.coordinator.didFocus = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            tv.window?.makeFirstResponder(tv)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var didFocus = false

        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }
    }
}
// MARK: - Table preview

private struct TablePreviewView: View {
    let rows: [[String]]

    private let maxRows = 3
    private let maxCols = 4

    private var visibleRows: [[String]] { Array(rows.prefix(maxRows)) }
    private var colCount: Int { min(rows.map(\.count).max() ?? 0, maxCols) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleRows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(0..<colCount, id: \.self) { colIdx in
                        let text = colIdx < row.count ? row[colIdx] : ""
                        let isHeader = rowIdx == 0
                        Text(text.isEmpty ? " " : text)
                            .font(.system(size: 9, weight: isHeader ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(isHeader ? Color.primary.opacity(0.07) : Color.clear)
                        if colIdx < colCount - 1 {
                            Divider().frame(width: 1)
                        }
                    }
                }
                if rowIdx < visibleRows.count - 1 {
                    Divider()
                }
            }
            if rows.count > maxRows {
                Text("+ \(rows.count - maxRows) more rows")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 3)
            }
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

#Preview {
    ClipboardHistoryView(
        onItemChosen: { _ in },
        onDismiss: {}
    )
}
// Note: For richer previews, populate ClipboardHistoryManager.shared with mock data.


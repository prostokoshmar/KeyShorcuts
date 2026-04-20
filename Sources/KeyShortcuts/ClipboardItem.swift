import Cocoa

enum ClipboardContent {
    case text(String)
    case image(NSImage)
}

struct ClipboardItem: Identifiable {
    let id: UUID
    let content: ClipboardContent
    let date: Date

    init(content: ClipboardContent) {
        self.id = UUID()
        self.content = content
        self.date = Date()
    }

    // Preserve id and date when updating content (e.g. inline text edit)
    init(updating source: ClipboardItem, content: ClipboardContent) {
        self.id = source.id
        self.content = content
        self.date = source.date
    }
}

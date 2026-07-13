import Cocoa

/// Holds a shelf of file URLs the user has parked for later — drag files in,
/// drag them back out, or AirDrop them. Paths persist across launches.
final class FileTrayManager: ObservableObject {
    static let shared = FileTrayManager()

    @Published private(set) var items: [URL] = []

    private let defaultsKey = "fileTrayPaths"

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        var changed = false
        for url in urls where url.isFileURL {
            let std = url.standardizedFileURL
            guard !items.contains(std),
                  FileManager.default.fileExists(atPath: std.path) else { continue }
            items.append(std)
            changed = true
        }
        if changed { persist() }
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    /// Drop entries whose files no longer exist (e.g. moved or deleted).
    func pruneMissing() {
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != items.count {
            items = existing
            persist()
        }
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.path), forKey: defaultsKey)
    }
}

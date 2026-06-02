import Foundation
import UserNotifications
import Combine

final class ConversionManager: ObservableObject {
    static let shared = ConversionManager()

    @Published private(set) var queue: [ConversionItem] = []
    @Published private(set) var recentResults: [ConversionItem] = []

    private let watcher = FolderWatcher()
    private let workQueue = DispatchQueue(label: "com.keyshortcuts.conversion", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()

    // Track URLs the app just wrote to avoid self-triggering
    private var appWrittenURLs: Set<URL> = []
    private let writtenURLLock = NSLock()

    var pendingCount: Int { queue.filter { $0.state == .pending }.count }

    private init() {
        requestNotificationPermission()

        NotificationCenter.default.addObserver(
            forName: .watchedFoldersChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.restartWatcher() }

        restartWatcher()
    }

    // MARK: - Watcher

    private func restartWatcher() {
        let paths = AppSettings.shared.watchedFolders
        watcher.start(paths: paths)
        watcher.onFilesChanged = { [weak self] urls in
            self?.handleChangedFiles(urls)
        }
    }

    // MARK: - Detection

    private func handleChangedFiles(_ urls: [URL]) {
        for url in urls {
            // Skip files this app just wrote
            writtenURLLock.lock()
            let wasWrittenByUs = appWrittenURLs.contains(url)
            writtenURLLock.unlock()
            if wasWrittenByUs { continue }

            guard let detected = FormatDetector.detect(url: url) else { continue }
            let ext = url.pathExtension.lowercased()
            guard let extFormat = ConversionFormat.extensionMap[ext] else { continue }
            guard detected != extFormat else { continue }      // true type matches extension — nothing to do
            guard !detected.isInputOnly || !extFormat.isInputOnly else { continue }

            let pair = ConversionPair(source: detected, target: extFormat)
            guard ConversionRouter.shared.supports(pair) else { continue }

            // Avoid duplicate queue entries for the same file
            let alreadyQueued = queue.contains { $0.sourceURL == url && $0.state == .pending }
            guard !alreadyQueued else { continue }

            let item = ConversionItem(sourceURL: url, detected: detected, target: extFormat)
            DispatchQueue.main.async {
                self.queue.append(item)
                NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
                if AppSettings.shared.conversionNotificationsEnabled {
                    self.postDetectionNotification(item)
                }
                if AppSettings.shared.conversionAutoApprove {
                    self.approve(item)
                }
            }
        }
    }

    // MARK: - Approval

    func approve(_ item: ConversionItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }),
              queue[idx].state == .pending else { return }
        updateState(id: item.id, state: .converting(progress: 0))
        NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
        performConversion(item)
    }

    func approveAll() {
        let pending = queue.filter { $0.state == .pending }
        for item in pending { approve(item) }
    }

    func dismiss(_ item: ConversionItem) {
        guard let idx = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[idx].state = .dismissed
        NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
        pruneCompleted()
    }

    func dismissAll() {
        for i in queue.indices where queue[i].state == .pending {
            queue[i].state = .dismissed
        }
        NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
        pruneCompleted()
    }

    // MARK: - Conversion

    private func performConversion(_ item: ConversionItem) {
        workQueue.async { [weak self] in
            guard let self = self else { return }

            let pair = ConversionPair(source: item.detectedSourceFormat, target: item.targetFormat)
            guard let engine = ConversionRouter.shared.engine(for: pair) else {
                DispatchQueue.main.async {
                    self.updateState(id: item.id, state: .failed("No engine for \(pair.source.displayName) → \(pair.target.displayName)"))
                    NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
                }
                return
            }

            // Check availability
            let avail = engine.availability(for: pair)
            if case .missingDependency(let dep) = avail {
                DispatchQueue.main.async {
                    self.updateState(id: item.id, state: .failed("Requires \(dep)"))
                    NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
                }
                return
            }
            if case .unsupportedOnThisOS(let reason) = avail {
                DispatchQueue.main.async {
                    self.updateState(id: item.id, state: .failed(reason))
                    NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
                }
                return
            }

            // Build output URL
            let outputURL = buildOutputURL(for: item)
            let originalURL = buildOriginalPreservationURL(for: item)

            // Register URLs we're about to write
            self.markWritten([outputURL, originalURL])

            do {
                let mode = AppSettings.shared.conversionOutputMode

                // Snapshot the source bytes before anything touches the file.
                // This must happen first so we can preserve the original even when
                // outputURL == sourceURL (user renamed photo.png → photo.jpg).
                let origData = try Data(contentsOf: item.sourceURL)

                // Save original bytes under true extension (keep-both / append-suffix)
                if mode == .keepBoth || mode == .appendSuffix {
                    try origData.write(to: originalURL, options: .atomic)
                }

                let tmp = outputURL.deletingLastPathComponent()
                    .appendingPathComponent(".\(UUID().uuidString).ksconv")
                self.markWritten([tmp])

                try engine.convert(item: item, to: tmp, progress: { p in
                    DispatchQueue.main.async {
                        self.updateState(id: item.id, state: .converting(progress: p))
                    }
                })

                // Atomic replace: remove source/target then move tmp into place
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: tmp, to: outputURL)

                // Replace mode: remove source if it wasn't already overwritten above
                if mode == .replace && outputURL.standardizedFileURL != item.sourceURL.standardizedFileURL {
                    try? FileManager.default.removeItem(at: item.sourceURL)
                }

                DispatchQueue.main.async {
                    self.updateState(id: item.id, state: .done)
                    NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
                    // Always notify on completion — user explicitly asked for this
                    self.postCompletionNotification(item)
                    self.pruneCompleted()
                }

            } catch {
                // Clean up temp if still around
                try? FileManager.default.removeItem(at:
                    outputURL.deletingLastPathComponent()
                        .appendingPathComponent(".\(UUID().uuidString).ksconv"))
                DispatchQueue.main.async {
                    self.updateState(id: item.id, state: .failed(error.localizedDescription))
                    NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
                    if AppSettings.shared.conversionNotificationsEnabled {
                        self.postFailureNotification(item, reason: error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - URL helpers

    private func buildOutputURL(for item: ConversionItem) -> URL {
        let dir  = item.sourceURL.deletingLastPathComponent()
        let stem = item.sourceURL.deletingPathExtension().lastPathComponent
        let ext  = item.targetFormat.fileExtension
        let mode = AppSettings.shared.conversionOutputMode
        let name = mode == .appendSuffix ? "\(stem)_converted.\(ext)" : "\(stem).\(ext)"
        let candidate = dir.appendingPathComponent(name)
        // If the output name matches the source file (e.g. user renamed photo.png → photo.jpg
        // and we want to write photo.jpg), overwrite in place rather than creating photo 2.jpg.
        if candidate.standardizedFileURL == item.sourceURL.standardizedFileURL {
            return candidate
        }
        return uniqueURL(dir: dir, name: name)
    }

    private func buildOriginalPreservationURL(for item: ConversionItem) -> URL {
        let dir  = item.sourceURL.deletingLastPathComponent()
        let stem = item.sourceURL.deletingPathExtension().lastPathComponent
        let ext  = item.detectedSourceFormat.fileExtension
        // If preserving as the same name as the source, use source path (will be preserved before overwrite)
        let candidate = dir.appendingPathComponent("\(stem).\(ext)")
        if candidate.standardizedFileURL == item.sourceURL.standardizedFileURL {
            return uniqueURL(dir: dir, name: "\(stem).\(ext)", suffix: " (original)")
        }
        return uniqueURL(dir: dir, name: "\(stem).\(ext)", suffix: " (original)")
    }

    private func uniqueURL(dir: URL, name: String, suffix: String = "") -> URL {
        let fm  = FileManager.default
        let ext = URL(fileURLWithPath: name).pathExtension
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        if !suffix.isEmpty {
            candidate = dir.appendingPathComponent("\(stem)\(suffix).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        var n = 2
        while true {
            let suf = suffix.isEmpty ? " \(n)" : "\(suffix) \(n)"
            candidate = dir.appendingPathComponent("\(stem)\(suf).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    // MARK: - Written-URL tracking

    private func markWritten(_ urls: [URL]) {
        writtenURLLock.lock()
        for u in urls { appWrittenURLs.insert(u) }
        writtenURLLock.unlock()
        // Forget after a generous delay so the watcher's debounce + FSEvents latency can pass
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.writtenURLLock.lock()
            for u in urls { self?.appWrittenURLs.remove(u) }
            self?.writtenURLLock.unlock()
        }
    }

    // MARK: - State helpers

    private func updateState(id: UUID, state: ConversionState) {
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].state = state
        }
    }

    private func pruneCompleted() {
        let done = queue.filter { if case .done = $0.state { return true }; return false }
        recentResults = Array((recentResults + done).suffix(10))
        queue.removeAll { item in
            switch item.state {
            case .done, .dismissed: return true
            case .failed:           return true
            default:                return false
            }
        }
        NotificationCenter.default.post(name: .conversionQueueChanged, object: nil)
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postDetectionNotification(_ item: ConversionItem) {
        let content = UNMutableNotificationContent()
        content.title = "Convert \(item.filename)?"
        content.body  = "\(item.detectedSourceFormat.displayName) file renamed to .\(item.targetFormat.fileExtension) — approve to convert."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "detect-\(item.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func postCompletionNotification(_ item: ConversionItem) {
        let content = UNMutableNotificationContent()
        content.title = "Converted \(item.filename)"
        content.body  = "→ \(item.targetFormat.displayName)"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "done-\(item.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func postFailureNotification(_ item: ConversionItem, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Conversion Failed: \(item.filename)"
        content.body  = reason
        let req = UNNotificationRequest(identifier: "fail-\(item.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

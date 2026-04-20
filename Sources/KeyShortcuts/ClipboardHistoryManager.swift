import Cocoa

class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published private(set) var items: [ClipboardItem] = []

    private var lastChangeCount: Int = -1
    private var pollTimer: Timer?
    private var selectionTimer: Timer?
    private var lastSelectedText: String = ""
    private let userDefaultsKey = "clipboardTextHistory"

    private init() {
        loadPersistedTextItems()
        startPolling()
        NotificationCenter.default.addObserver(self, selector: #selector(limitChanged),
                                               name: .clipboardLimitChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pollingIntervalChanged),
                                               name: .clipboardPollingIntervalChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(autoSelectCopyChanged),
                                               name: .autoSelectCopyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(autoSelectPollingIntervalChanged),
                                               name: .autoSelectPollingIntervalChanged, object: nil)
        if AppSettings.shared.autoSelectCopy { startSelectionMonitor() }
    }

    deinit {
        pollTimer?.invalidate()
        selectionTimer?.invalidate()
    }

    // MARK: - Clipboard polling

    private func startPolling() {
        pollTimer?.invalidate()
        let interval = AppSettings.shared.clipboardPollingInterval
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let text = pb.string(forType: .string), !text.isEmpty {
            addItem(ClipboardItem(content: .text(text)))
        } else if let data = pb.data(forType: .tiff), let image = NSImage(data: data) {
            addItem(ClipboardItem(content: .image(image)))
        } else if let data = pb.data(forType: NSPasteboard.PasteboardType("public.png")),
                  let image = NSImage(data: data) {
            addItem(ClipboardItem(content: .image(image)))
        }
    }

    // MARK: - Auto-select copy

    private func startSelectionMonitor() {
        selectionTimer?.invalidate()
        let interval = AppSettings.shared.autoSelectPollingInterval
        selectionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkSelectedText()
        }
        RunLoop.main.add(selectionTimer!, forMode: .common)
    }

    private func stopSelectionMonitor() {
        selectionTimer?.invalidate()
        selectionTimer = nil
        lastSelectedText = ""
    }

    private func checkSelectedText() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return }
        var selectedRef: AnyObject?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement,
                                            kAXSelectedTextAttribute as CFString,
                                            &selectedRef) == .success,
              let text = selectedRef as? String,
              !text.isEmpty,
              text != lastSelectedText else {
            if selectedRef == nil || (selectedRef as? String)?.isEmpty == true { lastSelectedText = "" }
            return
        }
        lastSelectedText = text
        // Write to system clipboard so ⌘V works immediately (mirrors what ⌘C would have done)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount   // don't re-ingest via the clipboard poller
        addItem(ClipboardItem(content: .text(text)))
    }

    // MARK: - Notification handlers

    @objc private func limitChanged() {
        enforceLimit()
        persistTextItems()
    }

    @objc private func pollingIntervalChanged() {
        startPolling()
    }

    @objc private func autoSelectCopyChanged() {
        if AppSettings.shared.autoSelectCopy {
            startSelectionMonitor()
        } else {
            stopSelectionMonitor()
        }
    }

    @objc private func autoSelectPollingIntervalChanged() {
        if AppSettings.shared.autoSelectCopy { startSelectionMonitor() }
    }

    // MARK: - CRUD

    private func addItem(_ item: ClipboardItem) {
        if case .text(let newText) = item.content,
           let first = items.first, case .text(let oldText) = first.content,
           newText == oldText { return }

        items.insert(item, at: 0)
        enforceLimit()
        persistTextItems()
    }

    private func enforceLimit() {
        let limit = AppSettings.shared.clipboardHistoryLimit
        if items.count > limit { items = Array(items.prefix(limit)) }
    }

    func delete(item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        persistTextItems()
    }

    func clearAll() {
        items.removeAll()
        persistTextItems()
    }

    func updateText(item: ClipboardItem, newText: String) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = ClipboardItem(updating: items[idx], content: .text(newText))
        persistTextItems()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case .text(let s):   pb.setString(s, forType: .string)
        case .image(let img):
            if let tiff = img.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        }
        lastChangeCount = pb.changeCount
    }

    func simulateCmdV() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: CGKeyCode = 9
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
            let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags   = .maskCommand
            keyDown?.post(tap: .cgSessionEventTap)
            keyUp?.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - Persistence (text only; images are in-memory only)

    private func persistTextItems() {
        let strings = items.compactMap { item -> String? in
            if case .text(let s) = item.content { return s }
            return nil
        }
        UserDefaults.standard.set(strings, forKey: userDefaultsKey)
    }

    private func loadPersistedTextItems() {
        guard let strings = UserDefaults.standard.stringArray(forKey: userDefaultsKey) else {
            lastChangeCount = NSPasteboard.general.changeCount
            return
        }
        let limit = AppSettings.shared.clipboardHistoryLimit
        items = strings.prefix(limit).map { ClipboardItem(content: .text($0)) }
        lastChangeCount = NSPasteboard.general.changeCount
    }
}

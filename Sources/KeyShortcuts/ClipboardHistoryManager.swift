import Cocoa

class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published private(set) var items: [ClipboardItem] = []

    private var lastChangeCount: Int = -1
    private var pollTimer: Timer?
    private var selectionTimer: Timer?
    private var mouseMonitor: Any?
    private var mouseDownPoint: NSPoint = .zero
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
        NotificationCenter.default.addObserver(self, selector: #selector(clipboardCaptureEnabledChanged),
                                               name: .clipboardCaptureEnabledChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(autoSelectSimulateCmdCChanged),
                                               name: .autoSelectSimulateCmdCChanged, object: nil)
        if AppSettings.shared.autoSelectCopy { startSelectionMonitor() }
    }

    deinit {
        pollTimer?.invalidate()
        selectionTimer?.invalidate()
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
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
        guard AppSettings.shared.clipboardCaptureEnabled else { return }

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
        stopSelectionMonitor()
        if AppSettings.shared.autoSelectSimulateCmdC {
            startMouseMonitor()
        } else {
            startAXTimer()
        }
    }

    private func stopSelectionMonitor() {
        selectionTimer?.invalidate()
        selectionTimer = nil
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        lastSelectedText = ""
    }

    // MARK: Mouse-drag trigger (Cmd+C simulation — works in browsers)

    private func startMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .leftMouseDown:
                self.mouseDownPoint = NSEvent.mouseLocation
            case .leftMouseUp:
                let loc = NSEvent.mouseLocation
                let dist = hypot(loc.x - self.mouseDownPoint.x, loc.y - self.mouseDownPoint.y)
                // Only fire after a drag (> 4 pt), not a plain click
                guard dist > 4 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.simulateCmdC()
                }
            default: break
            }
        }
    }

    private func simulateCmdC() {
        let src = CGEventSource(stateID: .hidSystemState)
        let cKey: CGKeyCode = 8
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
        // The clipboard poller picks up any resulting content on its next tick
    }

    // MARK: AX polling (direct text reading — native apps only)

    private func startAXTimer() {
        selectionTimer?.invalidate()
        let interval = AppSettings.shared.autoSelectPollingInterval
        selectionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkSelectionViaAX()
        }
        RunLoop.main.add(selectionTimer!, forMode: .common)
    }

    private func checkSelectionViaAX() {
        guard let text = selectedTextViaSystemWide() else {
            lastSelectedText = ""
            return
        }
        guard text != lastSelectedText else { return }
        lastSelectedText = text
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
        addItem(ClipboardItem(content: .text(text)))
    }

    private func selectedTextViaSystemWide() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            if let text = extractSelectedText(from: focused as! AXUIElement) { return text }
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let win = winRef, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        var elemRef: AnyObject?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &elemRef) == .success,
              let elem = elemRef, CFGetTypeID(elem) == AXUIElementGetTypeID() else { return nil }
        return extractSelectedText(from: elem as! AXUIElement)
    }

    private func extractSelectedText(from element: AXUIElement) -> String? {
        var ref: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &ref) == .success,
           let text = ref as? String, !text.isEmpty { return text }
        var rangeRef: AnyObject?
        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef, CFGetTypeID(rangeVal) == AXValueGetTypeID(),
              AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let fullText = valueRef as? String else { return nil }
        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &cfRange), cfRange.length > 0 else { return nil }
        guard let range = Range(NSRange(location: cfRange.location, length: cfRange.length), in: fullText) else { return nil }
        let selected = String(fullText[range])
        return selected.isEmpty ? nil : selected
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
        if AppSettings.shared.autoSelectCopy { startSelectionMonitor() } else { stopSelectionMonitor() }
    }

    @objc private func autoSelectPollingIntervalChanged() {
        if AppSettings.shared.autoSelectCopy && !AppSettings.shared.autoSelectSimulateCmdC { startAXTimer() }
    }

    @objc private func autoSelectSimulateCmdCChanged() {
        if AppSettings.shared.autoSelectCopy { startSelectionMonitor() }
    }

    @objc private func clipboardCaptureEnabledChanged() {
        if AppSettings.shared.clipboardCaptureEnabled {
            startPolling()
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
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

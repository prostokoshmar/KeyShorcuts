import Cocoa

func ksLog(_ msg: String) {
    let line = msg + "\n"
    if let data = line.data(using: .utf8) {
        let url = URL(fileURLWithPath: "/tmp/ks.log")
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        } else { try? data.write(to: url) }
    }
}

class GlobalKeyMonitor {
    private var eventTap: CFMachPort?
    private var holdTimer: Timer?
    private var isOverlayVisible = false
    private var otherKeyPressed = false
    private var lastKeyPressTime: Date?
    private let callback: (Bool) -> Void
    private let clipboardCallback: (() -> Void)?
    private let escapeCallback: (() -> Void)?
    private let keepAwakeCallback: (() -> Void)?
    private let appSwitcherCallback: (() -> Void)?

    init(callback: @escaping (Bool) -> Void,
         clipboardCallback: (() -> Void)? = nil,
         escapeCallback: (() -> Void)? = nil,
         keepAwakeCallback: (() -> Void)? = nil,
         appSwitcherCallback: (() -> Void)? = nil) {
        self.callback = callback
        self.clipboardCallback = clipboardCallback
        self.escapeCallback = escapeCallback
        self.keepAwakeCallback = keepAwakeCallback
        self.appSwitcherCallback = appSwitcherCallback
        setupEventTap()
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    private func setupEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: CGEventTapOptions(rawValue: 0)!, // non-passive so we can suppress ⌘⇧V
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<GlobalKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                // macOS auto-disables taps that are slow; re-enable immediately.
                if type.rawValue == 0xFFFFFFFE || type.rawValue == 0xFFFFFFFF {
                    if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                let suppress = monitor.handleEvent(type: type, event: event)
                return suppress ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            DispatchQueue.main.async { self.showPermissionError() }
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func showPermissionError() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .keyMonitorPermissionFailed,
                                            object: AXIsProcessTrusted())
        }
    }

    private func isOnlyTriggerKey(_ flags: CGEventFlags) -> Bool {
        let key = AppSettings.shared.triggerKey
        guard flags.contains(key.flagMask) else { return false }
        return !key.otherMasks.contains(where: { flags.contains($0) })
    }

    @discardableResult
    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        let settings = AppSettings.shared

        switch type {
        case .flagsChanged:
            let flags = event.flags
            let triggerActive = isOnlyTriggerKey(flags)

            if triggerActive && !isOverlayVisible {
                otherKeyPressed = false

                switch settings.triggerMode {
                case .hold:
                    startHoldTimer()

                case .doublePress:
                    let now = Date()
                    if let last = lastKeyPressTime,
                       now.timeIntervalSince(last) < settings.doublePressInterval {
                        lastKeyPressTime = nil
                        isOverlayVisible = true
                        self.callback(true)
                    } else {
                        lastKeyPressTime = now
                    }
                }

            } else if !flags.contains(settings.triggerKey.flagMask) {
                cancelHoldTimer()
                if isOverlayVisible {
                    isOverlayVisible = false
                    self.callback(false)
                }
            }
            return false

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let relevantMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let flagBits = flags.intersection(relevantMask).rawValue

            let hotkey = AppSettings.shared.clipboardHotkey
            let hotkeyBits = hotkey.cgModifiers.intersection(relevantMask).rawValue
            ksLog("keyDown keyCode=\(keyCode) flags=\(flagBits) | stored keyCode=\(hotkey.keyCode) flags=\(hotkeyBits) char='\(hotkey.keyChar)'")
            if keyCode == hotkey.keyCode &&
               !hotkey.keyChar.isEmpty &&
               flags.intersection(relevantMask) == hotkey.cgModifiers.intersection(relevantMask) {
                cancelHoldTimer()
                clipboardCallback?()
                return true
            }

            let kaHotkey = AppSettings.shared.keepAwakeHotkey
            if !kaHotkey.keyChar.isEmpty &&
               keyCode == kaHotkey.keyCode &&
               flags.intersection(relevantMask) == kaHotkey.cgModifiers.intersection(relevantMask) {
                cancelHoldTimer()
                keepAwakeCallback?()
                return true
            }

            let asHotkey = AppSettings.shared.appSwitcherHotkey
            if !asHotkey.keyChar.isEmpty &&
               keyCode == asHotkey.keyCode &&
               flags.intersection(relevantMask) == asHotkey.cgModifiers.intersection(relevantMask) {
                cancelHoldTimer()
                appSwitcherCallback?()
                return true
            }

            if keyCode == 53 {
                escapeCallback?()
            }

            otherKeyPressed = true
            cancelHoldTimer()
            if isOverlayVisible {
                isOverlayVisible = false
                self.callback(false)
            }
            return false

        default:
            return false
        }
    }

    private func startHoldTimer() {
        cancelHoldTimer()
        let delay = AppSettings.shared.holdDelay
        holdTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, !self.otherKeyPressed else { return }
            self.isOverlayVisible = true
            self.callback(true)
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }
}

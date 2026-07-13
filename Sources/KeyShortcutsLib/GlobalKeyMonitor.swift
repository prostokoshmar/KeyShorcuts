import Cocoa

private let kEscapeKeyCode = 53

class GlobalKeyMonitor {
    private var eventTap: CFMachPort?
    private var holdTimer: Timer?
    private var isOverlayVisible = false
    private var otherKeyPressed = false
    private var lastKeyPressTime: Date?
    private var lastHotkeyTapTimes: [Int: Date] = [:]  // index in `hotkeys` → last tap, for double-tap
    private let callback: (Bool) -> Void
    private let clipboardCallback: (() -> Void)?
    private let escapeCallback: (() -> Void)?
    private let keepAwakeCallback: (() -> Void)?
    private let appSwitcherCallback: (() -> Void)?
    private let fileTrayCallback: (() -> Void)?

    init(callback: @escaping (Bool) -> Void,
         clipboardCallback: (() -> Void)? = nil,
         escapeCallback: (() -> Void)? = nil,
         keepAwakeCallback: (() -> Void)? = nil,
         appSwitcherCallback: (() -> Void)? = nil,
         fileTrayCallback: (() -> Void)? = nil) {
        self.callback = callback
        self.clipboardCallback = clipboardCallback
        self.escapeCallback = escapeCallback
        self.keepAwakeCallback = keepAwakeCallback
        self.appSwitcherCallback = appSwitcherCallback
        self.fileTrayCallback = fileTrayCallback
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
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags

            // Configurable hotkeys, in priority order. The first match is consumed
            // (suppressed) so the underlying app never sees it.
            let hotkeys: [(ClipboardHotkey, (() -> Void)?)] = [
                (settings.clipboardHotkey,   clipboardCallback),
                (settings.keepAwakeHotkey,   keepAwakeCallback),
                (settings.appSwitcherHotkey, appSwitcherCallback),
                (settings.fileTrayHotkey,    fileTrayCallback),
            ]
            for (index, (hotkey, action)) in hotkeys.enumerated()
            where hotkey.matches(keyCode: keyCode, flags: flags) {
                cancelHoldTimer()
                if hotkey.doubleTap {
                    // Fire only on the second press within the double-press window.
                    let now = Date()
                    if let last = lastHotkeyTapTimes[index],
                       now.timeIntervalSince(last) < settings.doublePressInterval {
                        lastHotkeyTapTimes[index] = nil
                        action?()
                    } else {
                        lastHotkeyTapTimes[index] = now
                    }
                } else {
                    action?()
                }
                return true
            }

            if keyCode == kEscapeKeyCode {
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

import Cocoa

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

    init(callback: @escaping (Bool) -> Void,
         clipboardCallback: (() -> Void)? = nil,
         escapeCallback: (() -> Void)? = nil,
         keepAwakeCallback: (() -> Void)? = nil) {
        self.callback = callback
        self.clipboardCallback = clipboardCallback
        self.escapeCallback = escapeCallback
        self.keepAwakeCallback = keepAwakeCallback
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
        let hasAccessibility = AXIsProcessTrusted()

        let alert = NSAlert()
        alert.alertStyle = .warning

        if hasAccessibility {
            alert.messageText = "Input Monitoring Permission Required"
            alert.informativeText = """
                Key Shortcuts needs Input Monitoring access to detect when you hold the trigger key.

                You already granted Accessibility — now please also add Key Shortcuts in:
                System Settings → Privacy & Security → Input Monitoring

                After adding it, relaunch the app.
                """
            alert.addButton(withTitle: "Open Input Monitoring Settings")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                )
            }
        } else {
            alert.messageText = "Permissions Required"
            alert.informativeText = """
                Key Shortcuts needs two permissions:

                1. Accessibility — to read shortcuts from other apps
                   System Settings → Privacy & Security → Accessibility

                2. Input Monitoring — to detect the trigger key
                   System Settings → Privacy & Security → Input Monitoring

                Grant both, then relaunch the app.
                """
            alert.addButton(withTitle: "Open Privacy Settings")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
        }

        NSApp.terminate(nil)
    }

    // Returns true when only the configured trigger key is active (no other modifiers).
    private func isOnlyTriggerKey(_ flags: CGEventFlags) -> Bool {
        let key = AppSettings.shared.triggerKey
        guard flags.contains(key.flagMask) else { return false }
        return !key.otherMasks.contains(where: { flags.contains($0) })
    }

    // Returns true if the event should be suppressed (not passed to other apps).
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
                        // Second press within the window — show overlay.
                        lastKeyPressTime = nil
                        isOverlayVisible = true
                        DispatchQueue.main.async { self.callback(true) }
                    } else {
                        lastKeyPressTime = now
                    }
                }

            } else if !flags.contains(settings.triggerKey.flagMask) {
                // Trigger key released.
                cancelHoldTimer()
                if isOverlayVisible {
                    isOverlayVisible = false
                    DispatchQueue.main.async { self.callback(false) }
                }
            }
            return false

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let relevantMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

            // Clipboard history hotkey — dynamic, set in Preferences. Suppress so it doesn't reach the active app.
            let hotkey = AppSettings.shared.clipboardHotkey
            if keyCode == hotkey.keyCode &&
               !hotkey.keyChar.isEmpty &&
               flags.intersection(relevantMask) == hotkey.cgModifiers.intersection(relevantMask) {
                cancelHoldTimer()
                DispatchQueue.main.async { self.clipboardCallback?() }
                return true // suppress
            }

            // Keep Awake hotkey — suppress and toggle keep awake.
            let kaHotkey = AppSettings.shared.keepAwakeHotkey
            if !kaHotkey.keyChar.isEmpty &&
               keyCode == kaHotkey.keyCode &&
               flags.intersection(relevantMask) == kaHotkey.cgModifiers.intersection(relevantMask) {
                cancelHoldTimer()
                DispatchQueue.main.async { self.keepAwakeCallback?() }
                return true // suppress
            }

            // Esc — let escape callback dismiss the clipboard overlay; pass through to active app.
            if keyCode == 53 {
                DispatchQueue.main.async { self.escapeCallback?() }
            }

            // Any other key pressed — cancel and hide shortcuts overlay.
            otherKeyPressed = true
            cancelHoldTimer()
            if isOverlayVisible {
                isOverlayVisible = false
                DispatchQueue.main.async { self.callback(false) }
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

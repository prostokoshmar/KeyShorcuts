import Cocoa
import SwiftUI
import IOKit.pwr_mgt

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayWindowController!
    private var clipboardController: ClipboardOverlayWindowController!
    private var appSwitcherController: AppSwitcherOverlayWindowController!
    private var keyMonitor: GlobalKeyMonitor!
    private var preferencesWindow: NSWindow?

    private var keepAwakeAssertionID: IOPMAssertionID = 0
    private var keepAwakeEnabled = false
    private weak var keepAwakeMenuItem: NSMenuItem?
    private weak var permissionMenuItem: NSMenuItem?

    private var keepAwakeTimer: Timer?
    private var keepAwakeEndTime: Date?
    private var menuUpdateTimer: Timer?
    private var keepAwakeCurrentMinutes: Double = -1
    private var keepAwakeSubmenuItems: [(item: NSMenuItem, minutes: Double)] = []
    private weak var keepAwakeOffItem: NSMenuItem?
    private weak var keepAwakeCountdownItem: NSMenuItem?
    private weak var keepAwakeCountdownSeparator: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        overlayController       = OverlayWindowController()
        clipboardController     = ClipboardOverlayWindowController()
        appSwitcherController   = AppSwitcherOverlayWindowController()
        _ = ClipboardHistoryManager.shared

        keyMonitor = GlobalKeyMonitor(
            callback: { [weak self] isVisible in
                if isVisible {
                    let shortcuts = ShortcutReader.shared.readShortcuts()
                    let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
                    let appIcon = NSWorkspace.shared.frontmostApplication?.icon
                    self?.overlayController.show(shortcuts: shortcuts, appName: appName, appIcon: appIcon)
                } else {
                    self?.overlayController.hide()
                }
            },
            clipboardCallback: { [weak self] in
                guard let self = self else { return }
                if self.clipboardController.isVisible {
                    self.clipboardController.hide()
                } else {
                    self.clipboardController.show()
                }
            },
            escapeCallback: { [weak self] in
                guard let self = self else { return }
                if self.clipboardController.isVisible { self.clipboardController.hide() }
                if self.appSwitcherController.isVisible { self.appSwitcherController.hide() }
            },
            keepAwakeCallback: { [weak self] in
                self?.toggleKeepAwake()
            },
            appSwitcherCallback: { [weak self] in
                guard let self = self else { return }
                if self.appSwitcherController.isVisible {
                    self.appSwitcherController.hide()
                } else {
                    self.appSwitcherController.show()
                }
            }
        )
        NotificationCenter.default.addObserver(
            forName: .keyMonitorPermissionFailed, object: nil, queue: .main
        ) { [weak self] note in
            let hasAX = note.object as? Bool ?? false
            self?.showPermissionReminder(hasAccessibility: hasAX)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            AutoUpdater.shared.checkSilently()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if keepAwakeEnabled { IOPMAssertionRelease(keepAwakeAssertionID) }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refreshKeepAwakeUI()
    }

    // MARK: - Status bar setup

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Key Shortcuts")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
        }

        let menu = NSMenu()
        menu.delegate = self

        // Keep Awake item with submenu
        let keepAwakeItem = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self

        // Countdown display row (hidden by default, shown when timer is running)
        let countdownItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        countdownItem.isEnabled = false
        countdownItem.isHidden = true
        submenu.addItem(countdownItem)
        keepAwakeCountdownItem = countdownItem

        let countdownSep = NSMenuItem.separator()
        countdownSep.isHidden = true
        submenu.addItem(countdownSep)
        keepAwakeCountdownSeparator = countdownSep

        // Off
        let offItem = NSMenuItem(title: "Off", action: #selector(keepAwakeSelectOff), keyEquivalent: "")
        offItem.state = .on
        submenu.addItem(offItem)
        keepAwakeOffItem = offItem

        submenu.addItem(.separator())

        // Duration presets
        let presets: [(String, Double)] = [
            ("Indefinite", 0),
            ("15 Minutes", 15),
            ("30 Minutes", 30),
            ("1 Hour", 60),
            ("2 Hours", 120),
            ("4 Hours", 240),
        ]
        for (title, minutes) in presets {
            let item = NSMenuItem(title: title, action: #selector(keepAwakeSelectDuration(_:)), keyEquivalent: "")
            item.representedObject = NSNumber(value: minutes)
            submenu.addItem(item)
            keepAwakeSubmenuItems.append((item: item, minutes: minutes))
        }

        keepAwakeItem.submenu = submenu
        menu.addItem(keepAwakeItem)
        keepAwakeMenuItem = keepAwakeItem

        menu.addItem(withTitle: "Clipboard History", action: #selector(toggleClipboardHistory), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Key Shortcuts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: - Keep Awake actions

    @objc private func toggleClipboardHistory() {
        if clipboardController.isVisible { clipboardController.hide() } else { clipboardController.show() }
    }

    @objc private func keepAwakeSelectOff() {
        stopKeepAwake()
    }

    @objc private func keepAwakeSelectDuration(_ sender: NSMenuItem) {
        guard let minutes = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        startKeepAwake(minutes: minutes)
    }

    // Hotkey always activates indefinite mode
    @objc private func toggleKeepAwake() {
        if keepAwakeEnabled { stopKeepAwake() } else { startKeepAwake(minutes: 0) }
    }

    // MARK: - Keep Awake engine

    private func startKeepAwake(minutes: Double) {
        stopKeepAwake()

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "KeyShortcuts Keep Awake" as CFString,
            &keepAwakeAssertionID
        )
        guard result == kIOReturnSuccess else { return }

        keepAwakeEnabled = true
        keepAwakeCurrentMinutes = minutes

        if minutes > 0 {
            let seconds = minutes * 60
            keepAwakeEndTime = Date().addingTimeInterval(seconds)
            keepAwakeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.stopKeepAwake()
            }
            // Refresh the icon badge and menu title every 30 s while the timer ticks
            menuUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.refreshKeepAwakeUI()
            }
        }

        refreshKeepAwakeUI()
    }

    private func stopKeepAwake() {
        keepAwakeTimer?.invalidate(); keepAwakeTimer = nil
        menuUpdateTimer?.invalidate(); menuUpdateTimer = nil
        keepAwakeEndTime = nil
        if keepAwakeEnabled {
            IOPMAssertionRelease(keepAwakeAssertionID)
            keepAwakeAssertionID = 0
        }
        keepAwakeEnabled = false
        keepAwakeCurrentMinutes = -1
        refreshKeepAwakeUI()
    }

    // MARK: - UI refresh

    private func refreshKeepAwakeUI() {
        let remaining = keepAwakeEndTime.map { max(0, $0.timeIntervalSinceNow) }

        // Status bar icon + inline countdown text
        if keepAwakeEnabled {
            statusItem.button?.image = NSImage(systemSymbolName: "keyboard.badge.eye",
                                               accessibilityDescription: "Key Shortcuts – Keep Awake")
            if let rem = remaining, rem > 0 {
                statusItem.button?.title = " \(compact(rem))"
            } else {
                statusItem.button?.title = ""
            }
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "keyboard",
                                               accessibilityDescription: "Key Shortcuts")
            statusItem.button?.title = ""
        }
        statusItem.button?.image?.isTemplate = true

        // Parent menu item title
        if keepAwakeEnabled {
            if let rem = remaining, rem > 0 {
                keepAwakeMenuItem?.title = "Keep Awake — \(verbose(rem))"
            } else {
                keepAwakeMenuItem?.title = "Keep Awake (On)"
            }
        } else {
            keepAwakeMenuItem?.title = "Keep Awake"
        }

        // Countdown row inside submenu
        if keepAwakeEnabled, let rem = remaining, rem > 0 {
            keepAwakeCountdownItem?.title = "⏱  \(verbose(rem)) remaining"
            keepAwakeCountdownItem?.isHidden = false
            keepAwakeCountdownSeparator?.isHidden = false
        } else {
            keepAwakeCountdownItem?.isHidden = true
            keepAwakeCountdownSeparator?.isHidden = true
        }

        // Checkmarks
        keepAwakeOffItem?.state = keepAwakeEnabled ? .off : .on
        for entry in keepAwakeSubmenuItems {
            entry.item.state = (keepAwakeEnabled && entry.minutes == keepAwakeCurrentMinutes) ? .on : .off
        }
    }

    // "47m" / "1h12m" — compact for the icon badge
    private func compact(_ seconds: TimeInterval) -> String {
        let m = Int(ceil(seconds / 60))
        if m >= 60 {
            let h = m / 60; let rem = m % 60
            return rem > 0 ? "\(h)h\(rem)m" : "\(h)h"
        }
        return "\(m)m"
    }

    // "47m left" / "1h 12m left" — verbose for menu titles
    private func verbose(_ seconds: TimeInterval) -> String {
        let m = Int(ceil(seconds / 60))
        if m >= 60 {
            let h = m / 60; let rem = m % 60
            return rem > 0 ? "\(h)h \(rem)m left" : "\(h)h left"
        }
        return "\(m)m left"
    }

    // MARK: - Preferences

    @objc private func showPreferences() {
        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Key Shortcuts Preferences"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow = window
    }

    private func showPermissionReminder(hasAccessibility: Bool) {
        guard permissionMenuItem == nil else { return }
        let url = hasAccessibility
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        let title = hasAccessibility ? "⚠ Grant Input Monitoring Access…" : "⚠ Grant Accessibility Access…"
        let item = NSMenuItem(title: title, action: #selector(openPrivacySettings), keyEquivalent: "")
        item.representedObject = url
        statusItem.menu?.insertItem(item, at: 0)
        statusItem.menu?.insertItem(.separator(), at: 1)
        permissionMenuItem = item
    }

    @objc private func openPrivacySettings(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

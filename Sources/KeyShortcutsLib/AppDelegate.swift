import Cocoa
import SwiftUI
import IOKit.pwr_mgt
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayWindowController!
    private var clipboardController: ClipboardOverlayWindowController!
    private var appSwitcherController: AppSwitcherOverlayWindowController!
    private var keyMonitor: GlobalKeyMonitor!
    private var preferencesWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

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
    private var customDurationWindow: NSWindow?

    // Convert feature
    private var conversionController: ConversionQueueWindowController?
    private weak var conversionMenuItem: NSMenuItem?
    private weak var conversionBadgeItem: NSMenuItem?

    // File tray + shake-to-drop-zone
    private var fileTrayController: FileTrayWindowController?
    private var dragShakeMonitor: DragShakeMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        overlayController       = OverlayWindowController()
        clipboardController     = ClipboardOverlayWindowController()
        appSwitcherController   = AppSwitcherOverlayWindowController()
        conversionController    = ConversionQueueWindowController()
        fileTrayController      = FileTrayWindowController()
        dragShakeMonitor        = DragShakeMonitor()
        _ = ClipboardHistoryManager.shared
        _ = ConversionManager.shared

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
                if self.fileTrayController?.isVisible == true { self.fileTrayController?.hide() }
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
            },
            fileTrayCallback: { [weak self] in
                self?.toggleFileTray()
            }
        )
        NotificationCenter.default.addObserver(
            forName: .showFileTray, object: nil, queue: .main
        ) { [weak self] _ in
            if self?.fileTrayController?.isVisible != true { self?.fileTrayController?.show() }
        }
        NotificationCenter.default.addObserver(
            forName: .conversionQueueChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshConversionUI() }

        NotificationCenter.default.addObserver(
            forName: .keyMonitorPermissionFailed, object: nil, queue: .main
        ) { [weak self] note in
            let hasAX = note.object as? Bool ?? false
            self?.showPermissionReminder(hasAccessibility: hasAX)
        }
        AppSettings.shared.$accentTheme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyStatusBarTint() }
            .store(in: &cancellables)

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

        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Custom…", action: #selector(keepAwakeCustom), keyEquivalent: "")

        keepAwakeItem.submenu = submenu
        menu.addItem(keepAwakeItem)
        keepAwakeMenuItem = keepAwakeItem

        menu.addItem(withTitle: "Clipboard History", action: #selector(toggleClipboardHistory), keyEquivalent: "")
        menu.addItem(withTitle: "File Tray", action: #selector(toggleFileTrayMenu), keyEquivalent: "")

        // Conversions submenu
        let convItem = NSMenuItem(title: "Conversions", action: nil, keyEquivalent: "")
        let convSubmenu = NSMenu()
        convSubmenu.delegate = self

        let openQueueItem = NSMenuItem(title: "Show Queue…", action: #selector(showConversionQueue), keyEquivalent: "")
        convSubmenu.addItem(openQueueItem)
        convSubmenu.addItem(.separator())

        let badgeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        badgeItem.isEnabled = false
        badgeItem.isHidden = true
        convSubmenu.addItem(badgeItem)
        conversionBadgeItem = badgeItem

        convSubmenu.addItem(.separator())
        convSubmenu.addItem(withTitle: "Approve All", action: #selector(approveAllConversions), keyEquivalent: "")
        convSubmenu.addItem(withTitle: "Dismiss All", action: #selector(dismissAllConversions), keyEquivalent: "")

        convItem.submenu = convSubmenu
        menu.addItem(convItem)
        conversionMenuItem = convItem

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Key Shortcuts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: - Conversion actions

    @objc private func showConversionQueue() {
        if conversionController?.isVisible == true {
            conversionController?.hide()
        } else {
            conversionController?.show()
        }
    }

    @objc private func approveAllConversions() {
        ConversionManager.shared.approveAll()
    }

    @objc private func dismissAllConversions() {
        ConversionManager.shared.dismissAll()
    }

    private func refreshConversionUI() {
        let pending = ConversionManager.shared.pendingCount

        // Badge item text
        if pending > 0 {
            conversionBadgeItem?.title = "\(pending) pending"
            conversionBadgeItem?.isHidden = false
            conversionMenuItem?.title = "Conversions (\(pending))"
        } else {
            conversionBadgeItem?.isHidden = true
            conversionMenuItem?.title = "Conversions"
        }

        // Status-bar icon badge for combined keep-awake + pending conversions
        // Only update if keep-awake is off (keep-awake already owns the badge when on)
        if !keepAwakeEnabled {
            applyIdleStatusIcon()
        }
        // If keep-awake is active it already controls the icon; don't override it here.
    }

    // Status icon when keep-awake is off: pending-conversion badge or plain keyboard.
    private func applyIdleStatusIcon() {
        let pending = ConversionManager.shared.pendingCount
        if pending > 0 {
            setStatusBarImage(symbolName: "arrow.triangle.2.circlepath", desc: "Key Shortcuts – \(pending) conversion(s) pending")
            statusItem.button?.title = " \(pending)"
        } else {
            setStatusBarImage(symbolName: "keyboard", desc: "Key Shortcuts")
            statusItem.button?.title = ""
        }
    }

    // MARK: - Keep Awake actions

    @objc private func toggleClipboardHistory() {
        if clipboardController.isVisible { clipboardController.hide() } else { clipboardController.show() }
    }

    @objc private func toggleFileTrayMenu() {
        toggleFileTray()
    }

    private func toggleFileTray() {
        guard let tray = fileTrayController else { return }
        if tray.isVisible { tray.hide() } else { tray.show() }
    }

    @objc private func keepAwakeSelectOff() {
        stopKeepAwake()
    }

    @objc private func keepAwakeSelectDuration(_ sender: NSMenuItem) {
        guard let minutes = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        startKeepAwake(minutes: minutes)
    }

    @objc private func keepAwakeCustom() {
        if let w = customDurationWindow, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let view = KeepAwakeCustomView(
            onStart: { [weak self] minutes in
                self?.customDurationWindow?.close()
                self?.startKeepAwake(minutes: minutes)
            },
            onCancel: { [weak self] in
                self?.customDurationWindow?.close()
            }
        )
        let window = NSPanel(contentViewController: NSHostingController(rootView: view))
        window.title = "Custom Duration"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false  // we keep a strong reference and reuse it
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        customDurationWindow = window
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
            // .common mode so both timers keep firing while the status-bar menu is
            // open (menu tracking blocks default-mode timers — and the menu is
            // exactly where the countdown is displayed).
            let expiry = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
                self?.stopKeepAwake()
            }
            RunLoop.main.add(expiry, forMode: .common)
            keepAwakeTimer = expiry
            // Refresh the icon badge and menu title every 30 s while the timer ticks
            let refresh = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                self?.refreshKeepAwakeUI()
            }
            RunLoop.main.add(refresh, forMode: .common)
            menuUpdateTimer = refresh
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
            setStatusBarImage(symbolName: "keyboard.badge.eye", desc: "Key Shortcuts – Keep Awake")
            if let rem = remaining, rem > 0 {
                statusItem.button?.title = " \(compact(rem))"
            } else {
                statusItem.button?.title = ""
            }
        } else {
            applyIdleStatusIcon()
        }

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

    private func setStatusBarImage(symbolName: String, desc: String) {
        guard let button = statusItem.button else { return }
        if let tint = AppSettings.shared.accentTheme.nsAccent {
            let config = NSImage.SymbolConfiguration(paletteColors: [tint])
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: desc)?
                .withSymbolConfiguration(config) {
                button.image = img
                button.image?.isTemplate = false
                button.contentTintColor = nil
                return
            }
        }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: desc)
        button.image?.isTemplate = true
        button.contentTintColor = nil
    }

    private func applyStatusBarTint() {
        refreshKeepAwakeUI()
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
        window.isReleasedWhenClosed = false  // we keep a strong reference and reuse it
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

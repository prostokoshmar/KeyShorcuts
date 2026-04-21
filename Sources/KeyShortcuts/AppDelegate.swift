import Cocoa
import SwiftUI
import IOKit.pwr_mgt

class AppDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        overlayController       = OverlayWindowController()
        clipboardController     = ClipboardOverlayWindowController()
        appSwitcherController   = AppSwitcherOverlayWindowController()
        _ = ClipboardHistoryManager.shared  // start clipboard polling

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
                if self.clipboardController.isVisible {
                    self.clipboardController.hide()
                }
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
        // If the key monitor fails (permissions revoked after update), add a menu reminder.
        NotificationCenter.default.addObserver(
            forName: .keyMonitorPermissionFailed, object: nil, queue: .main
        ) { [weak self] note in
            let hasAX = note.object as? Bool ?? false
            self?.showPermissionReminder(hasAccessibility: hasAX)
        }

        // Check for updates silently 8 seconds after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            AutoUpdater.shared.checkSilently()
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Key Shortcuts")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()

        let keepAwakeItem = NSMenuItem(title: "Keep Awake", action: #selector(toggleKeepAwake), keyEquivalent: "")
        keepAwakeItem.state = .off
        menu.addItem(keepAwakeItem)
        keepAwakeMenuItem = keepAwakeItem

        menu.addItem(withTitle: "Clipboard History", action: #selector(toggleClipboardHistory), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Key Shortcuts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggleClipboardHistory() {
        if clipboardController.isVisible {
            clipboardController.hide()
        } else {
            clipboardController.show()
        }
    }

    @objc private func toggleKeepAwake() {
        if keepAwakeEnabled {
            IOPMAssertionRelease(keepAwakeAssertionID)
            keepAwakeAssertionID = 0
            keepAwakeEnabled = false
            keepAwakeMenuItem?.state = .off
            keepAwakeMenuItem?.title = "Keep Awake"
            statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Key Shortcuts")
            statusItem.button?.image?.isTemplate = true
        } else {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "KeyShortcuts Keep Awake" as CFString,
                &keepAwakeAssertionID
            )
            if result == kIOReturnSuccess {
                keepAwakeEnabled = true
                keepAwakeMenuItem?.state = .on
                keepAwakeMenuItem?.title = "Keep Awake (On)"
                statusItem.button?.image = NSImage(systemSymbolName: "keyboard.badge.eye", accessibilityDescription: "Key Shortcuts – Keep Awake")
                statusItem.button?.image?.isTemplate = true
            }
        }
    }

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
        let title = hasAccessibility
            ? "⚠ Grant Input Monitoring Access…"
            : "⚠ Grant Accessibility Access…"
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

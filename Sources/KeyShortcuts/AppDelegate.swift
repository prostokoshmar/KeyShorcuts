import Cocoa
import SwiftUI
import IOKit.pwr_mgt

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayWindowController!
    private var clipboardController: ClipboardOverlayWindowController!
    private var keyMonitor: GlobalKeyMonitor!
    private var preferencesWindow: NSWindow?

    private var keepAwakeAssertionID: IOPMAssertionID = 0
    private var keepAwakeEnabled = false
    private weak var keepAwakeMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        overlayController = OverlayWindowController()
        clipboardController = ClipboardOverlayWindowController()
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
            }
        )
        requestAccessibilityPermissions()

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

        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Clipboard History", action: #selector(toggleClipboardHistory), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let keepAwakeItem = NSMenuItem(title: "Keep Awake", action: #selector(toggleKeepAwake), keyEquivalent: "")
        keepAwakeItem.state = .off
        menu.addItem(keepAwakeItem)
        keepAwakeMenuItem = keepAwakeItem

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "About Key Shortcuts", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Key Shortcuts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func checkForUpdates() {
        AutoUpdater.shared.checkWithUI()
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

    private func requestAccessibilityPermissions() {
        if !AXIsProcessTrusted() {
            let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

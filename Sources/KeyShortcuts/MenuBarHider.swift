import Cocoa

final class MenuBarHider: NSObject {
    static let shared = MenuBarHider()

    private var dividerItem: NSStatusItem?
    private var coverPanel: NSPanel?
    private(set) var isInstalled = false
    private(set) var isCollapsed = false

    var onStateChange: ((Bool) -> Void)?

    private override init() { super.init() }

    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        dividerItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = dividerItem?.button else { return }
        // "chevron.left" is available on every macOS version we support
        btn.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Menu bar divider")
        btn.image?.isTemplate = true
        btn.toolTip = "Click to hide/show items to the left  |  ⌘-drag to reposition"
        rebuildMenu()
    }

    func uninstall() {
        hideCover()
        if let item = dividerItem {
            NSStatusBar.system.removeStatusItem(item)
            dividerItem = nil
        }
        isInstalled = false
        isCollapsed = false
        onStateChange?(false)
    }

    @objc func toggle() {
        isCollapsed.toggle()
        isCollapsed ? showCover() : hideCover()
        updateIcon()
        rebuildMenu()
        onStateChange?(isCollapsed)
    }

    // MARK: - Private

    private func rebuildMenu() {
        let menu = NSMenu()
        let actionTitle = isCollapsed ? "Show Hidden Items" : "Hide Items to the Left"
        let actionItem = NSMenuItem(title: actionTitle, action: #selector(toggle), keyEquivalent: "")
        actionItem.target = self
        menu.addItem(actionItem)
        menu.addItem(.separator())
        let removeItem = NSMenuItem(title: "Remove from Menu Bar", action: #selector(uninstallSelf), keyEquivalent: "")
        removeItem.target = self
        menu.addItem(removeItem)
        dividerItem?.menu = menu
    }

    @objc private func uninstallSelf() { uninstall() }

    private func updateIcon() {
        let name = isCollapsed ? "chevron.right" : "chevron.left"
        dividerItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        dividerItem?.button?.image?.isTemplate = true
    }

    private func showCover() {
        guard let btn = dividerItem?.button,
              let win = btn.window else { return }

        // Use the screen that actually contains the status item window.
        let screen = win.screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(win.frame) })
            ?? NSScreen.main!

        let menuBarH = NSStatusBar.system.thickness

        // Cover from left screen edge to the divider's left edge.
        // ignoresMouseEvents = true so the Apple menu and app menus under the cover remain clickable.
        let width = win.frame.minX - screen.frame.minX
        guard width > 1 else { return }

        let coverRect = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - menuBarH,
            width: width,
            height: menuBarH
        )

        let panel = NSPanel(
            contentRect: coverRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        let vfx = NSVisualEffectView(frame: NSRect(origin: .zero, size: coverRect.size))
        vfx.material = .menu
        vfx.state = .active
        vfx.blendingMode = .behindWindow
        vfx.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(vfx)

        panel.orderFrontRegardless()
        coverPanel = panel
    }

    private func hideCover() {
        coverPanel?.orderOut(nil)
        coverPanel = nil
    }
}

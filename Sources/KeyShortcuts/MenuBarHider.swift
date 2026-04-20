import Cocoa

final class MenuBarHider: NSObject {
    static let shared = MenuBarHider()

    private var dividerItem: NSStatusItem?
    private var coverPanel: NSPanel?
    private(set) var isInstalled = false
    private(set) var isCollapsed = false

    var onStateChange: ((Bool) -> Void)?

    private override init() { super.init() }

    // Call from Preferences to add the divider to the menu bar.
    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        dividerItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = dividerItem?.button else { return }
        btn.image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: "Hide menu bar items")
        btn.image?.isTemplate = true
        btn.action = #selector(toggle)
        btn.target = self
        btn.toolTip = "Click to hide/show items to the left\n⌘-drag to reposition"
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
        updateDividerIcon()
        onStateChange?(isCollapsed)
    }

    // MARK: - Cover panel

    private func showCover() {
        guard let btn = dividerItem?.button,
              let win = btn.window else { return }

        let menuBarH = NSStatusBar.system.thickness
        guard let screen = NSScreen.main else { return }

        // Cover from x=0 to the left edge of the divider item.
        // ignoresMouseEvents = true so app menus beneath remain clickable.
        let coverRect = NSRect(
            x: 0,
            y: screen.frame.maxY - menuBarH,
            width: win.frame.minX,
            height: menuBarH
        )
        guard coverRect.width > 0 else { return }

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

    private func updateDividerIcon() {
        let name = isCollapsed ? "chevron.right.2" : "chevron.left.2"
        dividerItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        dividerItem?.button?.image?.isTemplate = true
    }
}

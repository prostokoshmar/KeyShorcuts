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
        btn.image = NSImage(systemSymbolName: "chevron.left",
                            accessibilityDescription: "Menu bar divider")
        btn.image?.isTemplate = true
        btn.toolTip = "Click to hide/show items to the left  |  ⌘-drag to reposition"
        rebuildMenu()
    }

    func uninstall() {
        hideCover()
        if let item = dividerItem { NSStatusBar.system.removeStatusItem(item) }
        dividerItem = nil
        isInstalled  = false
        isCollapsed  = false
        onStateChange?(false)
    }

    @objc func toggle() {
        isCollapsed.toggle()
        isCollapsed ? showCover() : hideCover()
        updateIcon()
        rebuildMenu()
        onStateChange?(isCollapsed)
    }

    // MARK: - Private helpers

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = isCollapsed ? "Show Hidden Items" : "Hide Items to the Left"
        let action = NSMenuItem(title: title, action: #selector(toggle), keyEquivalent: "")
        action.target = self
        menu.addItem(action)
        menu.addItem(.separator())
        let remove = NSMenuItem(title: "Remove from Menu Bar",
                                action: #selector(uninstallSelf), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        dividerItem?.menu = menu
    }

    @objc private func uninstallSelf() { uninstall() }

    private func updateIcon() {
        let name = isCollapsed ? "chevron.right" : "chevron.left"
        dividerItem?.button?.image = NSImage(systemSymbolName: name,
                                             accessibilityDescription: nil)
        dividerItem?.button?.image?.isTemplate = true
    }

    // MARK: - Cover panel

    private func showCover() {
        guard let btn = dividerItem?.button, let win = btn.window else { return }

        let screen = win.screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(win.frame) })
            ?? NSScreen.main!

        let menuBarH = NSStatusBar.system.thickness
        let appMenuEnd = appMenusRightEdge()
        let coverLeft  = max(screen.frame.minX, appMenuEnd)
        let coverRight = win.frame.minX          // left edge of our divider button
        let width = coverRight - coverLeft
        guard width > 1 else { return }

        // AppKit frame for the cover slice (bottom-left origin)
        let coverRect = NSRect(x: coverLeft,
                               y: screen.frame.maxY - menuBarH,
                               width: width,
                               height: menuBarH)

        // ── Panel ────────────────────────────────────────────────────────────
        let panel = NSPanel(contentRect: coverRect,
                            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        // One level above .statusBar so the panel sits in front of the menu bar window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.hasShadow       = false
        panel.backgroundColor = .clear
        panel.isOpaque        = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        // ── Background using Ice's technique ─────────────────────────────────
        // Capture the desktop wallpaper window (owned by Dock, below the desktop)
        // cropped to the exact cover rect. No NSWorkspace file-load or manual
        // crop math — we just ask CoreGraphics for what's visually there.
        if let wallpaper = captureWallpaper(in: coverRect, screen: screen) {
            let iv = NSImageView(frame: NSRect(origin: .zero, size: coverRect.size))
            iv.image = NSImage(cgImage: wallpaper,
                               size: coverRect.size)
            iv.imageScaling   = .scaleAxesIndependently
            iv.autoresizingMask = [.width, .height]
            panel.contentView?.addSubview(iv)
        } else {
            // Fallback: match the menu bar with a visual-effect view
            let vfx = NSVisualEffectView(frame: NSRect(origin: .zero, size: coverRect.size))
            vfx.material       = .menu
            vfx.state          = .active
            vfx.blendingMode   = .behindWindow
            vfx.autoresizingMask = [.width, .height]
            panel.contentView?.addSubview(vfx)
        }

        panel.orderFrontRegardless()
        coverPanel = panel
    }

    private func hideCover() {
        coverPanel?.orderOut(nil)
        coverPanel = nil
    }

    // MARK: - Wallpaper capture (Ice technique)

    /// Captures the desktop wallpaper window cropped to `coverRect`.
    /// `coverRect` is in AppKit screen coordinates (bottom-left origin).
    /// Returns nil if the wallpaper window can't be found or captured.
    private func captureWallpaper(in coverRect: NSRect, screen: NSScreen) -> CGImage? {
        guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] else { return nil }

        // CoreGraphics uses top-left origin; convert once.
        let mainH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgScreen = CGRect(x: screen.frame.minX,
                              y: mainH - screen.frame.maxY,
                              width: screen.frame.width,
                              height: screen.frame.height)
        let cgCover = CGRect(x: coverRect.minX,
                             y: mainH - coverRect.maxY,
                             width: coverRect.width,
                             height: coverRect.height)

        // Find the wallpaper window: owned by Dock, lives below the desktop (layer < 0).
        var wallpaperID: CGWindowID?
        for info in list {
            guard (info[kCGWindowOwnerName as String] as? String) == "Dock",
                  let layer = info[kCGWindowLayer as String] as? Int, layer < 0,
                  let wid   = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            // Pick the one that covers our screen.
            if let bd = info[kCGWindowBounds as String] as? [String: CGFloat] {
                let wf = CGRect(x: bd["X"] ?? 0, y: bd["Y"] ?? 0,
                                width: bd["Width"] ?? 0, height: bd["Height"] ?? 0)
                if cgScreen.intersects(wf) { wallpaperID = wid; break }
            }
        }
        guard let wid = wallpaperID else { return nil }

        // Capture that window, clipped to our cover slice.
        // CGWindowListCreateImage is deprecated in macOS 14 but still functional and
        // is the exact technique Ice uses for wallpaper capture without Screen Recording.
        #if swift(>=5.9)
        return CGWindowListCreateImage(cgCover, .optionIncludingWindow, wid, [])
        #else
        return CGWindowListCreateImage(cgCover, .optionIncludingWindow, wid, [])
        #endif
    }

    // MARK: - App menu boundary

    private func appMenusRightEdge() -> CGFloat {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return 400 }
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var mbRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &mbRef) == .success,
              CFGetTypeID(mbRef!) == AXUIElementGetTypeID() else { return 400 }
        let menuBar = mbRef as! AXUIElement
        var childRef: AnyObject?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childRef) == .success,
              let children = childRef as? [AXUIElement] else { return 400 }

        var rightmost: CGFloat = 0
        for child in children {
            var frameRef: AnyObject?
            guard AXUIElementCopyAttributeValue(child, "AXFrame" as CFString, &frameRef) == .success,
                  let axVal = frameRef else { continue }
            var rect = CGRect.zero
            // AXValue is a CF type; cast via UnsafeRawPointer to avoid the "always succeeds" warning.
            let axValue = unsafeBitCast(axVal, to: AXValue.self)
            AXValueGetValue(axValue, .cgRect, &rect)
            rightmost = max(rightmost, rect.maxX)
        }
        return rightmost > 0 ? rightmost + 12 : 400
    }
}

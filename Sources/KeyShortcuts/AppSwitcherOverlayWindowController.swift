import Cocoa
import SwiftUI

class AppSwitcherOverlayWindowController {
    private var panel: NSPanel?
    private(set) var isVisible = false
    private var mouseMonitor: Any?

    func show() {
        let mouse = NSEvent.mouseLocation
        let apps  = Self.fetchRunningApps()
        guard !apps.isEmpty else { return }

        let size   = AppSwitcherView.containerSize(for: apps.count)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
                     ?? NSScreen.main ?? NSScreen.screens[0]
        let sf     = screen.frame
        let ox     = max(sf.minX, min(mouse.x - size / 2, sf.maxX - size))
        let oy     = max(sf.minY, min(mouse.y - size / 2, sf.maxY - size))
        let frame  = NSRect(x: ox, y: oy, width: size, height: size)

        buildPanel(frame: frame, apps: apps)

        isVisible = true
        panel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.panel?.animator().alphaValue = 1
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let pt = NSEvent.mouseLocation
            if let f = self.panel?.frame, !f.contains(pt) {
                DispatchQueue.main.async { self.hide() }
            }
        }
    }

    func hide() {
        removeMouseMonitor()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.isVisible = false
        })
    }

    // MARK: - Panel

    private func buildPanel(frame: NSRect, apps: [RunningAppEntry]) {
        let view = AppSwitcherView(
            apps: apps,
            onAppChosen:    { [weak self] entry      in self?.handleAppChosen(entry) },
            onWindowChosen: { [weak self] entry, win in self?.handleWindowChosen(entry, win) },
            onDismiss:      { [weak self] in self?.hide() }
        )

        if let p = panel {
            p.setFrame(frame, display: false)
            p.alphaValue = 0
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: frame.size)
            hosting.autoresizingMask = [.width, .height]
            p.contentView = hosting
            return
        }

        let p = NSPanel(
            contentRect: frame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        p.backgroundColor = .clear
        p.isOpaque        = false
        p.hasShadow       = false
        p.level           = .floating
        p.isFloatingPanel = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.alphaValue = 0

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        self.panel = p
    }

    // MARK: - Actions

    private func handleAppChosen(_ entry: RunningAppEntry) {
        hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            entry.app.activate(options: .activateIgnoringOtherApps)
        }
    }

    private func handleWindowChosen(_ entry: RunningAppEntry, _ win: AppWindowInfo) {
        hide()
        let axElem = win.axElement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            entry.app.activate(options: .activateIgnoringOtherApps)
            AXUIElementPerformAction(axElem, kAXRaiseAction as CFString)
        }
    }

    // MARK: - Data

    static func fetchRunningApps() -> [RunningAppEntry] {
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { app in
                RunningAppEntry(id: app.processIdentifier,
                                app: app,
                                windows: fetchWindows(for: app.processIdentifier))
            }
    }

    private static func fetchWindows(for pid: pid_t) -> [AppWindowInfo] {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let axWindows = ref as? [AXUIElement] else { return [] }

        return axWindows.enumerated().map { (i, axWindow) in
            var titleRef: CFTypeRef?
            let title: String
            if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success {
                title = (titleRef as? String) ?? ""
            } else {
                title = ""
            }
            return AppWindowInfo(id: i, title: title, axElement: axWindow)
        }
    }

    private func removeMouseMonitor() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }
}

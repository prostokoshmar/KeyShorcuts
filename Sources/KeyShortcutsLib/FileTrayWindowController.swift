import Cocoa
import SwiftUI

private class KeyableTrayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FileTrayWindowController {
    private var panel: NSPanel?
    private var mouseMonitor: Any?
    private(set) var isVisible = false

    init() {
        let w: CGFloat = 380
        let h: CGFloat = 480
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h)

        let p = KeyableTrayPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.level = .floating
        p.isFloatingPanel = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: FileTrayView(
            onDismiss: { [weak self] in self?.hide() }
        ))
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        self.panel = p
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
        // Center on the screen under the mouse, like the other overlays.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let sf = screen.frame
            let wf = panel?.frame ?? .zero
            panel?.setFrameOrigin(NSPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2 - 8))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        // Gentle fade + rise-in
        if let target = panel?.frame.origin {
            panel?.setFrameOrigin(NSPoint(x: target.x, y: target.y - 8))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel?.animator().alphaValue = 1
                panel?.animator().setFrameOrigin(target)
            }
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let pt = NSEvent.mouseLocation
            if let frame = self.panel?.frame, !frame.contains(pt) { self.hide() }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.13
            panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1
        })
    }
}

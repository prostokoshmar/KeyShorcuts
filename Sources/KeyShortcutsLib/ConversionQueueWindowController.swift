import Cocoa
import SwiftUI

private class KeyableConversionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ConversionQueueWindowController {
    private var panel: NSPanel?
    private var mouseMonitor: Any?
    private(set) var isVisible = false

    init() {
        let w: CGFloat = 500
        let h: CGFloat = 560
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(
            x: screen.midX - w / 2,
            y: screen.midY - h / 2,
            width: w, height: h
        )

        let p = KeyableConversionPanel(
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
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: ConversionQueueView(
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
        if let screen = NSScreen.main {
            let sf = screen.frame
            let wf = panel?.frame ?? .zero
            panel?.setFrameOrigin(NSPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.orderFrontRegardless()

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
        panel?.orderOut(nil)
    }
}

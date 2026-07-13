import Cocoa
import SwiftUI

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class ClipboardOverlayWindowController {
    private var panel: NSPanel?
    private var pendingPaste = false
    private var mouseMonitor: Any?
    private var previousApp: NSRunningApplication?
    private(set) var isVisible = false

    init() {
        let windowWidth:  CGFloat = 480
        let windowHeight: CGFloat = 620
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let frame = NSRect(
            x: screenFrame.midX - windowWidth / 2,
            y: screenFrame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )

        let p = KeyablePanel(
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
        p.alphaValue = 1

        let hosting = NSHostingView(rootView: ClipboardHistoryView(
            onItemChosen: { [weak self] item in self?.handleItemChosen(item) },
            onDismiss:    { [weak self] in self?.hide() }
        ))
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        self.panel = p

        // LSUIElement apps don't become key on click — activate explicitly when editing starts.
        NotificationCenter.default.addObserver(forName: .clipboardEditingBegan, object: nil, queue: .main) { [weak self] _ in
            NSApp.activate(ignoringOtherApps: true)
            self?.panel?.makeKeyAndOrderFront(nil)
        }
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
        previousApp = NSWorkspace.shared.frontmostApplication
        // Center on the screen under the mouse so the overlay shows on the display
        // you're actually using (consistent with the app switcher), not always main.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let sf = screen.frame
            let wf = panel?.frame ?? .zero
            panel?.setFrameOrigin(NSPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
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
            if let frame = self.panel?.frame, !frame.contains(pt) {
                self.hide()
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        removeMouseMonitor()
        let appToRestore = previousApp
        previousApp = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            self.panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1
        })
        appToRestore?.activate(options: .activateIgnoringOtherApps)
        if pendingPaste {
            pendingPaste = false
            ClipboardHistoryManager.shared.simulateCmdV()
        }
    }

    private func removeMouseMonitor() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    private func handleItemChosen(_ item: ClipboardItem) {
        ClipboardHistoryManager.shared.copyToClipboard(item)
        pendingPaste = true
        hide()
    }
}

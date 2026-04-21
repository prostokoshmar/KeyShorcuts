import Cocoa
import SwiftUI

class ClipboardOverlayWindowController {
    private var panel: NSPanel?
    private var pendingPaste = false
    private var mouseMonitor: Any?
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

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.level = .floating
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.alphaValue = 0

        let hosting = NSHostingView(rootView: ClipboardHistoryView(
            onItemChosen: { [weak self] item in self?.handleItemChosen(item) },
            onDismiss:    { [weak self] in self?.hide() }
        ))
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        self.panel = p

        NotificationCenter.default.addObserver(forName: .clipboardEditingBegan, object: nil, queue: .main) { [weak self] _ in
            self?.panel?.makeKey()
        }
    }

    func show() {
        if let screen = NSScreen.main {
            let sf = screen.frame
            let wf = panel?.frame ?? .zero
            panel?.setFrameOrigin(NSPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
        }
        isVisible = true
        panel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.panel?.animator().alphaValue = 1
        }

        // Dismiss on click outside the panel
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let pt = NSEvent.mouseLocation
            if let frame = self.panel?.frame, !frame.contains(pt) {
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
            if self?.pendingPaste == true {
                self?.pendingPaste = false
                ClipboardHistoryManager.shared.simulateCmdV()
            }
        })
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

import Cocoa
import SwiftUI

class OverlayWindowController {
    private var panel: NSPanel?

    init() {
        let windowWidth: CGFloat = 920
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
        p.becomesKeyOnlyIfNeeded = true   // won't steal key focus from other apps
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.alphaValue = 0

        self.panel = p
    }

    func show(shortcuts: [String: [ShortcutItem]], appName: String, appIcon: NSImage?) {
        if let screen = NSScreen.main {
            let sf = screen.frame
            let wf = panel?.frame ?? .zero
            panel?.setFrameOrigin(NSPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
        }

        let overlayView = ShortcutsOverlayView(shortcuts: shortcuts, appName: appName, appIcon: appIcon)
        let hosting = NSHostingView(rootView: overlayView)
        hosting.frame = panel?.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel?.contentView = hosting

        panel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.panel?.animator().alphaValue = 0
        }, completionHandler: {
            self.panel?.orderOut(nil)
        })
    }
}

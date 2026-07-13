import Cocoa
import SwiftUI
import UniformTypeIdentifiers

/// Watches global mouse drags. When the user shakes a file mid-drag,
/// a small drop zone pops up under the cursor with AirDrop / File Tray targets.
final class DragShakeMonitor {
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var samples: [(x: CGFloat, t: TimeInterval)] = []
    private var zone: DropZoneWindowController?
    private var zoneShownForThisDrag = false

    init() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleDrag()
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.dragEnded()
        }
    }

    deinit {
        if let m = dragMonitor { NSEvent.removeMonitor(m) }
        if let m = upMonitor { NSEvent.removeMonitor(m) }
    }

    private func handleDrag() {
        guard AppSettings.shared.shakeToDropZone, !zoneShownForThisDrag else { return }

        let now = ProcessInfo.processInfo.systemUptime
        samples.append((NSEvent.mouseLocation.x, now))
        samples.removeAll { now - $0.t > 0.7 }

        guard detectShake() else { return }
        // Only react when the drag actually carries files.
        guard let urls = currentDragFileURLs(), !urls.isEmpty else {
            samples.removeAll()
            return
        }

        zoneShownForThisDrag = true
        samples.removeAll()
        if zone == nil { zone = DropZoneWindowController() }
        zone?.show(near: NSEvent.mouseLocation)
    }

    private func dragEnded() {
        samples.removeAll()
        zoneShownForThisDrag = false
        // Small delay so a drop landing on the zone is processed before it hides.
        zone?.hideSoon(after: 0.35)
    }

    /// Shake = several rapid horizontal direction reversals with real amplitude.
    private func detectShake() -> Bool {
        guard samples.count >= 8 else { return false }
        var reversals = 0
        var lastDir = 0
        for i in 1..<samples.count {
            let dx = samples[i].x - samples[i - 1].x
            let dir = dx > 2 ? 1 : (dx < -2 ? -1 : 0)
            if dir != 0 {
                if lastDir != 0 && dir != lastDir { reversals += 1 }
                lastDir = dir
            }
        }
        let xs = samples.map(\.x)
        let range = (xs.max() ?? 0) - (xs.min() ?? 0)
        return reversals >= 4 && range >= 30
    }

    private func currentDragFileURLs() -> [URL]? {
        let pb = NSPasteboard(name: .drag)
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]
    }
}

// MARK: - Drop zone panel

final class DropZoneWindowController {
    private var panel: NSPanel?
    private let size = NSSize(width: 300, height: 128)

    init() {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.level = .popUpMenu
        p.isFloatingPanel = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let hosting = NSHostingView(rootView: DropZoneView(
            onAirDrop: { [weak self] urls in
                self?.hideNow()
                // Give the drag session a beat to finish before the share panel opens.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    FileTrayManager.shared.airDrop(urls)
                }
            },
            onTray: { [weak self] urls in
                FileTrayManager.shared.add(urls)
                self?.hideNow()
                NotificationCenter.default.post(name: .showFileTray, object: nil)
            }
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting
        self.panel = p
    }

    func show(near point: NSPoint) {
        guard let panel else { return }
        // Sit just above the cursor so the dragged file isn't already inside it.
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 36)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            let sf = screen.visibleFrame
            origin.x = max(sf.minX + 8, min(origin.x, sf.maxX - size.width - 8))
            origin.y = max(sf.minY + 8, min(origin.y, sf.maxY - size.height - 8))
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hideSoon(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.hideNow()
        }
    }

    func hideNow() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        })
    }
}

// MARK: - Drop zone view

private struct DropZoneView: View {
    let onAirDrop: ([URL]) -> Void
    let onTray: ([URL]) -> Void

    @State private var airTargeted = false
    @State private var trayTargeted = false
    @State private var appeared = false
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            LiquidGlassBackground(cornerRadius: 16)
            HStack(spacing: 10) {
                zoneTile(title: "AirDrop", icon: "dot.radiowaves.left.and.right", targeted: airTargeted)
                    .onDrop(of: [UTType.fileURL], isTargeted: $airTargeted) { providers in
                        FileTrayView.loadFileURLs(from: providers) { onAirDrop($0) }
                        return true
                    }
                zoneTile(title: "Add to Tray", icon: "tray.and.arrow.down", targeted: trayTargeted)
                    .onDrop(of: [UTType.fileURL], isTargeted: $trayTargeted) { providers in
                        FileTrayView.loadFileURLs(from: providers) { onTray($0) }
                        return true
                    }
            }
            .padding(12)
        }
        .frame(width: 300, height: 128)
        // Little pop on appear
        .scaleEffect(appeared ? 1.0 : 0.85)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { appeared = true }
        }
        .onDisappear { appeared = false }
    }

    private func zoneTile(title: String, icon: String, targeted: Bool) -> some View {
        let accent = settings.themeAccent ?? Color.accentColor
        return VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(targeted ? accent : Color.secondary)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(targeted ? accent : Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(targeted ? accent.opacity(0.14) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(targeted ? accent.opacity(0.8) : Color.primary.opacity(0.12),
                        style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [5, 4]))
        )
        .scaleEffect(targeted ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.13), value: targeted)
        .contentShape(Rectangle())
    }
}

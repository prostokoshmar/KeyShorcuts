import SwiftUI

/// Inline shortcut recorder. Pass a @Binding to any ClipboardHotkey stored in AppSettings.
/// Requires at least one modifier; Esc cancels without saving.
struct HotkeyRecorderView: View {
    @Binding var hotkey: ClipboardHotkey
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isRecording ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.18),
                                lineWidth: 1)
                )
            Text(isRecording ? "Type shortcut…" : hotkey.displayString)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: 150, height: 30)
        .contentShape(Rectangle())
        .onTapGesture { startRecording() }
        .onDisappear { stopMonitor() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { self.stopMonitor() }

            if event.keyCode == 53 { // Esc — cancel
                self.isRecording = false
                return nil
            }

            let mods = event.modifierFlags.toCGEventFlags
            let standard: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            guard !mods.intersection(standard).isEmpty else { return nil }

            let char = Self.keyName(for: event)
            self.hotkey = ClipboardHotkey(keyCode: Int(event.keyCode), keyChar: char, modifiers: mods.rawValue)
            // Persistence is handled by AppSettings.didSet
            self.isRecording = false
            return nil
        }
    }

    private func stopMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        isRecording = false
    }

    private static func keyName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 51:  return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 116: return "PgUp"
        case 121: return "PgDn"
        case 115: return "Home"
        case 119: return "End"
        default:  return event.charactersIgnoringModifiers?.uppercased() ?? "\(event.keyCode)"
        }
    }
}

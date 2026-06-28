import SwiftUI

/// Inline shortcut recorder. Pass a @Binding to any ClipboardHotkey stored in AppSettings.
/// Accepts either a modifier chord (e.g. ⌘⇧V) or a single key (e.g. F5). Esc cancels.
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
            Text(isRecording ? "Press keys or an F-key…" : hotkey.displayString)
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
            if event.keyCode == 53 { // Esc — cancel
                self.stopMonitor()
                return nil
            }

            let mods = event.modifierFlags.toCGEventFlags
            let standard: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let hasModifier = !mods.intersection(standard).isEmpty

            // A bare key (no modifier) is only accepted if it's a function key — those are
            // safe one-press triggers. Any other key needs a modifier, so keep waiting.
            guard hasModifier || Self.isFunctionKey(Int(event.keyCode)) else { return nil }

            let char = Self.keyName(for: event)
            self.hotkey = ClipboardHotkey(keyCode: Int(event.keyCode), keyChar: char,
                                          modifiers: mods.rawValue, doubleTap: self.hotkey.doubleTap)
            // Persistence is handled by AppSettings.didSet
            self.stopMonitor()
            return nil
        }
    }

    /// Function keys F1–F20 — the only keys allowed as a modifier-less single trigger.
    private static let functionKeyCodes: Set<Int> =
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    private static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyCodes.contains(keyCode)
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
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 90:  return "F20"
        default:  return event.charactersIgnoringModifiers?.uppercased() ?? "key \(event.keyCode)"
        }
    }
}

/// A labelled hotkey row: the recorder plus a "double-tap" toggle.
/// Used by every configurable feature shortcut so they all share the same options.
struct HotkeyField: View {
    let label: String
    /// This feature's name, used to detect collisions with other feature hotkeys.
    /// Pass "" to skip conflict checking.
    var feature: String = ""
    @Binding var hotkey: ClipboardHotkey
    @ObservedObject private var settings = AppSettings.shared

    private var conflicts: [String] {
        guard !feature.isEmpty else { return [] }
        return settings.conflictingFeatures(for: hotkey, excluding: feature)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                HotkeyRecorderView(hotkey: $hotkey)
            }
            Toggle("Double-tap to trigger", isOn: $hotkey.doubleTap)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .font(.caption)

            if !conflicts.isEmpty {
                Label("Same as \(conflicts.joined(separator: ", ")) — only one will respond.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

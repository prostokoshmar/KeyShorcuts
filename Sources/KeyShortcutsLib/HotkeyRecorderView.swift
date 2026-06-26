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
            Text(isRecording ? "Press a key…" : hotkey.displayString)
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
            // A single key (no modifier) is allowed — e.g. a function key as a one-press trigger.
            let char = Self.keyName(for: event)
            self.hotkey = ClipboardHotkey(keyCode: Int(event.keyCode), keyChar: char,
                                          modifiers: mods.rawValue, doubleTap: self.hotkey.doubleTap)
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
    @Binding var hotkey: ClipboardHotkey

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
        }
    }
}

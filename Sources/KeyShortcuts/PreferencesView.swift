import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Preferences")
                .font(.title2.bold())

            Divider()

            // MARK: Trigger key
            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger Key")
                    .font(.headline)
                Picker("", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // MARK: Trigger mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger Mode")
                    .font(.headline)
                Picker("", selection: $settings.triggerMode) {
                    ForEach(TriggerMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // MARK: Duration slider (context-sensitive)
            if settings.triggerMode == .hold {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Hold Duration").font(.headline)
                        Spacer()
                        Text("\(settings.holdDelay, specifier: "%.1f") s")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.holdDelay, in: 0.1...2.0, step: 0.1)
                    HStack { Text("0.1 s"); Spacer(); Text("2.0 s") }
                        .font(.caption).foregroundStyle(.tertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Double Press Window").font(.headline)
                        Spacer()
                        Text("\(Int(settings.doublePressInterval * 1000)) ms")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.doublePressInterval, in: 0.1...0.8, step: 0.05)
                    HStack { Text("100 ms"); Spacer(); Text("800 ms") }
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            Divider()

            // MARK: Keep Awake
            VStack(alignment: .leading, spacing: 8) {
                Text("Keep Awake")
                    .font(.headline)
                HStack {
                    Text("Shortcut")
                    Spacer()
                    HotkeyRecorderView(hotkey: $settings.keepAwakeHotkey)
                }
            }

            Divider()

            // MARK: Clipboard History
            VStack(alignment: .leading, spacing: 12) {
                Text("Clipboard History")
                    .font(.headline)

                HStack {
                    Text("Shortcut")
                    Spacer()
                    HotkeyRecorderView(hotkey: $settings.clipboardHotkey)
                }

                HStack {
                    Text("Maximum items")
                    Spacer()
                    Picker("", selection: $settings.clipboardHistoryLimit) {
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("50").tag(50)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Polling interval")
                        Spacer()
                        Text("\(settings.clipboardPollingInterval, specifier: "%.1f") s")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.clipboardPollingInterval, in: 0.2...5.0, step: 0.1)
                    HStack { Text("0.2 s"); Spacer(); Text("5.0 s") }
                        .font(.caption).foregroundStyle(.tertiary)
                    Text("Reads one integer per tick — negligible CPU at any interval.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            Divider()

            // MARK: Auto-copy selected text
            VStack(alignment: .leading, spacing: 8) {
                Text("Auto-copy Selected Text")
                    .font(.headline)

                Toggle("Enable", isOn: $settings.autoSelectCopy)
                    .toggleStyle(.switch)

                Text("Adds selected text to history automatically without ⌘C. One Accessibility call per tick — typically < 0.1 ms.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Polling interval")
                        Spacer()
                        Text("\(settings.autoSelectPollingInterval, specifier: "%.1f") s")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: $settings.autoSelectPollingInterval, in: 0.1...2.0, step: 0.1)
                        .disabled(!settings.autoSelectCopy)
                    HStack { Text("0.1 s"); Spacer(); Text("2.0 s") }
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .opacity(settings.autoSelectCopy ? 1 : 0.4)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)
            ClipboardTab()
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
                .tag(1)
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(2)
        }
        .frame(width: 460, height: 360)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Trigger key
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trigger Key").font(.headline)
                    Picker("", selection: $settings.triggerKey) {
                        ForEach(TriggerKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }

                // Trigger mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trigger Mode").font(.headline)
                    Picker("", selection: $settings.triggerMode) {
                        ForEach(TriggerMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }

                Divider()

                if settings.triggerMode == .hold {
                    VStack(alignment: .leading, spacing: 6) {
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
                    VStack(alignment: .leading, spacing: 6) {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep Awake").font(.headline)
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        HotkeyRecorderView(hotkey: $settings.keepAwakeHotkey)
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Clipboard

private struct ClipboardTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Clipboard History").font(.headline)

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
                        .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Polling interval")
                            Spacer()
                            Text("\(settings.clipboardPollingInterval, specifier: "%.1f") s")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $settings.clipboardPollingInterval, in: 0.2...5.0, step: 0.1)
                        HStack { Text("0.2 s"); Spacer(); Text("5.0 s") }
                            .font(.caption).foregroundStyle(.tertiary)
                        Text("One integer read per tick — negligible CPU at any interval.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Plain Paste").font(.headline)
                    Toggle("Enable", isOn: $settings.plainPaste).toggleStyle(.switch)
                    Text("Uses Paste and Match Style (⌥⇧⌘V) instead of ⌘V — strips source formatting to match destination.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Auto-copy Selected Text").font(.headline)
                    Toggle("Enable", isOn: $settings.autoSelectCopy).toggleStyle(.switch)
                    Text("Adds selected text to history without ⌘C. One Accessibility call per tick — typically < 0.1 ms.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
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
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Key Shortcuts").font(.title2.bold())
                Text("Version \(version)").foregroundStyle(.secondary)
            }

            Divider().frame(width: 200)

            Button("Check for Updates…") {
                AutoUpdater.shared.checkWithUI()
            }
            .controlSize(.regular)

            Link("View on GitHub",
                 destination: URL(string: "https://github.com/prostokoshmar/KeyShorcuts")!)
                .font(.callout)

            Spacer()

            Text("Made with ♥ using Swift & AppKit")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

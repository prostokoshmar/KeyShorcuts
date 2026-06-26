import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)
            ClipboardTab()
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
                .tag(1)
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(2)
            ConvertTab()
                .tabItem { Label("Convert", systemImage: "arrow.triangle.2.circlepath") }
                .tag(3)
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(4)
        }
        .frame(width: 500, height: 580)
        .tint(settings.cuteMode ? Color(red: 1, green: 0.08, blue: 0.45) : .accentColor)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Startup
                VStack(alignment: .leading, spacing: 8) {
                    Text("Startup").font(.headline)
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                }

                Divider()

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
                    HotkeyField(label: "Shortcut", hotkey: $settings.keepAwakeHotkey)
                    Text("Shortcut always activates indefinite mode. Use the menu icon to set a timed duration.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("App Switcher").font(.headline)
                    HotkeyField(label: "Shortcut", hotkey: $settings.appSwitcherHotkey)
                    Picker("Show", selection: $settings.appSwitcherShowAll) {
                        Text("All running apps").tag(true)
                        Text("Apps with open windows").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text("Press Esc to dismiss. Hover multi-window apps to see their windows.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
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

                    HotkeyField(label: "Shortcut", hotkey: $settings.clipboardHotkey)

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
                    Text("Auto-copy Selected Text").font(.headline)
                    Toggle("Enable", isOn: $settings.autoSelectCopy).toggleStyle(.switch)

                    Toggle("Simulate ⌘C on selection", isOn: $settings.autoSelectSimulateCmdC)
                        .toggleStyle(.switch)
                        .disabled(!settings.autoSelectCopy)
                    Text("ON: detects selection range via AX, fires ⌘C — works in browsers. OFF: reads text directly via AX — native apps only.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(settings.autoSelectCopy ? 1 : 0.4)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Polling interval")
                            Spacer()
                            Text("\(settings.autoSelectPollingInterval, specifier: "%.1f") s")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $settings.autoSelectPollingInterval, in: 0.5...5.0, step: 0.5)
                            .disabled(!settings.autoSelectCopy)
                        HStack { Text("0.5 s"); Spacer(); Text("5.0 s") }
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .opacity(settings.autoSelectCopy ? 1 : 0.4)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Liquid Glass").font(.headline)
                    Toggle("Enable Liquid Glass effect", isOn: $settings.liquidGlassEnabled)
                        .toggleStyle(.switch)
                    Text("Applies frosted-glass depth to all overlays — shortcuts panel, clipboard history, and app switcher. Works on macOS 13 and later.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if settings.liquidGlassEnabled {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Glass Intensity").font(.headline)
                        Picker("", selection: $settings.liquidGlassIntensity) {
                            ForEach(LiquidGlassIntensity.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented).labelsHidden()

                        HStack(spacing: 0) {
                            ForEach(LiquidGlassIntensity.allCases, id: \.self) { lvl in
                                Text(intensityDescription(lvl))
                                    .font(.caption).foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Cute Mode").font(.headline)
                        Text("🌸")
                    }
                    Toggle("Enable Cute Mode", isOn: $settings.cuteMode)
                        .toggleStyle(.switch)
                        .tint(Color(red: 1, green: 0.08, blue: 0.45))
                    Text("Applies a deep pink tint to all overlay backgrounds, key badges, hover states, and borders.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("App Switcher Layout").font(.headline)
                    Picker("", selection: $settings.appSwitcherLayout) {
                        ForEach(AppSwitcherLayout.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text("Radial Ring floats icons in a circle. Segmented Torus slices a glass donut into wedge tiles. Concentric arranges apps in two rings.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
    }

    private func intensityDescription(_ lvl: LiquidGlassIntensity) -> String {
        switch lvl {
        case .subtle:   return "Minimal blur"
        case .balanced: return "Medium refraction"
        case .max:      return "Full chromatic"
        }
    }
}

// MARK: - Convert

private struct ConvertTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var manager  = ConversionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Watched Folders
                VStack(alignment: .leading, spacing: 8) {
                    Text("Watched Folders").font(.headline)
                    Text("When a file's extension doesn't match its true format, a conversion is proposed. Noisy system paths (Library, .build, node_modules, .git) are always excluded.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Home folder quick-toggle
                    HStack {
                        Image(systemName: "house")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Home folder (~)").font(.system(size: 12, weight: .medium))
                            Text("Covers Desktop, Downloads, Documents and everything else").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { settings.watchedFolders.contains(NSHomeDirectory()) },
                            set: { on in
                                if on { if !settings.watchedFolders.contains(NSHomeDirectory()) { settings.watchedFolders.append(NSHomeDirectory()) } }
                                else  { settings.watchedFolders.removeAll { $0 == NSHomeDirectory() } }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)

                    // Additional custom folders (anything that isn't home)
                    ForEach(settings.watchedFolders.filter { $0 != NSHomeDirectory() }, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 13))
                            Text(path)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                settings.watchedFolders.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(8)
                    }

                    Button("Add Folder…") { addFolder() }
                        .controlSize(.small)
                }

                Divider()

                // Behavior
                VStack(alignment: .leading, spacing: 8) {
                    Text("Behavior").font(.headline)

                    Toggle("Auto-approve conversions", isOn: $settings.conversionAutoApprove)
                        .toggleStyle(.switch)
                    Text("When ON, files are converted automatically without prompting. When OFF (default), each conversion requires your approval.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Send notifications", isOn: $settings.conversionNotificationsEnabled)
                        .toggleStyle(.switch)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Mode").font(.headline)
                    Picker("", selection: $settings.conversionOutputMode) {
                        ForEach(ConversionOutputMode.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }

                Divider()

                // Engine status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Engines").font(.headline)
                    engineRow("Images / PDF / Config / Archives", available: true, note: "Built-in")
                    engineRow("Audio & Video (ffmpeg)", available: FFmpegEngine.shared.ffmpegPath != nil,
                              note: FFmpegEngine.shared.ffmpegPath != nil ? "Detected" : "Not found — brew install ffmpeg")
                    engineRow("Office (LibreOffice)", available: isCommandAvailable("soffice"),
                              note: isCommandAvailable("soffice") ? "Detected" : "Not found — install LibreOffice")
                    engineRow("Documents (pandoc)", available: isCommandAvailable("pandoc"),
                              note: isCommandAvailable("pandoc") ? "Detected" : "Not found — brew install pandoc")
                    engineRow("E-Books (Calibre)", available: isCommandAvailable("ebook-convert"),
                              note: isCommandAvailable("ebook-convert") ? "Detected" : "Not found — install Calibre")
                }
            }
            .padding(24)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            let newPaths = panel.urls.map(\.path).filter { !settings.watchedFolders.contains($0) }
            settings.watchedFolders.append(contentsOf: newPaths)
        }
    }

    private func engineRow(_ name: String, available: Bool, note: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? .green : .orange)
                .font(.system(size: 13))
            Text(name).font(.system(size: 12))
            Spacer()
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }

    private func isCommandAvailable(_ cmd: String) -> Bool {
        let fm = FileManager.default
        let paths = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/Applications/LibreOffice.app/Contents/MacOS"]
        for p in paths {
            if fm.isExecutableFile(atPath: "\(p)/\(cmd)") { return true }
        }
        return false
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
#Preview {
    PreferencesView()
}

import Cocoa

// ── Configure before shipping ────────────────────────────────────────────────
// Set this to your GitHub "username/repo" — the updater checks releases there.
private let kGitHubRepo = "prostokoshmar/KeyShorcuts"
// ─────────────────────────────────────────────────────────────────────────────

final class AutoUpdater {
    static let shared = AutoUpdater()
    private init() {}

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // Called on launch: checks silently, shows alert only when an update exists.
    func checkSilently() {
        guard kGitHubRepo != "YOUR_USERNAME/KeyShortcuts" else { return }
        fetchLatestRelease { [weak self] release in
            guard let self, let release else { return }
            let latest = release.tagName.trimmingCharacters(in: .init(charactersIn: "v"))
            if self.isNewer(latest, than: self.currentVersion) {
                self.showUpdateAlert(release, latestVersion: latest)
            }
        }
    }

    // Called from "Check for Updates…" menu item: always shows a result.
    func checkWithUI() {
        fetchLatestRelease { [weak self] release in
            guard let self else { return }
            guard let release else {
                self.showError("Could not reach GitHub. Check your internet connection.")
                return
            }
            let latest = release.tagName.trimmingCharacters(in: .init(charactersIn: "v"))
            if self.isNewer(latest, than: self.currentVersion) {
                self.showUpdateAlert(release, latestVersion: latest)
            } else {
                let a = NSAlert()
                a.messageText = "You're up to date"
                a.informativeText = "Key Shortcuts \(self.currentVersion) is the latest version."
                a.runModal()
            }
        }
    }

    // MARK: - Private

    private func fetchLatestRelease(completion: @escaping (GitHubRelease?) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(kGitHubRepo)/releases/latest") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let release = data.flatMap { try? JSONDecoder().decode(GitHubRelease.self, from: $0) }
            DispatchQueue.main.async { completion(release) }
        }.resume()
    }

    private func showUpdateAlert(_ release: GitHubRelease, latestVersion: String) {
        let a = NSAlert()
        a.messageText = "Update Available — v\(latestVersion)"
        let notes = release.body.flatMap { $0.isEmpty ? nil : $0 } ?? "A new version is ready."
        a.informativeText = notes
        a.addButton(withTitle: "Download & Install")
        a.addButton(withTitle: "Later")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        if let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
           let url = URL(string: asset.browserDownloadURL) {
            downloadAndInstall(from: url)
        } else if let url = URL(string: release.htmlURL) {
            NSWorkspace.shared.open(url) // fallback: open release page
        }
    }

    private func downloadAndInstall(from url: URL) {
        // Show a simple non-modal progress window
        let win = makeProgressWindow()
        win.makeKeyAndOrderFront(nil)

        URLSession.shared.downloadTask(with: url) { [weak self] tmpURL, _, error in
            DispatchQueue.main.async {
                win.orderOut(nil)
                guard let self else { return }
                if let error {
                    self.showError("Download failed: \(error.localizedDescription)")
                    return
                }
                guard let tmpURL else { return }
                self.installUpdate(zipURL: tmpURL)
            }
        }.resume()
    }

    private func installUpdate(zipURL: URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("KSUpdate_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

            let unzip = Process()
            unzip.launchPath = "/usr/bin/unzip"
            unzip.arguments = ["-q", zipURL.path, "-d", tmp.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { throw NSError(domain: "unzip", code: 1) }

            guard let newApp = (try FileManager.default.contentsOfDirectory(
                at: tmp, includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "app" }) else {
                throw NSError(domain: "app-not-found", code: 1)
            }

            let currentApp = Bundle.main.bundleURL

            // Wait for this process to quit, then replace and relaunch.
            // Do NOT re-sign: the zip already carries the build signature; re-signing
            // with a new ad-hoc hash would revoke macOS Accessibility/Input Monitoring access.
            let script = """
            sleep 2
            rm -rf '\(currentApp.path)'
            cp -R '\(newApp.path)' '\(currentApp.path)'
            open -n '\(currentApp.path)'
            """
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", script]
            try task.run()

            NSApp.terminate(nil)

        } catch {
            showError("Install failed: \(error.localizedDescription)\n\nTry downloading manually.")
        }
    }

    private func makeProgressWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 72),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        win.title = "Key Shortcuts"
        win.center()

        let label = NSTextField(labelWithString: "Downloading update…")
        label.frame = NSRect(x: 20, y: 46, width: 260, height: 18)
        label.font = .systemFont(ofSize: 13)

        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 260, height: 16))
        bar.style = .bar
        bar.isIndeterminate = true
        bar.startAnimation(nil)

        win.contentView?.addSubview(label)
        win.contentView?.addSubview(bar)
        return win
    }

    private func showError(_ message: String) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Update Failed"
        a.informativeText = message
        a.runModal()
    }

    private func isNewer(_ a: String, than b: String) -> Bool {
        let parse: (String) -> [Int] = { $0.split(separator: ".").compactMap { Int($0) } }
        let va = parse(a), vb = parse(b)
        for i in 0..<max(va.count, vb.count) {
            let x = i < va.count ? va[i] : 0
            let y = i < vb.count ? vb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// MARK: - GitHub API models

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let htmlURL: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body, assets
        case htmlURL = "html_url"
    }
}

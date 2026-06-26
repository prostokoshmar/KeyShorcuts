import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` so the rest of the app can treat
/// "launch at login" as a simple Bool. macOS 13+ (matches the app's minimum).
enum LoginItem {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the app as a login item.
    /// Returns `true` on success; on failure the state is left unchanged.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("KeyShortcuts: failed to \(enabled ? "enable" : "disable") launch at login — \(error.localizedDescription)")
            return false
        }
    }
}

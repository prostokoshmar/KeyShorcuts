import Cocoa

enum ConversionOutputMode: String, CaseIterable {
    case keepBoth     = "keepBoth"
    case replace      = "replace"
    case appendSuffix = "appendSuffix"

    var displayName: String {
        switch self {
        case .keepBoth:     return "Keep both (original + converted)"
        case .replace:      return "Replace original"
        case .appendSuffix: return "Append suffix to converted"
        }
    }
}

enum LiquidGlassIntensity: String, CaseIterable {
    case subtle   = "subtle"
    case balanced = "balanced"
    case max      = "max"

    var displayName: String {
        switch self {
        case .subtle:   return "Subtle"
        case .balanced: return "Balanced"
        case .max:      return "Max"
        }
    }

    // Values mirrored from the design's INTENSITY presets
    var tint:   Double { switch self { case .subtle: 0.10; case .balanced: 0.16; case .max: 0.22 } }
    var spec:   Double { switch self { case .subtle: 0.22; case .balanced: 0.34; case .max: 0.50 } }
    var edge:   Double { switch self { case .subtle: 0.20; case .balanced: 0.32; case .max: 0.48 } }
    var drop:   Double { switch self { case .subtle: 0.30; case .balanced: 0.45; case .max: 0.60 } }
    var chroma: Double { switch self { case .subtle: 0;    case .balanced: 0.5;  case .max: 1.0  } }

    var material: NSVisualEffectView.Material {
        switch self {
        case .subtle:   return .sidebar
        case .balanced: return .hudWindow
        case .max:      return .underWindowBackground
        }
    }
}

enum AppSwitcherLayout: String, CaseIterable {
    case radialRing     = "radialRing"
    case segmentedTorus = "segmentedTorus"
    case concentric     = "concentric"

    var displayName: String {
        switch self {
        case .radialRing:     return "Radial Ring"
        case .segmentedTorus: return "Segmented Torus"
        case .concentric:     return "Concentric"
        }
    }
}

enum TriggerMode: String, CaseIterable {
    case hold = "hold"
    case doublePress = "doublePress"

    var displayName: String {
        switch self {
        case .hold:        return "Hold"
        case .doublePress: return "Double Press"
        }
    }
}

enum TriggerKey: String, CaseIterable {
    case command = "command"
    case option  = "option"
    case control = "control"
    case shift   = "shift"

    var displayName: String {
        switch self {
        case .command: return "⌘ Command"
        case .option:  return "⌥ Option"
        case .control: return "⌃ Control"
        case .shift:   return "⇧ Shift"
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option:  return "⌥"
        case .control: return "⌃"
        case .shift:   return "⇧"
        }
    }

    var flagMask: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option:  return .maskAlternate
        case .control: return .maskControl
        case .shift:   return .maskShift
        }
    }

    var otherMasks: [CGEventFlags] {
        switch self {
        case .command: return [.maskShift, .maskAlternate, .maskControl]
        case .option:  return [.maskShift, .maskCommand,   .maskControl]
        case .control: return [.maskShift, .maskAlternate, .maskCommand]
        case .shift:   return [.maskCommand, .maskAlternate, .maskControl]
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var triggerMode: TriggerMode {
        didSet { UserDefaults.standard.set(triggerMode.rawValue, forKey: "triggerMode") }
    }

    @Published var holdDelay: Double {
        didSet { UserDefaults.standard.set(holdDelay, forKey: "holdDelay") }
    }

    @Published var doublePressInterval: Double {
        didSet { UserDefaults.standard.set(doublePressInterval, forKey: "doublePressInterval") }
    }

    @Published var triggerKey: TriggerKey {
        didSet { UserDefaults.standard.set(triggerKey.rawValue, forKey: "triggerKey") }
    }

    @Published var clipboardHistoryLimit: Int {
        didSet {
            UserDefaults.standard.set(clipboardHistoryLimit, forKey: "clipboardHistoryLimit")
            NotificationCenter.default.post(name: .clipboardLimitChanged, object: nil)
        }
    }

    @Published var clipboardHotkey: ClipboardHotkey {
        didSet { clipboardHotkey.save(prefix: "clipboardHotkey") }
    }

    @Published var keepAwakeHotkey: ClipboardHotkey {
        didSet { keepAwakeHotkey.save(prefix: "keepAwakeHotkey") }
    }

    @Published var appSwitcherHotkey: ClipboardHotkey {
        didSet { appSwitcherHotkey.save(prefix: "appSwitcherHotkey") }
    }

    @Published var appSwitcherShowAll: Bool {
        didSet { UserDefaults.standard.set(appSwitcherShowAll, forKey: "appSwitcherShowAll") }
    }

    @Published var appSwitcherLayout: AppSwitcherLayout {
        didSet { UserDefaults.standard.set(appSwitcherLayout.rawValue, forKey: "appSwitcherLayout") }
    }

    @Published var clipboardPollingInterval: Double {
        didSet {
            UserDefaults.standard.set(clipboardPollingInterval, forKey: "clipboardPollingInterval")
            NotificationCenter.default.post(name: .clipboardPollingIntervalChanged, object: nil)
        }
    }

    @Published var autoSelectCopy: Bool {
        didSet {
            UserDefaults.standard.set(autoSelectCopy, forKey: "autoSelectCopy")
            NotificationCenter.default.post(name: .autoSelectCopyChanged, object: nil)
        }
    }

    @Published var autoSelectPollingInterval: Double {
        didSet {
            UserDefaults.standard.set(autoSelectPollingInterval, forKey: "autoSelectPollingInterval")
            NotificationCenter.default.post(name: .autoSelectPollingIntervalChanged, object: nil)
        }
    }

    @Published var autoSelectSimulateCmdC: Bool {
        didSet {
            UserDefaults.standard.set(autoSelectSimulateCmdC, forKey: "autoSelectSimulateCmdC")
            NotificationCenter.default.post(name: .autoSelectSimulateCmdCChanged, object: nil)
        }
    }

    @Published var clipboardCaptureEnabled: Bool {
        didSet {
            UserDefaults.standard.set(clipboardCaptureEnabled, forKey: "clipboardCaptureEnabled")
            NotificationCenter.default.post(name: .clipboardCaptureEnabledChanged, object: nil)
        }
    }

    @Published var liquidGlassEnabled: Bool {
        didSet { UserDefaults.standard.set(liquidGlassEnabled, forKey: "liquidGlassEnabled") }
    }

    @Published var liquidGlassIntensity: LiquidGlassIntensity {
        didSet { UserDefaults.standard.set(liquidGlassIntensity.rawValue, forKey: "liquidGlassIntensity") }
    }

    @Published var cuteMode: Bool {
        didSet { UserDefaults.standard.set(cuteMode, forKey: "cuteMode") }
    }

    // MARK: - Convert

    @Published var watchedFolders: [String] {
        didSet {
            UserDefaults.standard.set(watchedFolders, forKey: "watchedFolders")
            NotificationCenter.default.post(name: .watchedFoldersChanged, object: nil)
        }
    }

    @Published var conversionAutoApprove: Bool {
        didSet {
            UserDefaults.standard.set(conversionAutoApprove, forKey: "conversionAutoApprove")
        }
    }

    @Published var conversionNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(conversionNotificationsEnabled, forKey: "conversionNotificationsEnabled")
        }
    }

    @Published var conversionOutputMode: ConversionOutputMode {
        didSet {
            UserDefaults.standard.set(conversionOutputMode.rawValue, forKey: "conversionOutputMode")
        }
    }

    private init() {
        let modeRaw = UserDefaults.standard.string(forKey: "triggerMode") ?? ""
        triggerMode = TriggerMode(rawValue: modeRaw) ?? .hold

        let delay = UserDefaults.standard.double(forKey: "holdDelay")
        holdDelay = delay > 0 ? delay : 0.5

        let interval = UserDefaults.standard.double(forKey: "doublePressInterval")
        doublePressInterval = interval > 0 ? interval : 0.3

        let keyRaw = UserDefaults.standard.string(forKey: "triggerKey") ?? ""
        triggerKey = TriggerKey(rawValue: keyRaw) ?? .command

        let limit = UserDefaults.standard.integer(forKey: "clipboardHistoryLimit")
        clipboardHistoryLimit = limit > 0 ? limit : 20

        clipboardHotkey     = ClipboardHotkey.load(prefix: "clipboardHotkey",     fallback: .defaultClipboard)
        keepAwakeHotkey     = ClipboardHotkey.load(prefix: "keepAwakeHotkey",     fallback: .defaultKeepAwake)
        appSwitcherHotkey   = ClipboardHotkey.load(prefix: "appSwitcherHotkey",   fallback: .defaultAppSwitcher)
        appSwitcherShowAll  = UserDefaults.standard.object(forKey: "appSwitcherShowAll") as? Bool ?? true

        let layoutRaw = UserDefaults.standard.string(forKey: "appSwitcherLayout") ?? ""
        appSwitcherLayout = AppSwitcherLayout(rawValue: layoutRaw) ?? .radialRing

        let pollInterval = UserDefaults.standard.double(forKey: "clipboardPollingInterval")
        clipboardPollingInterval = pollInterval > 0 ? pollInterval : 0.5

        autoSelectCopy = UserDefaults.standard.bool(forKey: "autoSelectCopy")

        let selInterval = UserDefaults.standard.double(forKey: "autoSelectPollingInterval")
        autoSelectPollingInterval = selInterval > 0 ? selInterval : 5.0

        clipboardCaptureEnabled = UserDefaults.standard.object(forKey: "clipboardCaptureEnabled") as? Bool ?? true
        autoSelectSimulateCmdC  = UserDefaults.standard.object(forKey: "autoSelectSimulateCmdC")  as? Bool ?? true

        if let raw = UserDefaults.standard.object(forKey: "liquidGlassEnabled") as? Bool {
            liquidGlassEnabled = raw
        } else {
            liquidGlassEnabled = true
        }

        let igRaw = UserDefaults.standard.string(forKey: "liquidGlassIntensity") ?? ""
        liquidGlassIntensity = LiquidGlassIntensity(rawValue: igRaw) ?? .balanced

        cuteMode = UserDefaults.standard.object(forKey: "cuteMode") as? Bool ?? false

        watchedFolders = UserDefaults.standard.stringArray(forKey: "watchedFolders") ?? []
        conversionAutoApprove = UserDefaults.standard.object(forKey: "conversionAutoApprove") as? Bool ?? false
        conversionNotificationsEnabled = UserDefaults.standard.object(forKey: "conversionNotificationsEnabled") as? Bool ?? true

        let omRaw = UserDefaults.standard.string(forKey: "conversionOutputMode") ?? ""
        conversionOutputMode = ConversionOutputMode(rawValue: omRaw) ?? .keepBoth
    }
}

extension Notification.Name {
    static let clipboardLimitChanged           = Notification.Name("clipboardLimitChanged")
    static let clipboardPollingIntervalChanged  = Notification.Name("clipboardPollingIntervalChanged")
    static let autoSelectCopyChanged             = Notification.Name("autoSelectCopyChanged")
    static let autoSelectPollingIntervalChanged  = Notification.Name("autoSelectPollingIntervalChanged")
    static let clipboardCaptureEnabledChanged      = Notification.Name("clipboardCaptureEnabledChanged")
    static let autoSelectSimulateCmdCChanged       = Notification.Name("autoSelectSimulateCmdCChanged")
    static let keyMonitorPermissionFailed        = Notification.Name("keyMonitorPermissionFailed")
    static let clipboardEditingBegan             = Notification.Name("clipboardEditingBegan")
    static let watchedFoldersChanged             = Notification.Name("watchedFoldersChanged")
    static let conversionQueueChanged            = Notification.Name("conversionQueueChanged")
}

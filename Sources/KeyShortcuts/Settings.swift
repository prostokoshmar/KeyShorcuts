import Cocoa

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

        clipboardHotkey = ClipboardHotkey.load(prefix: "clipboardHotkey", fallback: .defaultClipboard)
        keepAwakeHotkey = ClipboardHotkey.load(prefix: "keepAwakeHotkey", fallback: .defaultKeepAwake)

        let pollInterval = UserDefaults.standard.double(forKey: "clipboardPollingInterval")
        clipboardPollingInterval = pollInterval > 0 ? pollInterval : 0.5

        autoSelectCopy = UserDefaults.standard.bool(forKey: "autoSelectCopy")

        let selInterval = UserDefaults.standard.double(forKey: "autoSelectPollingInterval")
        autoSelectPollingInterval = selInterval > 0 ? selInterval : 0.3
    }
}

extension Notification.Name {
    static let clipboardLimitChanged           = Notification.Name("clipboardLimitChanged")
    static let clipboardPollingIntervalChanged  = Notification.Name("clipboardPollingIntervalChanged")
    static let autoSelectCopyChanged             = Notification.Name("autoSelectCopyChanged")
    static let autoSelectPollingIntervalChanged  = Notification.Name("autoSelectPollingIntervalChanged")
}

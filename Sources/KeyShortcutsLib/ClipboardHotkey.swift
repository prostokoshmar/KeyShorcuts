import Cocoa

struct ClipboardHotkey: Equatable {
    var keyCode: Int
    var keyChar: String    // display character, e.g. "V"
    var modifiers: UInt64  // CGEventFlags.rawValue
    var doubleTap: Bool = false  // require two quick presses to fire

    static let defaultClipboard = ClipboardHotkey(
        keyCode: 9, keyChar: "V",
        modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue
    )
    static let defaultKeepAwake = ClipboardHotkey(
        keyCode: 40, keyChar: "K",
        modifiers: CGEventFlags.maskCommand.rawValue
    )
    static let defaultAppSwitcher = ClipboardHotkey(
        keyCode: 49, keyChar: "Space",
        modifiers: CGEventFlags.maskAlternate.rawValue
    )
    static let none = ClipboardHotkey(keyCode: 0, keyChar: "", modifiers: 0)

    var displayString: String {
        guard !keyChar.isEmpty else { return "—" }
        let flags = CGEventFlags(rawValue: modifiers)
        var s = ""
        if flags.contains(.maskControl)   { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift)     { s += "⇧" }
        if flags.contains(.maskCommand)   { s += "⌘" }
        return s + keyChar
    }

    var cgModifiers: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    /// Modifier flags that participate in hotkey matching.
    static let relevantModifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    /// True when a key event matches this hotkey (same key code and exact modifier set).
    /// An unset hotkey (empty `keyChar`) never matches.
    func matches(keyCode code: Int, flags: CGEventFlags) -> Bool {
        guard !keyChar.isEmpty else { return false }
        let mask = ClipboardHotkey.relevantModifierMask
        return code == keyCode && flags.intersection(mask) == cgModifiers.intersection(mask)
    }

    /// True when both hotkeys fire on the same physical key + modifier chord. Ignores
    /// `doubleTap`/`keyChar` because the key monitor still suppresses the event either way,
    /// so two features bound to the same key still collide. Unset hotkeys never conflict.
    func conflicts(with other: ClipboardHotkey) -> Bool {
        guard !keyChar.isEmpty, !other.keyChar.isEmpty else { return false }
        let mask = ClipboardHotkey.relevantModifierMask
        return keyCode == other.keyCode &&
            cgModifiers.intersection(mask) == other.cgModifiers.intersection(mask)
    }

    func save(prefix: String) {
        UserDefaults.standard.set(keyCode,    forKey: "\(prefix)Code")
        UserDefaults.standard.set(keyChar,    forKey: "\(prefix)Char")
        UserDefaults.standard.set(modifiers,  forKey: "\(prefix)Mods")
        UserDefaults.standard.set(doubleTap,  forKey: "\(prefix)DoubleTap")
    }

    static func load(prefix: String, fallback: ClipboardHotkey) -> ClipboardHotkey {
        let char = UserDefaults.standard.string(forKey: "\(prefix)Char") ?? ""
        guard !char.isEmpty else { return fallback }
        let code = UserDefaults.standard.integer(forKey: "\(prefix)Code")
        let mods = (UserDefaults.standard.object(forKey: "\(prefix)Mods") as? UInt64) ?? 0
        let dbl  = UserDefaults.standard.bool(forKey: "\(prefix)DoubleTap")
        return ClipboardHotkey(keyCode: code, keyChar: char, modifiers: mods, doubleTap: dbl)
    }
}

extension NSEvent.ModifierFlags {
    var toCGEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option)  { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift)   { flags.insert(.maskShift) }
        return flags
    }
}

import Cocoa

struct ClipboardHotkey: Equatable {
    var keyCode: Int
    var keyChar: String    // display character, e.g. "V"
    var modifiers: UInt64  // CGEventFlags.rawValue

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

    func save(prefix: String) {
        UserDefaults.standard.set(keyCode,    forKey: "\(prefix)Code")
        UserDefaults.standard.set(keyChar,    forKey: "\(prefix)Char")
        UserDefaults.standard.set(modifiers,  forKey: "\(prefix)Mods")
    }

    static func load(prefix: String, fallback: ClipboardHotkey) -> ClipboardHotkey {
        let char = UserDefaults.standard.string(forKey: "\(prefix)Char") ?? ""
        guard !char.isEmpty else { return fallback }
        let code = UserDefaults.standard.integer(forKey: "\(prefix)Code")
        let mods = (UserDefaults.standard.object(forKey: "\(prefix)Mods") as? UInt64) ?? 0
        return ClipboardHotkey(keyCode: code, keyChar: char, modifiers: mods)
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

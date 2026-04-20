import Cocoa

struct ShortcutItem: Identifiable {
    let id = UUID()
    let title: String
    let keys: String
    let category: String
}

class ShortcutReader {
    static let shared = ShortcutReader()

    func readShortcuts() -> [String: [ShortcutItem]] {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return [:] }
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXMenuBar" as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else { return [:] }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, "AXChildren" as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return [:] }

        var result: [String: [ShortcutItem]] = [:]
        // Skip first item (Apple menu)
        for topMenu in children.dropFirst() {
            let title = stringAttr(topMenu, "AXTitle") ?? ""
            var items: [ShortcutItem] = []
            collectShortcuts(from: topMenu, category: title, into: &items)
            if !items.isEmpty {
                result[title] = items
            }
        }
        return result
    }

    private func collectShortcuts(from element: AXUIElement, category: String, into items: inout [ShortcutItem]) {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            let title = stringAttr(child, "AXTitle") ?? ""
            let cmdChar = stringAttr(child, "AXMenuItemCmdChar") ?? ""

            if !title.isEmpty && title != "-" && !cmdChar.isEmpty {
                let mods = intAttr(child, "AXMenuItemCmdModifiers") ?? 0
                let keysStr = modifierSymbols(mods) + displayKey(cmdChar)
                items.append(ShortcutItem(title: title, keys: keysStr, category: category))
            }
            collectShortcuts(from: child, category: category, into: &items)
        }
    }

    private func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func intAttr(_ element: AXUIElement, _ attr: String) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? Int
    }

    private func modifierSymbols(_ mods: Int) -> String {
        // AXMenuItemCmdModifiers bitmask:
        // Bit 0 (1) = Shift, Bit 1 (2) = Option, Bit 2 (4) = Control, Bit 3 (8) = No Command
        var s = ""
        if mods & 4 != 0 { s += "⌃" }
        if mods & 2 != 0 { s += "⌥" }
        if mods & 1 != 0 { s += "⇧" }
        if mods & 8 == 0 { s += "⌘" }
        return s
    }

    private func displayKey(_ key: String) -> String {
        switch key {
        case "\u{F700}": return "↑"
        case "\u{F701}": return "↓"
        case "\u{F702}": return "←"
        case "\u{F703}": return "→"
        case "\u{F728}": return "⌦"
        case "\u{F729}": return "↖"
        case "\u{F72B}": return "↘"
        case "\u{F72C}": return "⇞"
        case "\u{F72D}": return "⇟"
        case "\u{08}":   return "⌫"
        case "\u{1B}":   return "⎋"
        case "\u{09}":   return "⇥"
        case "\u{0D}":   return "↩"
        default: return key.uppercased()
        }
    }
}

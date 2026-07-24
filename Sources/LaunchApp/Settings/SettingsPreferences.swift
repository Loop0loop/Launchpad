import AppKit
import Carbon.HIToolbox

struct GlobalHotKeyShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultShortcut = GlobalHotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_2),
        modifiers: UInt32(cmdKey),
        keyLabel: "2"
    )

    var displayName: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        guard event.keyCode != UInt16(kVK_Escape) else { return nil }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        // Plain global letter/number keys would steal normal typing in every app.
        guard carbonModifiers != 0, let keyLabel = Self.keyLabel(for: event) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers, keyLabel: keyLabel)
    }

    static func load() -> GlobalHotKeyShortcut {
        guard let data = UserDefaults.standard.data(forKey: LaunchConstants.Storage.globalHotKeyKey),
              let shortcut = try? JSONDecoder().decode(GlobalHotKeyShortcut.self, from: data),
              !shortcut.keyLabel.isEmpty,
              shortcut.modifiers != 0 else {
            return .defaultShortcut
        }
        return shortcut
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: LaunchConstants.Storage.globalHotKeyKey)
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default:
            guard let characters = event.charactersIgnoringModifiers?.uppercased(),
                  !characters.isEmpty,
                  characters.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
            return characters
        }
    }
}

/// Dock/app icon choice. Backed by the icon assets bundled in Resources.
enum AppIconOption: String, CaseIterable, Identifiable {
    case launch
    case launchBlack

    var id: String { rawValue }
    var title: String {
        switch self {
        case .launch: return "Launch"
        case .launchBlack: return "Launch black"
        }
    }
    private var resourceName: String {
        switch self {
        case .launch: return "Launch"
        case .launchBlack: return "Launch_black"
        }
    }

    func image() -> NSImage? {
        if let url = Self.resourceURL(named: resourceName, extension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return nil
    }

    static func load() -> AppIconOption {
        switch UserDefaults.standard.string(forKey: LaunchConstants.Storage.appIconKey) {
        case AppIconOption.launchBlack.rawValue, "mono":
            return .launchBlack
        default:
            return .launch
        }
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: LaunchConstants.Storage.appIconKey)
    }

    static func resourceURL(named name: String, extension fileExtension: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return url
        }

        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let devURL = cwdURL.appendingPathComponent("Resources").appendingPathComponent("\(name).\(fileExtension)")
        if FileManager.default.fileExists(atPath: devURL.path) { return devURL }

        let publicURL = cwdURL.appendingPathComponent("public").appendingPathComponent("\(name).\(fileExtension)")
        return FileManager.default.fileExists(atPath: publicURL.path) ? publicURL : nil
    }

}

/// Grid ordering mode. `.name` keeps the grid alphabetized; `.custom` is manual drag order.
enum SortMode: String, CaseIterable, Identifiable {
    case custom
    case name

    var id: String { rawValue }
    var title: String { self == .custom ? Localized.t("사용자 지정", "Custom") : Localized.t("이름순", "Name") }

    static func load() -> SortMode {
        SortMode(rawValue: UserDefaults.standard.string(forKey: LaunchConstants.Storage.sortModeKey) ?? "") ?? .custom
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: LaunchConstants.Storage.sortModeKey)
    }
}

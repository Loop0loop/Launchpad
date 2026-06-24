import AppKit

/// Dock/app icon choice. Backed by the icon assets bundled in Resources.
enum AppIconOption: String, CaseIterable, Identifiable {
    case color
    case mono
    case blue
    case rocket

    var id: String { rawValue }
    var title: String {
        switch self {
        case .color: return "Color"
        case .mono: return "Mono"
        case .blue: return "Blue"
        case .rocket: return "Rocket"
        }
    }
    private var resourceName: String {
        switch self {
        case .color: return "AppIconColor"
        case .mono: return "AppIconMono"
        case .blue: return "AppIconBlue"
        case .rocket: return "AppIconRocket"
        }
    }

    func image() -> NSImage? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    static func load() -> AppIconOption {
        AppIconOption(rawValue: UserDefaults.standard.string(forKey: LaunchConstants.Storage.appIconKey) ?? "") ?? .color
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: LaunchConstants.Storage.appIconKey)
    }
}

/// Grid ordering mode. `.name` keeps the grid alphabetized; `.custom` is manual drag order.
enum SortMode: String, CaseIterable, Identifiable {
    case custom
    case name

    var id: String { rawValue }
    var title: String { self == .custom ? "Custom" : "Name" }

    static func load() -> SortMode {
        SortMode(rawValue: UserDefaults.standard.string(forKey: LaunchConstants.Storage.sortModeKey) ?? "") ?? .custom
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: LaunchConstants.Storage.sortModeKey)
    }
}

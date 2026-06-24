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
        if let url = Self.resourceURL(named: resourceName, extension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        switch self {
        case .blue:
            return generatedIcon(background: NSColor.systemBlue, symbol: "circle.grid.3x3.fill")
        case .rocket:
            return generatedIcon(background: NSColor.darkGray, symbol: "rocket.fill")
        case .color, .mono:
            return nil
        }
    }

    static func load() -> AppIconOption {
        AppIconOption(rawValue: UserDefaults.standard.string(forKey: LaunchConstants.Storage.appIconKey) ?? "") ?? .color
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
        return FileManager.default.fileExists(atPath: devURL.path) ? devURL : nil
    }

    private func generatedIcon(background: NSColor, symbol: String) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        background.setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 42, dy: 42), xRadius: 92, yRadius: 92).fill()

        if let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            symbolImage.lockFocus()
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            symbolImage.unlockFocus()
            symbolImage.draw(in: rect.insetBy(dx: 150, dy: 150), from: .zero, operation: .sourceOver, fraction: 1)
        }
        return image
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

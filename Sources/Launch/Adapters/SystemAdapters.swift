import AppKit
import ApplicationServices
import LaunchCore
import ServiceManagement

enum AppSystemAdapter {
    static func launch(_ app: LaunchApp) {
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
    }

    static func showInFinder(_ app: LaunchApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    static func moveToTrash(_ app: LaunchApp) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: nil)
    }

    // ponytail: restarting Dock is the only reliable public way to add a persistent tile.
    static func addToDock(_ app: LaunchApp) {
        let tile = "<dict><key>tile-data</key><dict><key>file-data</key><dict>"
            + "<key>_CFURLString</key><string>\(app.path)</string>"
            + "<key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
        run("/usr/bin/defaults", ["write", "com.apple.dock", "persistent-apps", "-array-add", tile])
        run("/usr/bin/killall", ["Dock"])
    }

    private static func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
}

enum LoginItemAdapter {
    enum LoginItemError: LocalizedError {
        case unsupported

        var errorDescription: String? {
            "Requires macOS 13 or newer."
        }
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { throw LoginItemError.unsupported }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum AccessibilityAdapter {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

enum LayoutPersistenceAdapter {
    static func stringArray(forKey key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func set(_ value: [String], forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func data(forKey key: String) -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    static func set(_ value: Data, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

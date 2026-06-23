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

import Foundation
import ServiceManagement

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

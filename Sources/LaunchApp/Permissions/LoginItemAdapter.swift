import Foundation
import ServiceManagement

enum LoginItemAdapter {
    enum LoginItemError: LocalizedError {
        case requiresApproval
        case notEnabled

        var errorDescription: String? {
            switch self {
            case .requiresApproval:
                "Enable Launchpad in System Settings > General > Login Items."
            case .notEnabled:
                "Could not enable Launchpad at Login."
            }
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            switch SMAppService.mainApp.status {
            case .enabled:
                break
            case .requiresApproval:
                throw LoginItemError.requiresApproval
            default:
                throw LoginItemError.notEnabled
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

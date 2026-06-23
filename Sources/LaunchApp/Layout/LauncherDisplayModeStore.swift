import Foundation

enum LauncherDisplayModeStore {
    static func load() -> LauncherDisplayMode {
        guard let value = UserDefaults.standard.string(forKey: LaunchConstants.Storage.displayModeKey),
              let mode = LauncherDisplayMode(rawValue: value) else { return .paged }
        return mode
    }

    static func save(_ mode: LauncherDisplayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: LaunchConstants.Storage.displayModeKey)
    }
}

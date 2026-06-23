import Foundation

enum AppearanceStore {
    private static let backgroundTransparencyKey = "appearance.backgroundTransparency"
    private static let folderDimOpacityKey = "appearance.folderDimOpacity"

    static func load() -> AppearanceSettings {
        let defaults = AppearanceSettings.defaults
        let transparency = UserDefaults.standard.object(forKey: backgroundTransparencyKey) as? Double
            ?? defaults.backgroundTransparency
        let folderDim = UserDefaults.standard.object(forKey: folderDimOpacityKey) as? Double
            ?? defaults.folderDimOpacity
        return AppearanceSettings(
            backgroundTransparency: transparency,
            folderDimOpacity: folderDim
        ).clamped
    }

    static func save(_ settings: AppearanceSettings) {
        let clamped = settings.clamped
        UserDefaults.standard.set(clamped.backgroundTransparency, forKey: backgroundTransparencyKey)
        UserDefaults.standard.set(clamped.folderDimOpacity, forKey: folderDimOpacityKey)
    }
}

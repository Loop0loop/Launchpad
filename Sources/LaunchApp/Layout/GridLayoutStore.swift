import Foundation

enum GridLayoutStore {
    static func load() -> GridLayoutSettings {
        guard let data = LayoutPersistenceAdapter.data(forKey: LaunchConstants.Storage.gridLayoutKey),
              let decoded = try? JSONDecoder().decode(GridLayoutSettings.self, from: data),
              GridLayoutSettings.presets.contains(decoded) else { return .classic }
        return decoded
    }

    static func save(_ settings: GridLayoutSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        LayoutPersistenceAdapter.set(data, forKey: LaunchConstants.Storage.gridLayoutKey)
    }
}

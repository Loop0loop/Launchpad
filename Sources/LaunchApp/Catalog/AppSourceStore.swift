import Foundation

enum AppSourceStore {
    static func load() -> [String] {
        LayoutPersistenceAdapter.stringArray(forKey: LaunchConstants.Storage.appSourcesKey)
    }

    static func save(_ paths: [String]) {
        LayoutPersistenceAdapter.set(paths, forKey: LaunchConstants.Storage.appSourcesKey)
    }
}

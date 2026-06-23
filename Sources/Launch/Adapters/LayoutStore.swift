import Foundation
import LaunchCore

@MainActor
final class LayoutStore {
    private let layoutKey = LaunchConstants.Storage.layoutOrderKey
    private let foldersKey = LaunchConstants.Storage.foldersKey

    func loadOrder() -> [String] {
        LayoutPersistenceAdapter.stringArray(forKey: layoutKey)
    }

    func saveOrder(_ order: [String]) {
        LayoutPersistenceAdapter.set(order, forKey: layoutKey)
    }

    func loadFolders() -> [LaunchFolder] {
        guard let data = LayoutPersistenceAdapter.data(forKey: foldersKey),
              let decoded = try? JSONDecoder().decode([LaunchFolder].self, from: data) else { return [] }
        return decoded
    }

    func saveFolders(_ folders: [LaunchFolder]) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        LayoutPersistenceAdapter.set(data, forKey: foldersKey)
    }

    func cleanup(folders: [LaunchFolder], order: [String], validAppIDs: Set<String>) -> (folders: [LaunchFolder], order: [String]) {
        LayoutCleanup.cleanup(folders: folders, order: order, validAppIDs: validAppIDs)
    }
}

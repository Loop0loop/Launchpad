import Foundation
import LaunchCore

extension AppState {
    var visibleApps: [LaunchApp] {
        let shown = apps.filter { !hiddenAppIDs.contains($0.id) }
        guard !query.isEmpty else { return shown }
        return AppSearch.rankedApps(shown, matching: query)
    }

    func refreshApps() {
        apps = CatalogStore.scanApps(extraRoots: appSourcePaths)
        let cleanup = layoutStore.cleanup(folders: folders, order: order, validAppIDs: Set(apps.map(\.id)))
        folders = cleanup.folders
        openFolder = openFolder.flatMap { open in folders.first { $0.id == open.id } }
        order = cleanup.order
        layoutStore.saveFolders(folders)
        saveOrder()
        ensureSelection()
    }

    func appByID(_ id: String) -> LaunchApp? {
        apps.first { $0.id == id }
    }

    func requestAppSource() {
        chooseAppSource?()
    }

    func addAppSource(_ path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !appSourcePaths.contains(standardized) else { return }
        appSourcePaths.append(standardized)
        AppSourceStore.save(appSourcePaths)
        refreshApps()
    }

    func removeAppSource(_ path: String) {
        appSourcePaths.removeAll { $0 == path }
        AppSourceStore.save(appSourcePaths)
        refreshApps()
    }

    func importNativeLaunchpadLayout() {
        guard query.isEmpty else { return }
        let rootIDs = visibleItems.map(\.id)
        let rootIDSet = Set(rootIDs)
        let imported = NativeLaunchpadLayoutImporter.importOrder(apps: apps).filter(rootIDSet.contains)
        guard !imported.isEmpty else { return }
        saveOrder(imported + rootIDs.filter { !imported.contains($0) })
    }
}

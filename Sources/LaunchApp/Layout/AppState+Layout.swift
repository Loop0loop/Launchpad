import Foundation
import LaunchCore

enum LayoutStore {
    static func loadOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: LaunchConstants.Storage.layoutOrderKey) ?? []
    }

    static func saveOrder(_ order: [String]) {
        UserDefaults.standard.set(order, forKey: LaunchConstants.Storage.layoutOrderKey)
    }

    static func loadFolders() -> [LaunchFolder] {
        guard let data = UserDefaults.standard.data(forKey: LaunchConstants.Storage.foldersKey),
              let decoded = try? JSONDecoder().decode([LaunchFolder].self, from: data) else { return [] }
        return decoded
    }

    static func saveFolders(_ folders: [LaunchFolder]) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: LaunchConstants.Storage.foldersKey)
    }

    static func cleanup(folders: [LaunchFolder], order: [String], validAppIDs: Set<String>) -> (folders: [LaunchFolder], order: [String]) {
        LayoutCleanup.cleanup(folders: folders, order: order, validAppIDs: validAppIDs)
    }
}

extension AppState {
    var visibleItems: [LauncherItem] {
        if !query.isEmpty {
            return visibleApps.map(LauncherItem.app)
        }

        let folderedIDs = Set(folders.flatMap(\.appIDs))
        let rootApps = apps.filter { !folderedIDs.contains($0.id) && !hiddenAppIDs.contains($0.id) }
        let appItems = rootApps.map { LauncherItem.app($0) }
        let folderItems = folders.map { folder in
            LauncherItem.folder(folder, folder.appIDs.compactMap(appByID).filter { !hiddenAppIDs.contains($0.id) })
        }
        let allItems = appItems + folderItems
        let byID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        let orderedIDs = Set(ordered.map(\.id))
        return ordered + allItems.filter { !orderedIDs.contains($0.id) }
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(visibleItems.count) / Double(pageSize))))
    }

    var gridColumns: Int {
        gridLayout.columns
    }

    var pageItems: [LauncherItem] {
        items(forPage: currentPage)
    }

    fileprivate var pageSize: Int {
        gridLayout.pageSize
    }

    func items(forPage page: Int) -> [LauncherItem] {
        Array(visibleItems.dropFirst(page * pageSize).prefix(pageSize))
    }

    func move(_ id: String, before targetID: String) {
        guard query.isEmpty else { return }
        let nextOrder = LayoutOrder.move(id, before: targetID, in: visibleItems.map(\.id))
        saveOrder(nextOrder)
    }

    func createFolder(draggedID: String, targetID: String) {
        guard folders.allSatisfy({ !$0.appIDs.contains(draggedID) && !$0.appIDs.contains(targetID) }) else {
            LaunchLog.line("create folder blocked dragged=\(draggedID) target=\(targetID)")
            return
        }

        LaunchLog.line("create folder dragged=\(draggedID) target=\(targetID)")
        let result = FolderLayout.createFolder(
            id: "folder-\(UUID().uuidString)",
            draggedID: draggedID,
            targetID: targetID,
            folders: folders,
            order: visibleItems.map(\.id)
        )
        folders = result.folders
        LayoutStore.saveFolders(folders)
        saveOrder(result.order)
        openFolder = folders.last
    }

    func addApp(_ appID: String, toFolder folderID: String) {
        guard query.isEmpty else { return }
        guard folders.allSatisfy({ !$0.appIDs.contains(appID) }) else { return }
        LaunchLog.line("add app to folder app=\(appID) folder=\(folderID)")
        let result = FolderLayout.addApp(
            appID: appID,
            toFolderID: folderID,
            folders: folders,
            order: visibleItems.map(\.id)
        )
        folders = result.folders
        LayoutStore.saveFolders(folders)
        saveOrder(result.order)
        openFolder = folders.first { $0.id == folderID }
    }

    func removeApp(_ appID: String, fromFolder folderID: String) {
        let result = FolderLayout.removeApp(
            appID: appID,
            fromFolderID: folderID,
            folders: folders,
            order: visibleItems.map(\.id)
        )
        folders = result.folders
        LayoutStore.saveFolders(folders)
        saveOrder(result.order)
        openFolder = folders.first { $0.id == folderID }
    }

    func renameFolder(_ folderID: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].name = trimmed
        LayoutStore.saveFolders(folders)
        // Guard prevents FolderTitleField.onDisappear commit from re-opening the folder we just closed.
        if openFolder?.id == folderID {
            openFolder = folders[index]
        }
    }

    func apps(in folder: LaunchFolder) -> [LaunchApp] {
        folder.appIDs.compactMap(appByID)
    }

    /// Page to the item so a just-extracted app isn't stranded on another page.
    func revealItem(_ id: String) {
        guard let index = visibleItems.firstIndex(where: { $0.id == id }) else { return }
        let page = index / gridLayout.pageSize
        if page != currentPage { currentPage = page }
    }

    func itemName(_ id: String) -> String {
        appByID(id)?.name ?? id
    }

    func saveOrder(_ order: [String]? = nil) {
        self.order = order ?? visibleItems.map(\.id)
        LayoutStore.saveOrder(self.order)
    }

    func applyNameSort() {
        guard query.isEmpty else { return }
        let sortedRootIDs = visibleItems.map(\.id).sorted { lhs, rhs in
            itemName(lhs).localizedStandardCompare(itemName(rhs)) == .orderedAscending
        }
        saveOrder(sortedRootIDs)
    }

}

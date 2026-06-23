import Foundation
import LaunchCore

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
            return
        }

        let result = FolderLayout.createFolder(
            id: "folder-\(UUID().uuidString)",
            draggedID: draggedID,
            targetID: targetID,
            folders: folders,
            order: visibleItems.map(\.id)
        )
        folders = result.folders
        layoutStore.saveFolders(folders)
        saveOrder(result.order)
        openFolder = folders.last
    }

    func apps(in folder: LaunchFolder) -> [LaunchApp] {
        folder.appIDs.compactMap(appByID)
    }

    func itemName(_ id: String) -> String {
        appByID(id)?.name ?? id
    }

    func saveOrder(_ order: [String]? = nil) {
        self.order = order ?? visibleItems.map(\.id)
        layoutStore.saveOrder(self.order)
    }

    func applyNameSort() {
        guard query.isEmpty else { return }
        let sortedRootIDs = visibleItems.map(\.id).sorted { lhs, rhs in
            itemName(lhs).localizedStandardCompare(itemName(rhs)) == .orderedAscending
        }
        saveOrder(sortedRootIDs)
    }

    func dropApp(_ draggedID: String, on targetID: String) {
        guard query.isEmpty else { return }
        if draggedID == targetID { return }

        if appByID(targetID) != nil, appByID(draggedID) != nil {
            createFolder(draggedID: draggedID, targetID: targetID)
        } else {
            move(draggedID, before: targetID)
        }
    }
}

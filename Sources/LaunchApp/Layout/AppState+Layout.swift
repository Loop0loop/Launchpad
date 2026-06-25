import Foundation
import LaunchpadCore

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
        if let visibleItemsCache { return visibleItemsCache }

        let items: [LauncherItem]
        if !searchQuery.isEmpty {
            items = visibleApps.map(LauncherItem.app)
        } else {
            let folderedIDs = Set(folders.flatMap(\.appIDs))
            let appsByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
            let rootApps = apps.filter { !folderedIDs.contains($0.id) && !hiddenAppIDs.contains($0.id) }
            let appItems = rootApps.map { LauncherItem.app($0) }
            let folderItems = folders.map { folder in
                LauncherItem.folder(folder, folder.appIDs.compactMap { appsByID[$0] }.filter { !hiddenAppIDs.contains($0.id) })
            }
            let allItems = appItems + folderItems
            let byID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
            let ordered = order.compactMap { byID[$0] }
            let orderedIDs = Set(ordered.map(\.id))
            items = ordered + allItems.filter { !orderedIDs.contains($0.id) }
        }

        visibleItemsCache = items
        return items
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

    func addApp(_ appID: String, toFolder folderID: String, at index: Int? = nil) {
        guard query.isEmpty else { return }
        guard folders.allSatisfy({ !$0.appIDs.contains(appID) }) else { return }
        LaunchLog.line("add app to folder app=\(appID) folder=\(folderID) at=\(index.map(String.init) ?? "end")")
        let result = FolderLayout.addApp(
            appID: appID,
            toFolderID: folderID,
            folders: folders,
            order: visibleItems.map(\.id),
            at: index
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

    /// 폴더 내부 드래그 라이브 프리뷰: 재배열 중인 앱을 목표 슬롯으로 옮긴 순서.
    /// 메인 그리드의 dragRenderItems와 동일 규칙이라 프리뷰 == 드롭 결과.
    func folderRenderApps(_ folder: LaunchFolder) -> [LaunchApp] {
        let apps = apps(in: folder)
        guard let id = folderReorderingID, let index = folderDragInsertionIndex,
              apps.contains(where: { $0.id == id }) else { return apps }
        let ids = LayoutOrder.move(id, toIndex: index, in: apps.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// 슬롯이 바뀔 때만 갱신(슬롯 가로지름마다 reflow, 매 프레임 아님).
    func updateFolderReorder(_ appID: String, toIndex index: Int) {
        if folderReorderingID != appID { folderReorderingID = appID }
        if folderDragInsertionIndex != index { folderDragInsertionIndex = index }
    }

    func endFolderReorder() {
        folderReorderingID = nil
        folderDragInsertionIndex = nil
    }

    /// Reorder an app within its folder to a target slot. Called once on drop, so it
    /// persists immediately (no transient mid-drag writes).
    func reorderAppInFolder(_ appID: String, toIndex index: Int, folderID: String) {
        let nextFolders = FolderLayout.reorderApp(appID: appID, inFolderID: folderID, folders: folders, toIndex: index)
        guard nextFolders != folders else { return }
        LaunchLog.line("folder reorder app=\(appID) -> index=\(index) folder=\(folderID)")
        folders = nextFolders
        LayoutStore.saveFolders(folders)
        if openFolder?.id == folderID {
            openFolder = folders.first { $0.id == folderID }
        }
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

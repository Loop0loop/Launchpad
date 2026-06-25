public struct LaunchFolder: Codable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var appIDs: [String]

    public init(id: String, name: String, appIDs: [String]) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}

public enum FolderLayout {
    public static func createFolder(
        id: String,
        draggedID: String,
        targetID: String,
        folders: [LaunchFolder],
        order: [String]
    ) -> (folders: [LaunchFolder], order: [String]) {
        guard draggedID != targetID else { return (folders, order) }

        let folder = LaunchFolder(id: id, name: "Folder", appIDs: [targetID, draggedID])
        let draggedIndex = order.firstIndex(of: draggedID) ?? 0
        let targetIndex = order.firstIndex(of: targetID) ?? 0
        var nextOrder = order.filter { $0 != draggedID && $0 != targetID }
        nextOrder.insert(id, at: min(draggedIndex, targetIndex, nextOrder.count))
        return (folders + [folder], nextOrder)
    }

    public static func addApp(
        appID: String,
        toFolderID folderID: String,
        folders: [LaunchFolder],
        order: [String],
        at insertIndex: Int? = nil
    ) -> (folders: [LaunchFolder], order: [String]) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }),
              !folders[index].appIDs.contains(appID) else { return (folders, order) }

        var nextFolders = folders
        if let insertIndex {
            let clamped = min(max(insertIndex, 0), nextFolders[index].appIDs.count)
            nextFolders[index].appIDs.insert(appID, at: clamped)
        } else {
            nextFolders[index].appIDs.append(appID)
        }
        return (nextFolders, order.filter { $0 != appID })
    }

    public static func removeApp(
        appID: String,
        fromFolderID folderID: String,
        folders: [LaunchFolder],
        order: [String]
    ) -> (folders: [LaunchFolder], order: [String]) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }),
              folders[index].appIDs.contains(appID) else { return (folders, order) }

        var nextFolders = folders
        var folder = nextFolders[index]
        folder.appIDs.removeAll { $0 == appID }

        var nextOrder = order.filter { $0 != appID }
        let folderIndex = nextOrder.firstIndex(of: folderID) ?? nextOrder.count

        if folder.appIDs.count <= 1 {
            nextFolders.remove(at: index)
            nextOrder.removeAll { $0 == folderID || folder.appIDs.contains($0) }
            nextOrder.insert(contentsOf: folder.appIDs + [appID], at: min(folderIndex, nextOrder.count))
        } else {
            nextFolders[index] = folder
            nextOrder.insert(appID, at: min(folderIndex + 1, nextOrder.count))
        }

        return (nextFolders, nextOrder)
    }

    public static func reorderApp(
        appID: String,
        inFolderID folderID: String,
        folders: [LaunchFolder],
        toIndex index: Int
    ) -> [LaunchFolder] {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return folders }
        var nextFolders = folders
        var ids = nextFolders[folderIndex].appIDs
        guard let from = ids.firstIndex(of: appID) else { return folders }
        ids.remove(at: from)
        ids.insert(appID, at: min(max(index, 0), ids.count))
        nextFolders[folderIndex].appIDs = ids
        return nextFolders
    }
}

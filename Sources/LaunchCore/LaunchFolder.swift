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
}

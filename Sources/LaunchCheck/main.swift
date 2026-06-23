import Foundation
import LaunchCore

let url = URL(fileURLWithPath: "/tmp/Fake App.app")
assert(AppCatalog.displayName(for: url) == "Fake App")

let missing = URL(fileURLWithPath: "/tmp/launch-missing-\(UUID().uuidString)")
assert(AppCatalog.scan(roots: [missing]).isEmpty)

let apps = [
    LaunchApp(id: "a", name: "A", path: "/A.app"),
    LaunchApp(id: "b", name: "B", path: "/B.app"),
    LaunchApp(id: "c", name: "C", path: "/C.app")
]
assert(LayoutOrder.apply(["c", "a"], to: apps).map(\.id) == ["c", "a", "b"])
assert(LayoutOrder.move("c", before: "b", in: ["a", "b", "c"]) == ["a", "c", "b"])

let folderResult = FolderLayout.createFolder(
    id: "folder-1",
    draggedID: "c",
    targetID: "a",
    folders: [],
    order: ["a", "b", "c"]
)
assert(folderResult.folders == [LaunchFolder(id: "folder-1", name: "Folder", appIDs: ["a", "c"])])
assert(folderResult.order == ["folder-1", "b"])

let reorderedFolderResult = FolderLayout.createFolder(
    id: "folder-2",
    draggedID: "c",
    targetID: "a",
    folders: [],
    order: ["c", "a", "b"]
)
assert(reorderedFolderResult.order == ["folder-2", "b"])

print("LaunchCheck OK")

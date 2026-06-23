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

assert(TrackpadIntent.pinch(magnification: -0.1) == .open)
assert(TrackpadIntent.pinch(magnification: 0.1) == .close)
assert(TrackpadIntent.pinch(magnification: 0.01) == nil)
assert(TrackpadIntent.horizontalSwipe(deltaX: -1) == .nextPage)
assert(TrackpadIntent.horizontalSwipe(deltaX: 1) == .previousPage)
assert(TrackpadIntent.horizontalScroll(deltaX: -20) == .nextPage)
assert(TrackpadIntent.horizontalScroll(deltaX: 20) == .previousPage)
assert(TrackpadIntent.horizontalScroll(deltaX: 1) == nil)
assert(TrackpadIntent.isRecentFourFingerFrame(eventTime: 10.2, lastFourFingerTime: 10.0))
assert(!TrackpadIntent.isRecentFourFingerFrame(eventTime: 10.6, lastFourFingerTime: 10.0))
assert(!TrackpadIntent.isRecentFourFingerFrame(eventTime: 10.0, lastFourFingerTime: nil))

print("LaunchCheck OK")

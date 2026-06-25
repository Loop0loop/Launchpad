import Foundation
import LaunchpadCore

let url = URL(fileURLWithPath: "/tmp/Fake App.app")
assert(AppCatalog.displayName(for: url) == "Fake App")

let localizedApp = FileManager.default.temporaryDirectory
    .appendingPathComponent("LaunchpadCheck-\(UUID().uuidString)")
    .appendingPathComponent("Localized App.app")
let resources = localizedApp.appendingPathComponent("Contents/Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
NSDictionary(dictionary: ["CFBundleName": "Localized App"]).write(
    to: localizedApp.appendingPathComponent("Contents/Info.plist"),
    atomically: true
)
NSDictionary(dictionary: ["ko": ["CFBundleName": "현지화 앱"]]).write(
    to: resources.appendingPathComponent("InfoPlist.loctable"),
    atomically: true
)
assert(AppCatalog.displayName(for: localizedApp, languageCode: "ko-KR") == "현지화 앱")
if Locale.preferredLanguages.first?.hasPrefix("ko") == true {
    assert(AppCatalog.displayName(for: localizedApp) == "현지화 앱")
}

let missing = URL(fileURLWithPath: "/tmp/launch-missing-\(UUID().uuidString)")
assert(AppCatalog.scan(roots: [missing]).isEmpty)

let apps = [
    LaunchApp(id: "a", name: "A", path: "/A.app"),
    LaunchApp(id: "b", name: "B", path: "/B.app"),
    LaunchApp(id: "c", name: "C", path: "/C.app")
]
let encodedApps = try JSONEncoder().encode(apps)
let decodedApps = try JSONDecoder().decode([LaunchApp].self, from: encodedApps)
assert(decodedApps == apps)
let searchApps = [
    LaunchApp(id: "com.example.notes", name: "Notes", path: "/Applications/Notes.app"),
    LaunchApp(id: "com.example.cafe", name: "Café", path: "/Applications/Cafe.app"),
    LaunchApp(id: "com.example.camera", name: "Camera", path: "/Applications/Camera.app")
]
assert(LayoutOrder.apply(["c", "a"], to: apps).map(\.id) == ["c", "a", "b"])
assert(LayoutOrder.move("c", before: "b", in: ["a", "b", "c"]) == ["a", "c", "b"])
assert(AppSearch.rankedApps(searchApps, matching: "ca").map(\.name) == ["Café", "Camera"])
assert(AppSearch.rankedApps(searchApps, matching: "notes").map(\.name) == ["Notes"])
assert(AppSearch.rankedApps(searchApps, matching: "example.camera").map(\.name) == ["Camera"])

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

let addToFolderResult = FolderLayout.addApp(
    appID: "b",
    toFolderID: "folder",
    folders: [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a", "c"])],
    order: ["folder", "b"]
)
assert(addToFolderResult.folders == [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a", "c", "b"])])
assert(addToFolderResult.order == ["folder"])

let removeFromFolderResult = FolderLayout.removeApp(
    appID: "b",
    fromFolderID: "folder",
    folders: [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a", "b", "c"])],
    order: ["folder"]
)
assert(removeFromFolderResult.folders == [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a", "c"])])
assert(removeFromFolderResult.order == ["folder", "b"])

let dissolveFolderResult = FolderLayout.removeApp(
    appID: "b",
    fromFolderID: "folder",
    folders: [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a", "b"])],
    order: ["folder", "c"]
)
assert(dissolveFolderResult.folders.isEmpty)
assert(dissolveFolderResult.order == ["a", "b", "c"])

let cleanup = LayoutCleanup.cleanup(
    folders: [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a", "missing"])],
    order: ["folder", "missing", "a"],
    validAppIDs: ["a"]
)
assert(cleanup.folders == [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a"])])
assert(cleanup.order == ["folder", "a"])

assert(TrackpadIntent.pinch(magnification: -0.1) == .open)
assert(TrackpadIntent.pinch(magnification: 0.1) == .close)
assert(TrackpadIntent.pinch(magnification: 0.01) == nil)
assert(TrackpadIntent.horizontalSwipe(deltaX: -1) == .nextPage)
assert(TrackpadIntent.horizontalSwipe(deltaX: 1) == .previousPage)
assert(TrackpadIntent.horizontalScroll(deltaX: -20) == .nextPage)
assert(TrackpadIntent.horizontalScroll(deltaX: 20) == .previousPage)
assert(TrackpadIntent.horizontalScroll(deltaX: 1) == nil)
assert(TrackpadIntent.shouldAcceptScrollIntent(eventTime: 1.0, lastIntentTime: 0.0))
assert(!TrackpadIntent.shouldAcceptScrollIntent(eventTime: 1.1, lastIntentTime: 1.0))
assert(TrackpadIntent.pinchRadius(ratio: 0.89) == .open)
assert(TrackpadIntent.pinchRadius(ratio: 1.11) == .close)
assert(TrackpadIntent.pinchRadius(ratio: 1.0) == nil)

print("LaunchpadCheck OK")

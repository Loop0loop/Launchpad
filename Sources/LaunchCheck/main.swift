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

let scanRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("LaunchpadCheck-\(UUID().uuidString)")
let scanApp = scanRoot.appendingPathComponent("Scanned App.app")
try FileManager.default.createDirectory(
    at: scanApp.appendingPathComponent("Contents"),
    withIntermediateDirectories: true
)
NSDictionary(dictionary: [
    "CFBundleIdentifier": "com.example.scanned",
    "CFBundleName": "Scanned Name"
]).write(to: scanApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
let scannedApps = AppCatalog.scan(roots: [scanRoot], languageCode: "en")
assert(scannedApps.count == 1)
assert(scannedApps[0].id == "com.example.scanned")
assert(scannedApps[0].name == "Scanned Name")
assert(scannedApps[0].path.hasSuffix("/Scanned App.app"))
assert(scannedApps[0].existingBundleURL?.lastPathComponent == "Scanned App.app")
assert(LaunchApp(id: "bad", name: "Bad", path: scanRoot.appendingPathComponent("Bad.app").path).existingBundleURL == nil)
assert(AppCatalog.scan(roots: [scanRoot], isCancelled: { true }).isEmpty)

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
assert(LayoutOrder.move("a", toIndex: 2, in: ["a", "b", "c"]) == ["b", "c", "a"])
assert(LayoutOrder.move("c", toIndex: 0, in: ["a", "b", "c"]) == ["c", "a", "b"])
assert(LayoutOrder.move("b", toIndex: 99, in: ["a", "b", "c"]) == ["a", "c", "b"])
assert(AppSearch.rankedApps(searchApps, matching: "ca").map(\.name) == ["Café", "Camera"])
assert(AppSearch.rankedApps(searchApps, matching: "notes").map(\.name) == ["Notes"])
assert(AppSearch.rankedApps(searchApps, matching: "example.camera").map(\.name) == ["Camera"])
assert(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: "abc").isConfigured)
assert(!UpdateConfiguration(feedURL: "http://example.com/appcast.xml", publicKey: "abc").isConfigured)
assert(!UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY").isConfigured)
assert(!UpdateConfiguration(feedURL: "not a url", publicKey: "abc").isConfigured)
assert(!UpdateConfiguration(feedURL: nil, publicKey: "abc").isConfigured)
assert(!UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: "").isConfigured)

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

let addManyToFolderResult = ["b", "d", "e"].reduce(
    (folders: [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a", "c"])], order: ["folder", "b", "d", "e"])
) { state, appID in
    FolderLayout.addApp(appID: appID, toFolderID: "folder", folders: state.folders, order: state.order)
}
assert(addManyToFolderResult.folders == [LaunchFolder(id: "folder", name: "Folder", appIDs: ["a", "c", "b", "d", "e"])])
assert(addManyToFolderResult.order == ["folder"])

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
assert(TrackpadIntent.pageSwipe(offset: -130, velocity: 0, pageWidth: 800) == .nextPage)
assert(TrackpadIntent.pageSwipe(offset: 130, velocity: 0, pageWidth: 800) == .previousPage)
assert(TrackpadIntent.pageSwipe(offset: -20, velocity: -950, pageWidth: 800) == .nextPage)
assert(TrackpadIntent.pageSwipe(offset: 20, velocity: 200, pageWidth: 800) == nil)
assert(TrackpadIntent.shouldAcceptScrollIntent(eventTime: 1.0, lastIntentTime: 0.0))
assert(!TrackpadIntent.shouldAcceptScrollIntent(eventTime: 1.1, lastIntentTime: 1.0))
assert(TrackpadIntent.pinchRadius(ratio: 0.89) == .open)
assert(TrackpadIntent.pinchRadius(ratio: 1.11) == .close)
assert(TrackpadIntent.pinchRadius(ratio: 1.0) == nil)

let fingerTouches = [
    TrackpadTouchSample(id: 3, x: 0.1, y: 0.1, majorAxis: 0.12, minorAxis: 0.08),
    TrackpadTouchSample(id: 1, x: 0.2, y: 0.1, majorAxis: 0.13, minorAxis: 0.08),
    TrackpadTouchSample(id: 4, x: 0.1, y: 0.2, majorAxis: 0.12, minorAxis: 0.09),
    TrackpadTouchSample(id: 2, x: 0.2, y: 0.2, majorAxis: 0.13, minorAxis: 0.09)
]
assert(TrackpadContactQuality.qualifiedPinchTouches(fingerTouches)?.map(\.id) == [1, 2, 3, 4])
assert(TrackpadContactQuality.qualifiedPinchTouches(fingerTouches + [
    TrackpadTouchSample(id: 5, x: 0.3, y: 0.2, majorAxis: 0.11, minorAxis: 0.08)
]) != nil)
assert(TrackpadContactQuality.qualifiedPinchTouches(fingerTouches + [
    TrackpadTouchSample(id: 5, x: 0.3, y: 0.2),
    TrackpadTouchSample(id: 6, x: 0.4, y: 0.2)
]) == nil)
assert(TrackpadContactQuality.qualifiedPinchTouches([
    TrackpadTouchSample(id: 1, x: 0.1, y: 0.1, majorAxis: 0.45, minorAxis: 0.28),
    TrackpadTouchSample(id: 2, x: 0.2, y: 0.1, majorAxis: 0.44, minorAxis: 0.27),
    TrackpadTouchSample(id: 3, x: 0.1, y: 0.2, majorAxis: 0.46, minorAxis: 0.29),
    TrackpadTouchSample(id: 4, x: 0.2, y: 0.2, majorAxis: 0.43, minorAxis: 0.26)
]) == nil)

var pinchSession = TrackpadGestureSession()
assert(pinchSession.updatePinch(radius: 1.0, timestamp: 1.0) == nil)
assert(pinchSession.updatePinch(radius: 0.89, timestamp: 1.01) == nil)
assert(pinchSession.updatePinch(radius: 0.88, timestamp: 1.02) == .open)
assert(pinchSession.updatePinch(radius: 0.80, timestamp: 1.03) == nil)
assert(pinchSession.updatePinch(radius: nil, timestamp: 1.04) == nil)
assert(pinchSession.updatePinch(radius: 1.0, timestamp: 2.0) == nil)
assert(pinchSession.updatePinch(radius: 1.11, timestamp: 2.01) == nil)
assert(pinchSession.updatePinch(radius: 1.12, timestamp: 2.02) == .close)

var largePinchSession = TrackpadGestureSession()
assert(largePinchSession.updatePinch(radius: 1.0, timestamp: 3.0) == nil)
assert(largePinchSession.updatePinch(radius: 0.78, timestamp: 3.01) == .open)
assert(largePinchSession.updatePinch(radius: 0.70, timestamp: 3.02) == nil)
assert(largePinchSession.updatePinch(radius: 1.11, timestamp: 3.03) == nil)
assert(largePinchSession.updatePinch(radius: 1.12, timestamp: 3.04) == .close)

var scrollSession = TrackpadGestureSession()
assert(scrollSession.updateHorizontalScroll(deltaX: -10, deltaY: 3) == nil)
assert(scrollSession.updateHorizontalScroll(deltaX: -12, deltaY: 2) == nil)
assert(scrollSession.updateHorizontalScroll(deltaX: -10, deltaY: 1) == .nextPage)
assert(scrollSession.updateHorizontalScroll(deltaX: -40, deltaY: 1) == nil)
assert(scrollSession.updateHorizontalScroll(deltaX: 0, deltaY: 0, ended: true) == nil)
assert(scrollSession.updateHorizontalScroll(deltaX: 35, deltaY: 2) == .previousPage)
assert(scrollSession.updateHorizontalScroll(deltaX: 35, deltaY: 35, ended: true) == nil)

// Folder reorder: map a drop point to a cell slot. 4 cols, 184x164 pitch.
assert(GridGeometry.cellIndex(x: 10, y: 10, columns: 4, colPitch: 184, rowPitch: 164, count: 8) == 0)
assert(GridGeometry.cellIndex(x: 200, y: 10, columns: 4, colPitch: 184, rowPitch: 164, count: 8) == 1)
assert(GridGeometry.cellIndex(x: 10, y: 200, columns: 4, colPitch: 184, rowPitch: 164, count: 8) == 4)
assert(GridGeometry.cellIndex(x: 9999, y: 9999, columns: 4, colPitch: 184, rowPitch: 164, count: 8) == 7)
assert(GridGeometry.cellIndex(x: -5, y: -5, columns: 4, colPitch: 184, rowPitch: 164, count: 8) == 0)
assert(GridGeometry.cellIndex(x: 10, y: 10, columns: 4, colPitch: 184, rowPitch: 164, count: 0) == 0)

print("LaunchpadCheck OK")

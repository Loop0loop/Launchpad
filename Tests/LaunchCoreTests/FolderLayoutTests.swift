import XCTest
@testable import LaunchpadCore

final class FolderLayoutTests: XCTestCase {
    private func folder() -> LaunchFolder {
        LaunchFolder(id: "f1", name: "Folder", appIDs: ["a", "b"])
    }

    func testAddAppDefaultAppends() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"])
        XCTAssertEqual(r.folders[0].appIDs, ["a", "b", "c"])
    }

    func testAddAppAtFront() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"], at: 0)
        XCTAssertEqual(r.folders[0].appIDs, ["c", "a", "b"])
    }

    func testAddAppAtMiddle() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"], at: 1)
        XCTAssertEqual(r.folders[0].appIDs, ["a", "c", "b"])
    }

    func testAddAppIndexClampedToCount() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"], at: 99)
        XCTAssertEqual(r.folders[0].appIDs, ["a", "b", "c"])
    }

    func testAddAppNegativeIndexClampedToZero() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"], at: -5)
        XCTAssertEqual(r.folders[0].appIDs, ["c", "a", "b"])
    }

    func testAddAppDuplicateIsNoOp() {
        let r = FolderLayout.addApp(appID: "a", toFolderID: "f1", folders: [folder()], order: ["f1"], at: 0)
        XCTAssertEqual(r.folders[0].appIDs, ["a", "b"])
    }
}

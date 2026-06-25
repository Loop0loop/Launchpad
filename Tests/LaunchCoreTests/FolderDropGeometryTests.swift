import XCTest
@testable import LaunchpadCore

final class FolderDropGeometryTests: XCTestCase {
    // 폴더 그리드: global (100,100), 400x200, 4열, colPitch 100, rowPitch 100, 6칸
    private func slot(px: Double, py: Double) -> Int? {
        FolderDropGeometry.slot(
            pointerX: px, pointerY: py,
            launcherGridOriginX: 0, launcherGridOriginY: 0,
            folderGridX: 100, folderGridY: 100,
            folderGridWidth: 400, folderGridHeight: 200,
            columns: 4, colPitch: 100, rowPitch: 100, count: 6
        )
    }

    func testFirstCell() {
        XCTAssertEqual(slot(px: 110, py: 110), 0)
    }

    func testSecondCellSameRow() {
        XCTAssertEqual(slot(px: 210, py: 110), 1)
    }

    func testSecondRowFirstCell() {
        XCTAssertEqual(slot(px: 110, py: 210), 4)
    }

    func testClampedToCount() {
        // 마지막 행/열 영역 → count-1 로 clamp
        XCTAssertEqual(slot(px: 490, py: 290), 5)
    }

    func testOutsideLeftReturnsNil() {
        XCTAssertNil(slot(px: 50, py: 110))
    }

    func testOutsideBelowReturnsNil() {
        XCTAssertNil(slot(px: 110, py: 350))
    }

    func testLauncherOriginOffsetApplied() {
        // 그리드 origin이 (0,50)이면 포인터 y는 50만큼 위로 보정됨
        let s = FolderDropGeometry.slot(
            pointerX: 110, pointerY: 60,
            launcherGridOriginX: 0, launcherGridOriginY: 50,
            folderGridX: 100, folderGridY: 100,
            folderGridWidth: 400, folderGridHeight: 200,
            columns: 4, colPitch: 100, rowPitch: 100, count: 6
        )
        XCTAssertEqual(s, 0) // global y = 50+60=110 → folder-local 10 → row 0
    }
}

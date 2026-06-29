import XCTest
@testable import LaunchpadCore

final class GridDropGeometryTests: XCTestCase {
    func testUsesIconCenterForIconHitTesting() {
        let result = GridDropGeometry.resolve(
            itemIDs: ["a"],
            page: 0,
            pageSize: 35,
            pointerX: 64,
            pointerY: 46,
            columns: 7,
            rows: 5,
            horizontalPadding: 0,
            columnWidth: 128,
            rowHeight: 170,
            iconSize: 80,
            labelHeight: 34,
            iconLabelSpacing: 8,
            dragMergeZoneScale: 0.4,
            dragFolderMergeZoneScale: 0.52,
            dragInsertionBandRatio: 0.18,
            dragHoldZoneScale: 0.8,
            folderIDs: []
        )

        XCTAssertEqual(result.onIconID, "a")
        XCTAssertNil(result.targetIndex)
    }

    func testIconHitIsCenteredOnIconImageNotLabelBlock() {
        let result = GridDropGeometry.resolve(
            itemIDs: ["a"],
            page: 0,
            pageSize: 35,
            pointerX: 64,
            pointerY: 86,
            columns: 7,
            rows: 5,
            horizontalPadding: 0,
            columnWidth: 128,
            rowHeight: 170,
            iconSize: 80,
            labelHeight: 34,
            iconLabelSpacing: 8,
            dragMergeZoneScale: 0.4,
            dragFolderMergeZoneScale: 0.52,
            dragInsertionBandRatio: 0.18,
            dragHoldZoneScale: 0.8,
            folderIDs: []
        )

        XCTAssertNil(result.onIconID)
    }

    func testResolvesAgainstPreviewOrder() {
        let result = GridDropGeometry.resolve(
            itemIDs: ["b", "a", "c"],
            page: 0,
            pageSize: 35,
            pointerX: 128 + 64,
            pointerY: 46,
            columns: 7,
            rows: 5,
            horizontalPadding: 0,
            columnWidth: 128,
            rowHeight: 170,
            iconSize: 80,
            labelHeight: 34,
            iconLabelSpacing: 8,
            dragMergeZoneScale: 0.4,
            dragFolderMergeZoneScale: 0.52,
            dragInsertionBandRatio: 0.18,
            dragHoldZoneScale: 0.8,
            folderIDs: []
        )

        XCTAssertEqual(result.onIconID, "a")
    }

    func testSecondRowUsesVisualGridPitch() {
        let result = GridDropGeometry.resolve(
            itemIDs: ["a", "b", "c", "d"],
            page: 0,
            pageSize: 4,
            pointerX: 64,
            pointerY: 122 + 40,
            columns: 2,
            rows: 2,
            horizontalPadding: 0,
            columnWidth: 128,
            rowHeight: 122,
            iconSize: 80,
            labelHeight: 34,
            iconLabelSpacing: 8,
            dragMergeZoneScale: 0.4,
            dragFolderMergeZoneScale: 0.52,
            dragInsertionBandRatio: 0.18,
            dragHoldZoneScale: 0.8,
            folderIDs: []
        )

        XCTAssertEqual(result.onIconID, "c")
    }
}

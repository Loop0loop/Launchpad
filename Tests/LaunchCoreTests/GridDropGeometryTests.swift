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
        XCTAssertEqual(result.targetIndex, 0)
    }

    func testIconCenterKeepsReorderPreviewUntilMergeDwellConfirms() {
        let result = GridDropGeometry.resolve(
            itemIDs: ["a", "b", "c"],
            page: 0,
            pageSize: 35,
            pointerX: 128 + 64,
            pointerY: 40,
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
            dragInsertionBandRatio: 0.42,
            dragHoldZoneScale: 0.8,
            folderIDs: []
        )

        XCTAssertEqual(result.onIconID, "b")
        XCTAssertEqual(result.targetIndex, 1)
        XCTAssertEqual(LayoutOrder.move("c", toIndex: result.targetIndex!, in: ["a", "b", "c"]), ["a", "c", "b"])
    }

    func testCenterAndLowerDropResolveToSameReorderSlot() {
        func resolve(y: Double) -> GridDropTarget {
            GridDropGeometry.resolve(
                itemIDs: ["a", "b", "c"],
                page: 0,
                pageSize: 35,
                pointerX: 128 + 64,
                pointerY: y,
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
                dragInsertionBandRatio: 0.42,
                dragHoldZoneScale: 0.8,
                folderIDs: []
            )
        }

        XCTAssertEqual(resolve(y: 40).targetIndex, 1)
        XCTAssertEqual(resolve(y: 110).targetIndex, 1)
    }

    func testIconCenterReordersAcrossRows() {
        let order = ["a", "b", "c", "d", "e", "f"]
        let result = GridDropGeometry.resolve(
            itemIDs: order,
            page: 0,
            pageSize: 6,
            pointerX: 128 + 64,
            pointerY: 170 + 40,
            columns: 3,
            rows: 2,
            horizontalPadding: 0,
            columnWidth: 128,
            rowHeight: 170,
            iconSize: 80,
            labelHeight: 34,
            iconLabelSpacing: 8,
            dragMergeZoneScale: 0.4,
            dragFolderMergeZoneScale: 0.52,
            dragInsertionBandRatio: 0.42,
            dragHoldZoneScale: 0.8,
            folderIDs: []
        )

        XCTAssertEqual(result.onIconID, "e")
        XCTAssertEqual(result.targetIndex, 4)
        XCTAssertEqual(LayoutOrder.move("c", toIndex: result.targetIndex!, in: order), ["a", "b", "d", "e", "c", "f"])
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

    func testIconRowBetweenIconsCreatesInsertionGap() {
        let result = GridDropGeometry.resolve(
            itemIDs: ["a", "b"],
            page: 0,
            pageSize: 35,
            pointerX: 100,
            pointerY: 40,
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
            dragInsertionBandRatio: 0.42,
            dragHoldZoneScale: 0.8,
            folderIDs: []
        )

        XCTAssertNil(result.onIconID)
        XCTAssertEqual(result.targetIndex, 1)
    }
}

import XCTest
@testable import LaunchpadCore

final class TrackpadIntentTests: XCTestCase {
    func testPageSwipeCommitsByDistance() {
        XCTAssertEqual(TrackpadIntent.pageSwipe(offset: -130, velocity: 0, pageWidth: 800), .nextPage)
        XCTAssertEqual(TrackpadIntent.pageSwipe(offset: 130, velocity: 0, pageWidth: 800), .previousPage)
    }

    func testPageSwipeCommitsByVelocity() {
        XCTAssertEqual(TrackpadIntent.pageSwipe(offset: -20, velocity: -950, pageWidth: 800), .nextPage)
        XCTAssertEqual(TrackpadIntent.pageSwipe(offset: 20, velocity: 950, pageWidth: 800), .previousPage)
    }

    func testPageSwipeCancelsWhenBelowThresholds() {
        XCTAssertNil(TrackpadIntent.pageSwipe(offset: 20, velocity: 200, pageWidth: 800))
    }
}

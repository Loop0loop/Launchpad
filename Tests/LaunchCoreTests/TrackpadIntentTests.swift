import XCTest
@testable import LaunchpadCore

final class TrackpadIntentTests: XCTestCase {
    private let threeTouches = [
        TrackpadTouchSample(id: 1, x: 0.1, y: 0.1),
        TrackpadTouchSample(id: 2, x: 0.2, y: 0.1),
        TrackpadTouchSample(id: 3, x: 0.15, y: 0.2)
    ]

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

    func testContactGateRequiresExactStableFingerCount() {
        var gate = TrackpadContactGate()
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0), .waiting)
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.01), .waiting)
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.02), .waiting)
        XCTAssertEqual(
            gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.03),
            .qualified(threeTouches)
        )
    }

    func testContactGateRearmsAfterSequentialFingerLanding() {
        var gate = TrackpadContactGate()
        XCTAssertEqual(gate.update(touches: Array(threeTouches.prefix(1)), requiredFingerCounts: [3], timestamp: 0), .rejected)
        XCTAssertEqual(gate.update(touches: Array(threeTouches.prefix(2)), requiredFingerCounts: [3], timestamp: 0.01), .rejected)
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.02), .waiting)
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.03), .waiting)
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.04), .waiting)
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.05), .qualified(threeTouches))
    }

    func testContactGateEndsWhenQualifiedFingersLiftOneAtATime() {
        var gate = TrackpadContactGate()
        for frame in 0...3 {
            _ = gate.update(
                touches: threeTouches,
                requiredFingerCounts: [3],
                timestamp: Double(frame) * 0.01
            )
        }
        XCTAssertEqual(
            gate.update(touches: Array(threeTouches.prefix(2)), requiredFingerCounts: [3], timestamp: 0.04),
            .ended
        )
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.05), .waiting)
    }

    func testContactGateIgnoresHoverAndTracksReleaseLifecycle() {
        var gate = TrackpadContactGate()
        let inactive = [
            TrackpadTouchSample(id: 8, x: 0.4, y: 0.4, state: 2),
            TrackpadTouchSample(id: 9, x: 0.5, y: 0.5, state: 2)
        ]
        for frame in 0..<3 {
            XCTAssertEqual(
                gate.update(
                    touches: threeTouches + inactive,
                    requiredFingerCounts: [3],
                    timestamp: Double(frame) * 0.01
                ),
                .waiting
            )
        }
        XCTAssertEqual(
            gate.update(touches: threeTouches + inactive, requiredFingerCounts: [3], timestamp: 0.03),
            .qualified(threeTouches)
        )

        let releasing = threeTouches.map {
            TrackpadTouchSample(id: $0.id, x: $0.x, y: $0.y, state: 5)
        }
        XCTAssertEqual(
            gate.update(touches: releasing + inactive, requiredFingerCounts: [3], timestamp: 0.04),
            .qualified(releasing)
        )
    }
}

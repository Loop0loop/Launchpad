import XCTest
@testable import LaunchpadCore

final class TrackpadGesturePreferenceSnapshotTests: XCTestCase {
    func testRestorePlanKeepsOriginalValuesAndRemovesMissingKeys() {
        let snapshot = TrackpadGesturePreferenceSnapshot(values: [
            "enabled": 2,
            "missing": nil
        ])

        XCTAssertEqual(snapshot.restoreWrites["enabled"]!, 2)
        XCTAssertNil(snapshot.restoreWrites["missing"]!)
        XCTAssertEqual(snapshot.reserveWrites, ["enabled": 0, "missing": 0])
        XCTAssertEqual(snapshot.restoreNotificationNames, [
            "com.apple.AppleMultitouchTrackpadDomainDidChangeNotification",
            "com.apple.AppleMenuGesturesDidChangeNotification"
        ])
        XCTAssertEqual(snapshot.restoreLaunchAgentLabels, ["com.apple.Dock.agent"])
    }

    func testReservationPlanCanSnapshotMissionControlForTemporarySuppression() {
        for original: Int? in [nil, 0, 1] {
            let values: [String: Int?] = [
                "showSpotlightGestureEnabled": original,
                "showDesktopGestureEnabled": 1,
                "TrackpadFourFingerPinchGesture": 2,
                "com.apple.trackpad.fourFingerPinchSwipeGesture": 2,
                "TrackpadThreeFingerVertSwipeGesture": 2,
                "TrackpadFourFingerVertSwipeGesture": 2
            ]
            let snapshot = TrackpadGesturePreferenceSnapshot(values: values)
            XCTAssertEqual(snapshot.reserveWrites, [
                "showSpotlightGestureEnabled": 0,
                "showDesktopGestureEnabled": 1,
                "TrackpadFourFingerPinchGesture": 0,
                "com.apple.trackpad.fourFingerPinchSwipeGesture": 0,
                "TrackpadThreeFingerVertSwipeGesture": 0,
                "TrackpadFourFingerVertSwipeGesture": 0
            ])
            XCTAssertEqual(snapshot.restoreWrites, values)
        }
    }
}

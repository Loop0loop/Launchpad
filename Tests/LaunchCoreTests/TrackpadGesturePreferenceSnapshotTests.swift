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
}

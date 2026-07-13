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

    func testPinchProgressFollowsAndReversesWithFingerSpread() {
        var session = TrackpadGestureSession()
        XCTAssertNil(session.trackPinch(radius: 1, timestamp: 0))
        guard case .tracking(.open, let halfway, let timestamp)? = session.trackPinch(radius: 0.8665, timestamp: 0.01) else {
            return XCTFail("expected halfway open progress")
        }
        XCTAssertEqual(halfway, 0.5, accuracy: 0.001)
        XCTAssertEqual(timestamp, 0.01)
        guard case .tracking(.open, let progress, _)? = session.trackPinch(radius: 0.9705, timestamp: 0.02) else {
            return XCTFail("expected reversible progress")
        }
        XCTAssertEqual(progress, 0.1, accuracy: 0.001)
    }

    func testPinchDeadZoneIsContinuousAtBoundary() {
        var session = TrackpadGestureSession()
        XCTAssertNil(session.trackPinch(radius: 1, timestamp: 0))
        XCTAssertNil(session.trackPinch(radius: 0.9966, timestamp: 0.01))
        guard case .tracking(.open, let progress, _)? = session.trackPinch(radius: 0.9964, timestamp: 0.02) else {
            return XCTFail("expected progress immediately beyond dead zone")
        }
        XCTAssertLessThan(progress, 0.001)
    }

    func testClaimedCloseCannotFlipToOpen() {
        var session = TrackpadGestureSession()
        XCTAssertNil(session.trackPinch(radius: 1, timestamp: 0, lockedIntent: .close))
        XCTAssertNil(session.trackPinch(radius: 0.9, timestamp: 0.01, lockedIntent: .close))
        guard case .tracking(.close, let progress, _)? = session.trackPinch(
            radius: 1.18,
            timestamp: 0.02,
            lockedIntent: .close
        ) else {
            return XCTFail("expected the claimed close direction to stay locked")
        }
        XCTAssertGreaterThan(progress, 0.5)
        XCTAssertEqual(session.trackPinch(radius: nil, timestamp: 0.03), .commit(.close))
    }

    func testClaimedPinchToleratesCenterDrift() {
        var session = TrackpadGestureSession()
        XCTAssertNil(session.trackPinch(
            radius: 1,
            centerX: 0.5,
            centerY: 0.5,
            timestamp: 0,
            lockedIntent: .open
        ))
        guard case .tracking(.open, let progress, _)? = session.trackPinch(
            radius: 0.86,
            centerX: 0.65,
            centerY: 0.5,
            timestamp: 0.01,
            lockedIntent: .open
        ) else {
            return XCTFail("expected a claimed pinch to tolerate center drift")
        }
        XCTAssertGreaterThan(progress, 0.5)
    }

    func testTransitionTargetProjectsReleaseVelocity() {
        XCTAssertEqual(TrackpadIntent.projectedTransitionTarget(progress: 0.55, velocity: 0), 1)
        XCTAssertEqual(TrackpadIntent.projectedTransitionTarget(progress: 0.35, velocity: 0), 0)
        XCTAssertEqual(TrackpadIntent.projectedTransitionTarget(progress: 0.35, velocity: 2), 1)
        XCTAssertEqual(TrackpadIntent.projectedTransitionTarget(progress: 0.7, velocity: -2), 0)
    }

    func testAdditiveProgressHasConstantSensitivity() {
        XCTAssertEqual(TrackpadIntent.additiveTransitionProgress(start: 0.2, gestureProgress: 0.1, intent: .open), 0.3, accuracy: 0.001)
        XCTAssertEqual(TrackpadIntent.additiveTransitionProgress(start: 0.8, gestureProgress: 0.1, intent: .open), 0.9, accuracy: 0.001)
        XCTAssertEqual(TrackpadIntent.additiveTransitionProgress(start: 0.8, gestureProgress: 0.1, intent: .close), 0.7, accuracy: 0.001)
    }

    func testFourFingerShowDesktopPairYieldsToSystem() {
        var state = SystemShowDesktopGestureState()

        XCTAssertFalse(state.shouldYield(
            fingerCount: 4,
            intent: .open,
            systemGestureEnabled: true
        ))
        XCTAssertTrue(state.shouldYield(
            fingerCount: 4,
            intent: .close,
            systemGestureEnabled: true
        ))
        XCTAssertFalse(state.shouldYield(
            fingerCount: 5,
            intent: .open,
            systemGestureEnabled: true
        ))
        XCTAssertTrue(state.shouldYield(
            fingerCount: 4,
            intent: .open,
            systemGestureEnabled: true
        ))
        XCTAssertFalse(state.shouldYield(
            fingerCount: 4,
            intent: .open,
            systemGestureEnabled: true
        ))
    }

    func testDisablingShowDesktopClearsPendingReturn() {
        var state = SystemShowDesktopGestureState()
        XCTAssertTrue(state.shouldYield(
            fingerCount: 4,
            intent: .close,
            systemGestureEnabled: true
        ))
        XCTAssertFalse(state.shouldYield(
            fingerCount: 4,
            intent: .open,
            systemGestureEnabled: false
        ))
        XCTAssertFalse(state.shouldYield(
            fingerCount: 4,
            intent: .open,
            systemGestureEnabled: true
        ))
    }

    func testDirectShowDesktopWaitsForClearFourFingerMotion() {
        XCTAssertEqual(
            TrackpadIntent.systemShowDesktopDecision(
                fingerCount: 4,
                intent: .close,
                scaleRatio: 1.02,
                owner: .undecided,
                isEnabled: true
            ),
            .wait
        )
        XCTAssertEqual(
            TrackpadIntent.systemShowDesktopDecision(
                fingerCount: 4,
                intent: .close,
                scaleRatio: 1.08,
                owner: .undecided,
                isEnabled: true
            ),
            .show
        )
    }

    func testDirectShowDesktopRestoresOnlyWhileActive() {
        XCTAssertEqual(
            TrackpadIntent.systemShowDesktopDecision(
                fingerCount: 4,
                intent: .open,
                scaleRatio: 0.92,
                owner: .desktop,
                isEnabled: true
            ),
            .restore
        )
        XCTAssertEqual(
            TrackpadIntent.systemShowDesktopDecision(
                fingerCount: 4,
                intent: .open,
                scaleRatio: 0.80,
                owner: .undecided,
                isEnabled: true
            ),
            .launcher
        )
        XCTAssertEqual(
            TrackpadIntent.systemShowDesktopDecision(
                fingerCount: 5,
                intent: .close,
                scaleRatio: 1.20,
                owner: .undecided,
                isEnabled: true
            ),
            .launcher
        )
    }

    func testVisibleLauncherOwnsFourFingerRadialMotion() {
        XCTAssertEqual(
            TrackpadIntent.systemShowDesktopDecision(
                fingerCount: 4,
                intent: .close,
                scaleRatio: 1.20,
                owner: .launcher,
                isEnabled: true
            ),
            .launcher
        )
        XCTAssertEqual(
            TrackpadIntent.systemShowDesktopDecision(
                fingerCount: 4,
                intent: .open,
                scaleRatio: 0.80,
                owner: .launcher,
                isEnabled: true
            ),
            .launcher
        )
    }

    func testLauncherWinsPresentationOwnerSnapshot() {
        XCTAssertEqual(
            SystemShowDesktopGestureOwner(
                launcherIsVisible: true,
                systemShowDesktopIsActive: true
            ),
            .launcher
        )
        XCTAssertEqual(
            SystemShowDesktopGestureOwner(
                launcherIsVisible: false,
                systemShowDesktopIsActive: true
            ),
            .desktop
        )
        XCTAssertEqual(SystemShowDesktopGestureOwner.launcher.launcherIntent, .close)
        XCTAssertEqual(SystemShowDesktopGestureOwner.undecided.launcherIntent, .open)
        XCTAssertNil(SystemShowDesktopGestureOwner.desktop.launcherIntent)
    }

    func testOnlyLargeFastProgressJumpsAreInterpolated() {
        XCTAssertTrue(TrackpadIntent.shouldInterpolatePresentationJump(
            delta: 0.5,
            previousDelta: 0.1,
            velocity: 4
        ))
        XCTAssertFalse(TrackpadIntent.shouldInterpolatePresentationJump(
            delta: 0.03,
            previousDelta: 0.03,
            velocity: 4
        ))
        XCTAssertFalse(TrackpadIntent.shouldInterpolatePresentationJump(
            delta: 0.5,
            previousDelta: 0.1,
            velocity: 0.1
        ))
    }

    func testMedianPairScaleRatioComparesMatchingFingerPairs() {
        let baseline = [
            TrackpadTouchSample(id: 1, x: 0, y: 0),
            TrackpadTouchSample(id: 2, x: 1, y: 0),
            TrackpadTouchSample(id: 3, x: 0, y: 1)
        ]
        let current = baseline.map {
            TrackpadTouchSample(id: $0.id, x: $0.x * 2, y: $0.y * 2)
        }
        XCTAssertEqual(
            TrackpadContactQuality.medianPairScaleRatio(baseline: baseline, current: current)!,
            2,
            accuracy: 0.001
        )
    }

    func testScaleFilterUsesHardwareElapsedTime() {
        let filtered = TrackpadContactQuality.lowPassScaleRatio(
            previous: 1,
            current: 1.2,
            elapsed: 0.018,
            responseTime: 0.018
        )
        XCTAssertEqual(filtered, 1.126424, accuracy: 0.000_001)
        XCTAssertEqual(
            TrackpadContactQuality.lowPassScaleRatio(
                previous: filtered,
                current: 1.4,
                elapsed: 0,
                responseTime: 0.018
            ),
            filtered
        )
    }

    func testGestureIntentArbiterOnlyClaimsClearPinch() {
        let baseline = [
            TrackpadTouchSample(id: 1, x: 0.3, y: 0.3),
            TrackpadTouchSample(id: 2, x: 0.7, y: 0.3),
            TrackpadTouchSample(id: 3, x: 0.3, y: 0.7),
            TrackpadTouchSample(id: 4, x: 0.7, y: 0.7)
        ]
        var swipeArbiter = TrackpadGestureIntentArbiter(baseline: baseline, timestamp: 0)
        let translated = baseline.map {
            TrackpadTouchSample(id: $0.id, x: $0.x + 0.03, y: $0.y)
        }
        XCTAssertEqual(swipeArbiter.update(current: translated, timestamp: 0.01), .undecided)

        let irregular = [
            TrackpadTouchSample(id: 1, x: 0.34, y: 0.34),
            TrackpadTouchSample(id: 2, x: 0.74, y: 0.26),
            TrackpadTouchSample(id: 3, x: 0.34, y: 0.66),
            TrackpadTouchSample(id: 4, x: 0.74, y: 0.74)
        ]
        var irregularArbiter = TrackpadGestureIntentArbiter(baseline: baseline, timestamp: 0)
        XCTAssertEqual(irregularArbiter.update(current: irregular, timestamp: 0.01), .undecided)
        XCTAssertEqual(irregularArbiter.update(current: irregular, timestamp: 0.02), .undecided)

        let pinched = baseline.map {
            TrackpadTouchSample(
                id: $0.id,
                x: 0.5 + ($0.x - 0.5) * 0.9,
                y: 0.5 + ($0.y - 0.5) * 0.9
            )
        }
        let gradualPinch = baseline.map {
            TrackpadTouchSample(
                id: $0.id,
                x: 0.5 + ($0.x - 0.5) * 0.98,
                y: 0.5 + ($0.y - 0.5) * 0.98
            )
        }
        swipeArbiter.ignoreUntilLift()
        XCTAssertEqual(swipeArbiter.update(current: pinched, timestamp: 0.02), .ignoredUntilLift)

        var pinchArbiter = TrackpadGestureIntentArbiter(baseline: baseline, timestamp: 0)
        XCTAssertEqual(pinchArbiter.update(current: gradualPinch, timestamp: 0.01), .undecided)
        XCTAssertEqual(pinchArbiter.update(current: gradualPinch, timestamp: 0.02), .launcherRadialIn)
        var immediatePinchArbiter = TrackpadGestureIntentArbiter(baseline: baseline, timestamp: 0)
        XCTAssertEqual(immediatePinchArbiter.update(current: pinched, timestamp: 0.01), .launcherRadialIn)

        let spread = baseline.map {
            TrackpadTouchSample(
                id: $0.id,
                x: 0.5 + ($0.x - 0.5) * 1.1,
                y: 0.5 + ($0.y - 0.5) * 1.1
            )
        }
        let gradualSpread = baseline.map {
            TrackpadTouchSample(
                id: $0.id,
                x: 0.5 + ($0.x - 0.5) * 1.02,
                y: 0.5 + ($0.y - 0.5) * 1.02
            )
        }
        var immediateSpreadArbiter = TrackpadGestureIntentArbiter(baseline: baseline, timestamp: 0)
        XCTAssertEqual(immediateSpreadArbiter.update(current: spread, timestamp: 0.01), .launcherRadialOut)
        var reversingArbiter = TrackpadGestureIntentArbiter(baseline: baseline, timestamp: 0)
        XCTAssertEqual(reversingArbiter.update(current: gradualPinch, timestamp: 0.01), .undecided)
        XCTAssertEqual(reversingArbiter.update(current: gradualSpread, timestamp: 0.02), .undecided)
        XCTAssertEqual(reversingArbiter.update(current: gradualSpread, timestamp: 0.03), .launcherRadialOut)

        var interruptedArbiter = TrackpadGestureIntentArbiter(baseline: baseline, timestamp: 0)
        XCTAssertEqual(interruptedArbiter.update(current: gradualPinch, timestamp: 0.01), .undecided)
        XCTAssertEqual(interruptedArbiter.update(current: baseline, timestamp: 0.02), .undecided)
        XCTAssertEqual(interruptedArbiter.update(current: gradualPinch, timestamp: 0.03), .undecided)
        XCTAssertEqual(interruptedArbiter.update(current: gradualPinch, timestamp: 0.04), .launcherRadialIn)
    }

    func testContactGateRequiresExactStableFingerCount() {
        var gate = TrackpadContactGate()
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0), .waiting)
        XCTAssertEqual(
            gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.01),
            .provisional(threeTouches)
        )
        XCTAssertEqual(
            gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.02),
            .qualified(threeTouches)
        )
    }

    func testContactGateRearmsAfterSequentialFingerLanding() {
        var gate = TrackpadContactGate()
        XCTAssertEqual(gate.update(touches: Array(threeTouches.prefix(1)), requiredFingerCounts: [3], timestamp: 0), .rejected)
        XCTAssertEqual(gate.update(touches: Array(threeTouches.prefix(2)), requiredFingerCounts: [3], timestamp: 0.01), .rejected)
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.02), .waiting)
        XCTAssertEqual(
            gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.03),
            .provisional(threeTouches)
        )
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.04), .qualified(threeTouches))
    }

    func testSingleCountGateWaitsForLandingContact() {
        let fourthTouch = TrackpadTouchSample(id: 4, x: 0.25, y: 0.2)
        let landingFourth = TrackpadTouchSample(id: 4, x: 0.25, y: 0.2, state: 1)
        let fourTouches = threeTouches + [fourthTouch]
        var gate = TrackpadContactGate()

        XCTAssertEqual(
            gate.update(touches: threeTouches + [landingFourth], requiredFingerCounts: [4], timestamp: 0),
            .waiting
        )
        XCTAssertEqual(gate.update(touches: fourTouches, requiredFingerCounts: [4], timestamp: 0.01), .waiting)
        XCTAssertEqual(
            gate.update(touches: fourTouches, requiredFingerCounts: [4], timestamp: 0.02),
            .provisional(fourTouches)
        )
    }

    func testMultiCountGateWaitsForFinalSequentialFingerCount() {
        let fourTouches = threeTouches + [TrackpadTouchSample(id: 4, x: 0.25, y: 0.2)]
        let fiveTouches = fourTouches + [TrackpadTouchSample(id: 5, x: 0.3, y: 0.2)]
        let landingFourth = TrackpadTouchSample(id: 4, x: 0.25, y: 0.2, state: 1)
        let landingFifth = TrackpadTouchSample(id: 5, x: 0.3, y: 0.2, state: 3)
        var gate = TrackpadContactGate()

        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3, 4, 5], timestamp: 0), .waiting)
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3, 4, 5], timestamp: 0.01), .waiting)
        XCTAssertEqual(
            gate.update(touches: threeTouches + [landingFourth], requiredFingerCounts: [3, 4, 5], timestamp: 0.021),
            .waiting
        )
        XCTAssertEqual(gate.update(touches: fourTouches, requiredFingerCounts: [3, 4, 5], timestamp: 0.024), .waiting)
        XCTAssertEqual(
            gate.update(touches: fourTouches + [landingFifth], requiredFingerCounts: [3, 4, 5], timestamp: 0.045),
            .waiting
        )
        XCTAssertEqual(gate.update(touches: fiveTouches, requiredFingerCounts: [3, 4, 5], timestamp: 0.048), .waiting)
        XCTAssertEqual(
            gate.update(touches: fiveTouches, requiredFingerCounts: [3, 4, 5], timestamp: 0.109),
            .qualified(fiveTouches)
        )
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
        gate.claim()
        XCTAssertEqual(
            gate.update(touches: Array(threeTouches.prefix(2)), requiredFingerCounts: [3], timestamp: 0.04),
            .waiting
        )
        XCTAssertEqual(
            gate.update(touches: Array(threeTouches.prefix(2)), requiredFingerCounts: [3], timestamp: 0.09),
            .ended
        )
        XCTAssertEqual(gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.10), .waiting)
    }

    func testContactGateCountsOnlyPhysicallyTouchingContacts() {
        for state: UInt32 in [0, 1, 2, 3, 5, 6, 7] {
            XCTAssertFalse(TrackpadTouchSample(id: 1, x: 0, y: 0, state: state).isGestureContact)
        }
        XCTAssertTrue(TrackpadTouchSample(id: 1, x: 0, y: 0, state: 4).isGestureContact)

        var gate = TrackpadContactGate()
        let inactive = [
            TrackpadTouchSample(id: 8, x: 0.4, y: 0.4, state: 2),
            TrackpadTouchSample(id: 9, x: 0.5, y: 0.5, state: 2)
        ]
        XCTAssertEqual(
            gate.update(touches: threeTouches + inactive, requiredFingerCounts: [3], timestamp: 0),
            .waiting
        )
        XCTAssertEqual(
            gate.update(touches: threeTouches + inactive, requiredFingerCounts: [3], timestamp: 0.01),
            .provisional(threeTouches)
        )
        XCTAssertEqual(
            gate.update(touches: threeTouches + inactive, requiredFingerCounts: [3], timestamp: 0.02),
            .qualified(threeTouches)
        )
        gate.claim()

        let releasing = threeTouches.map {
            TrackpadTouchSample(id: $0.id, x: $0.x, y: $0.y, state: 5)
        }
        XCTAssertEqual(
            gate.update(touches: releasing + inactive, requiredFingerCounts: [3], timestamp: 0.03),
            .ended
        )
    }

    func testContactGateLocksExtraContactsOnlyAfterLauncherClaim() {
        let extraContact = TrackpadTouchSample(id: 10, x: 0.7, y: 0.7)
        var observingGate = TrackpadContactGate()
        _ = observingGate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0)
        _ = observingGate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.01)
        XCTAssertEqual(
            observingGate.update(
                touches: threeTouches + [extraContact],
                requiredFingerCounts: [3],
                timestamp: 0.02
            ),
            .rejected
        )

        var ownedGate = TrackpadContactGate()
        _ = ownedGate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0)
        _ = ownedGate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.01)
        ownedGate.claim()
        XCTAssertEqual(
            ownedGate.update(
                touches: threeTouches + [extraContact],
                requiredFingerCounts: [3],
                timestamp: 0.02
            ),
            .qualified(threeTouches)
        )
    }

    func testContactGateIgnoresPartialReleaseAfterCommittedAction() {
        var gate = TrackpadContactGate()
        _ = gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0)
        _ = gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.01)
        gate.ignoreUntilAllTouchesLift()

        XCTAssertEqual(
            gate.update(touches: Array(threeTouches.prefix(2)), requiredFingerCounts: [3], timestamp: 0.02),
            .waiting
        )
        XCTAssertEqual(
            gate.update(touches: Array(threeTouches.prefix(1)), requiredFingerCounts: [3], timestamp: 0.03),
            .waiting
        )
        XCTAssertEqual(gate.update(touches: [], requiredFingerCounts: [3], timestamp: 0.04), .ended)
    }

    func testContactGateEndsImmediatelyWhenAllFingersLift() {
        var gate = TrackpadContactGate()
        _ = gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0)
        _ = gate.update(touches: threeTouches, requiredFingerCounts: [3], timestamp: 0.01)
        XCTAssertEqual(gate.update(touches: [], requiredFingerCounts: [3], timestamp: 0.011), .ended)
    }
}

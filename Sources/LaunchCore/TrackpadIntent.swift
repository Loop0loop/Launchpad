public enum TrackpadIntent: Equatable, Sendable {
    case open
    case close
    case previousPage
    case nextPage

    public static func pinch(magnification: Double, threshold: Double = 0.08) -> TrackpadIntent? {
        if magnification <= -threshold { return .open }
        if magnification >= threshold { return .close }
        return nil
    }

    public static func horizontalSwipe(deltaX: Double, threshold: Double = 0.5) -> TrackpadIntent? {
        if deltaX <= -threshold { return .nextPage }
        if deltaX >= threshold { return .previousPage }
        return nil
    }

    public static func horizontalScroll(deltaX: Double, threshold: Double = 12) -> TrackpadIntent? {
        if deltaX <= -threshold { return .nextPage }
        if deltaX >= threshold { return .previousPage }
        return nil
    }

    public static func pageSwipe(
        offset: Double,
        velocity: Double,
        pageWidth: Double,
        distanceThreshold: Double = 60,
        distanceRatio: Double = 0.15,
        velocityThreshold: Double = 900
    ) -> TrackpadIntent? {
        let threshold = max(pageWidth * distanceRatio, distanceThreshold)
        if offset <= -threshold || velocity <= -velocityThreshold { return .nextPage }
        if offset >= threshold || velocity >= velocityThreshold { return .previousPage }
        return nil
    }

    public static func shouldAcceptScrollIntent(eventTime: Double, lastIntentTime: Double, minimumInterval: Double = 0.7) -> Bool {
        eventTime - lastIntentTime > minimumInterval
    }

    public static func pinchRadius(ratio: Double, pinchInThreshold: Double = 0.9, pinchOutThreshold: Double = 1.1) -> TrackpadIntent? {
        if ratio <= pinchInThreshold { return .open }
        if ratio >= pinchOutThreshold { return .close }
        return nil
    }

    /// 0...1 progress toward opening as radius shrinks past `start` down to `full`.
    public static func pinchOpenProgress(
        ratio: Double,
        start: Double = 0.9,
        full: Double = 0.82
    ) -> Double {
        guard start > full else { return ratio <= full ? 1 : 0 }
        if ratio >= start { return 0 }
        if ratio <= full { return 1 }
        return (start - ratio) / (start - full)
    }

    /// 0...1 progress toward closing as radius grows past `start` up to `full`.
    public static func pinchCloseProgress(
        ratio: Double,
        start: Double = 1.1,
        full: Double = 1.18
    ) -> Double {
        guard full > start else { return ratio >= full ? 1 : 0 }
        if ratio <= start { return 0 }
        if ratio >= full { return 1 }
        return (ratio - start) / (full - start)
    }

    public static func projectedTransitionTarget(
        progress: Double,
        velocity: Double,
        projectionTime: Double = 0.12
    ) -> Double {
        let projected = min(max(progress + velocity * projectionTime, 0), 1)
        return projected >= 0.5 ? 1 : 0
    }

    public static func additiveTransitionProgress(
        start: Double,
        gestureProgress: Double,
        intent: TrackpadIntent
    ) -> Double {
        let delta = intent == .open ? gestureProgress : -gestureProgress
        return min(max(start + delta, 0), 1)
    }

    public static func shouldInterpolatePresentationJump(
        delta: Double,
        previousDelta: Double,
        velocity: Double,
        largeJumpThreshold: Double = 0.14,
        fastVelocityThreshold: Double = 2,
        stationaryVelocityThreshold: Double = 0.12,
        stationaryDeltaThreshold: Double = 0.002
    ) -> Bool {
        let stationary = abs(velocity) < stationaryVelocityThreshold
            || (abs(delta) < stationaryDeltaThreshold && abs(previousDelta) < stationaryDeltaThreshold)
        return !stationary
            && abs(delta) > largeJumpThreshold
            && abs(velocity) > fastVelocityThreshold
    }
}

public struct SystemShowDesktopGestureState: Equatable, Sendable {
    private var isAwaitingReturn = false

    public init() {}

    public mutating func shouldYield(
        fingerCount: Int,
        intent: TrackpadIntent,
        systemGestureEnabled: Bool
    ) -> Bool {
        guard systemGestureEnabled else {
            reset()
            return false
        }
        guard fingerCount == 4 else { return false }
        if intent == .close {
            isAwaitingReturn = true
            return true
        }
        guard intent == .open, isAwaitingReturn else { return false }
        isAwaitingReturn = false
        return true
    }

    public mutating func reset() {
        isAwaitingReturn = false
    }
}

public enum SystemShowDesktopGestureDecision: Equatable, Sendable {
    case launcher
    case wait
    case show
    case restore
    case ignore
}

public enum SystemShowDesktopGestureOwner: Equatable, Sendable {
    case launcher
    case desktop
    case undecided

    public init(launcherIsVisible: Bool, systemShowDesktopIsActive: Bool) {
        if launcherIsVisible {
            self = .launcher
        } else if systemShowDesktopIsActive {
            self = .desktop
        } else {
            self = .undecided
        }
    }

    public var launcherIntent: TrackpadIntent? {
        switch self {
        case .launcher: .close
        case .undecided: .open
        case .desktop: nil
        }
    }
}

public extension TrackpadIntent {
    static func systemShowDesktopDecision(
        fingerCount: Int,
        intent: TrackpadIntent,
        scaleRatio: Double,
        owner: SystemShowDesktopGestureOwner,
        isEnabled: Bool,
        minimumScaleChange: Double = 0.08
    ) -> SystemShowDesktopGestureDecision {
        guard isEnabled, fingerCount == 4 else { return .launcher }

        switch owner {
        case .launcher:
            return .launcher
        case .desktop:
            guard intent == .open else { return .ignore }
            return scaleRatio <= 1 - minimumScaleChange ? .restore : .wait
        case .undecided:
            guard intent == .close else { return .launcher }
            return scaleRatio >= 1 + minimumScaleChange ? .show : .wait
        }
    }
}

public enum TrackpadPinchUpdate: Equatable, Sendable {
    case tracking(intent: TrackpadIntent, progress: Double, timestamp: Double)
    case commit(TrackpadIntent)
    case cancel
}

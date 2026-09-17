import Foundation

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

    public static func settledTransitionTarget(
        progress: Double,
        velocity: Double,
        committed: Bool,
        startProgress: Double,
        projectionTime: Double = 0.12
    ) -> Double {
        guard committed else { return startProgress >= 0.5 ? 1 : 0 }
        return projectedTransitionTarget(
            progress: progress,
            velocity: velocity,
            projectionTime: projectionTime
        )
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

public enum SystemDesktopVisibility: Equatable, Sendable {
    case unknown
    case windowsVisible
    case desktopVisible

    public var allowsLauncherPresentation: Bool { self == .windowsVisible }

    public func preemptsLauncherGesture(ownedBy ownership: TrackpadGestureOwnership?) -> Bool {
        switch (self, ownership) {
        case (.windowsVisible, .launcherRadialIn?), (.windowsVisible, .launcherRadialOut?): false
        default: true
        }
    }
}

public enum SystemShowDesktopGestureOwner: Equatable, Sendable {
    case launcher
    case desktop
    case undecided
    case unknown

    public init(launcherIsVisible: Bool, systemDesktopVisibility: SystemDesktopVisibility) {
        if launcherIsVisible {
            self = .launcher
        } else {
            self = switch systemDesktopVisibility {
            case .unknown: .unknown
            case .windowsVisible: .undecided
            case .desktopVisible: .desktop
            }
        }
    }

    public var launcherIntent: TrackpadIntent? {
        switch self {
        case .launcher: .close
        case .undecided: .open
        case .desktop, .unknown: nil
        }
    }

    /// The system owns desktop show/restore; a physical spread cannot open our UI.
    public func acceptsLauncherIntent(_ intent: TrackpadIntent) -> Bool {
        launcherIntent == intent
    }
}

public enum SystemShowDesktopGestureDecision: Equatable, Sendable {
    case launcher
    case wait
    case show
    case restore
    case ignore
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
        case .unknown:
            return .wait
        }
    }
}

/// A desktop return remains system-owned even when Exposé reports its exit
/// before the physical pinch has ended.
public struct SystemDesktopContactSession: Equatable, Sendable {
    public private(set) var isSystemOwned = false
    public private(set) var hasContacts = false

    public init() {}

    public mutating func update(hasContacts: Bool, desktopIsActive: Bool) {
        self.hasContacts = hasContacts
        if !hasContacts {
            isSystemOwned = false
        } else if desktopIsActive {
            isSystemOwned = true
        }
    }

    /// Even an exit without a preceding enter belongs to the system gesture
    /// currently touching the device, never to the next physical gesture.
    public mutating func systemTransitionReceived() {
        if hasContacts { isSystemOwned = true }
    }
}

public enum SystemShowDesktopGestureUpdate: Equatable, Sendable {
    case began(progress: Double)
    case changed(progress: Double)
    case ended(progress: Double, velocity: Double)
    case cancelled(progress: Double, velocity: Double)

    public func resolvedDesktopActive(
        from current: Bool,
        threshold: Double = 0.42,
        projectionTime: Double = 0.08
    ) -> Bool {
        guard case .ended(let progress, let velocity) = self else { return current }
        let projected = progress + velocity * projectionTime
        return current ? projected > -threshold : projected >= threshold
    }
}

/// Converts the physical pinch scale into the accumulated Dock Swipe progress
/// expected by macOS. Positive progress spreads windows to reveal the desktop;
/// negative progress restores them.
public struct SystemShowDesktopGestureSession: Equatable, Sendable {
    private var isTracking = false
    private var originScale: Double?
    private var restoring = false
    private var lastProgress = 0.0
    private var lastVelocity = 0.0
    private var lastTimestamp: Double?

    public init() {}

    public var isActive: Bool { isTracking }

    public mutating func update(
        scaleRatio: Double,
        sensitivity: Double = 4.0,
        restoring: Bool = false,
        timestamp: Double? = nil
    ) -> SystemShowDesktopGestureUpdate? {
        guard scaleRatio.isFinite, scaleRatio > 0 else { return nil }
        guard let originScale else {
            self.originScale = scaleRatio
            self.restoring = restoring
            lastTimestamp = timestamp
            isTracking = true
            return .began(progress: 0)
        }
        let displacement = log(scaleRatio / originScale) * sensitivity
        // Returning past the origin cancels this action; it must not start the opposite UI.
        let progress = self.restoring ? min(displacement, 0) : max(displacement, 0)
        let elapsed = timestamp.flatMap { current in
            lastTimestamp.map { current - $0 }.flatMap { $0 > 0 ? $0 : nil }
        }
        let velocity = (progress - lastProgress) / (elapsed ?? 0.01)
        lastProgress = progress
        lastVelocity = velocity
        lastTimestamp = timestamp
        return .changed(progress: progress)
    }

    public mutating func finish(cancelled: Bool = false) -> SystemShowDesktopGestureUpdate? {
        guard isTracking else { return nil }
        let reversedAtRelease = lastProgress != 0
            && lastVelocity != 0
            && lastProgress.sign != lastVelocity.sign
        let update: SystemShowDesktopGestureUpdate = cancelled || reversedAtRelease
            ? .cancelled(progress: lastProgress, velocity: lastVelocity)
            : .ended(progress: lastProgress, velocity: lastVelocity)
        self = SystemShowDesktopGestureSession()
        return update
    }
}

public enum TrackpadPinchUpdate: Equatable, Sendable {
    case tracking(intent: TrackpadIntent, progress: Double, timestamp: Double)
    case commit(TrackpadIntent)
    case cancel
}

/// Coalesce progress, but invalidate both progress and completion when the
/// system takes over. A drained batch must also be checked before delivery.
public struct TrackpadPinchDelivery: Sendable {
    public private(set) var generation: UInt = 0
    private var tracking: TrackpadPinchUpdate?
    private var terminal: TrackpadPinchUpdate?

    public init() {}

    public mutating func enqueue(_ update: TrackpadPinchUpdate) {
        switch update {
        case .tracking:
            if terminal == nil { tracking = update }
        case .commit, .cancel:
            terminal = update
        }
    }

    public mutating func drain() -> (generation: UInt, tracking: TrackpadPinchUpdate?, terminal: TrackpadPinchUpdate?) {
        let batch = (generation, tracking, terminal)
        tracking = nil
        terminal = nil
        return batch
    }

    public mutating func invalidate() {
        generation &+= 1
        tracking = nil
        terminal = nil
    }
}

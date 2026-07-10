public struct TrackpadTouchSample: Equatable, Sendable {
    public let id: Int32
    public let x: Double
    public let y: Double
    public let majorAxis: Double
    public let minorAxis: Double
    public let zTotal: Double
    public let state: UInt32

    public init(
        id: Int32,
        x: Double,
        y: Double,
        majorAxis: Double = 0,
        minorAxis: Double = 0,
        zTotal: Double = 0,
        state: UInt32 = 4
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.zTotal = zTotal
        self.state = state
    }

    public var isActivelyTouching: Bool { state == 3 || state == 4 }
}

public enum TrackpadContactQuality {
    public static func qualifiedPinchTouches(
        _ touches: [TrackpadTouchSample],
        requiredCount: Int = 4
    ) -> [TrackpadTouchSample]? {
        let activeTouches = touches.filter(\.isActivelyTouching)
        guard activeTouches.count == requiredCount else { return nil }
        return activeTouches.sorted { $0.id < $1.id }
    }
}

public enum TrackpadContactGateUpdate: Equatable, Sendable {
    case waiting
    case qualified([TrackpadTouchSample])
    case ended
    case rejected
}

/// Requires an exact, stable set of contacts before a pinch may begin.
public struct TrackpadContactGate: Sendable {
    private var stableIDs: [Int32]?
    private var stableSince = 0.0
    private var stableFrames = 0
    private var wasQualified = false
    private var blockedUntilLift = false

    public init() {}

    public mutating func update(
        touches: [TrackpadTouchSample],
        requiredFingerCounts: [Int],
        timestamp: Double,
        minimumStableFrames: Int = 4,
        minimumStableDuration: Double = 0.025
    ) -> TrackpadContactGateUpdate {
        let activeTouches = touches.filter(\.isActivelyTouching)
        guard !activeTouches.isEmpty else {
            let result: TrackpadContactGateUpdate = wasQualified ? .ended : .waiting
            self = TrackpadContactGate()
            return result
        }
        guard !blockedUntilLift else { return .rejected }
        if wasQualified, let stableIDs, activeTouches.count < stableIDs.count {
            wasQualified = false
            blockedUntilLift = true
            return .ended
        }
        guard let selected = requiredFingerCounts
            .sorted(by: >)
            .compactMap({ TrackpadContactQuality.qualifiedPinchTouches(activeTouches, requiredCount: $0) })
            .first else {
            blockedUntilLift = true
            return .rejected
        }

        let ids = selected.map(\.id)
        if stableIDs == nil {
            stableIDs = ids
            stableSince = timestamp
            stableFrames = 1
            return .waiting
        }
        guard stableIDs == ids else {
            blockedUntilLift = true
            return .rejected
        }

        stableFrames += 1
        guard stableFrames >= minimumStableFrames,
              timestamp - stableSince >= minimumStableDuration else { return .waiting }
        wasQualified = true
        return .qualified(selected)
    }
}

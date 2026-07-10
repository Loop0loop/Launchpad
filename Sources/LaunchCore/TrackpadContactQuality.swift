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

    /// MultitouchSupport keeps a contact alive across its start/touch/release lifecycle.
    public var isGestureContact: Bool { [1, 3, 4, 5, 6].contains(state) }
}

public enum TrackpadContactQuality {
    public static func qualifiedPinchTouches(
        _ touches: [TrackpadTouchSample],
        requiredCount: Int = 4
    ) -> [TrackpadTouchSample]? {
        let activeTouches = touches.filter(\.isGestureContact)
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

    public init() {}

    public mutating func update(
        touches: [TrackpadTouchSample],
        requiredFingerCounts: [Int],
        timestamp: Double,
        minimumStableFrames: Int = 4,
        minimumStableDuration: Double = 0.025
    ) -> TrackpadContactGateUpdate {
        let activeTouches = touches.filter(\.isGestureContact)
        guard !activeTouches.isEmpty else {
            let result: TrackpadContactGateUpdate = wasQualified ? .ended : .waiting
            self = TrackpadContactGate()
            return result
        }
        guard let selected = requiredFingerCounts
            .sorted(by: >)
            .compactMap({ TrackpadContactQuality.qualifiedPinchTouches(activeTouches, requiredCount: $0) })
            .first else {
            let result: TrackpadContactGateUpdate = wasQualified ? .ended : .rejected
            self = TrackpadContactGate()
            return result
        }

        let ids = selected.map(\.id)
        if stableIDs == nil {
            stableIDs = ids
            stableSince = timestamp
            stableFrames = 1
            return .waiting
        }
        guard stableIDs == ids else {
            let result: TrackpadContactGateUpdate = wasQualified ? .ended : .waiting
            stableIDs = ids
            stableSince = timestamp
            stableFrames = 1
            wasQualified = false
            return result
        }

        stableFrames += 1
        guard stableFrames >= minimumStableFrames,
              timestamp - stableSince >= minimumStableDuration else { return .waiting }
        wasQualified = true
        return .qualified(selected)
    }
}

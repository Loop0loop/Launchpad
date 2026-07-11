import Foundation

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

    /// State 4 is the only physically touching phase; nearby and release phases are not fingers.
    public var isGestureContact: Bool { state == 4 }
}

public enum TrackpadContactQuality {
    public static func qualifiedPinchTouches(
        _ touches: [TrackpadTouchSample],
        requiredCount: Int = 4
    ) -> [TrackpadTouchSample]? {
        let activeTouches = touches.filter(\.isGestureContact)
        guard activeTouches.count == requiredCount else { return nil }
        guard activeTouches.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        return activeTouches.sorted { $0.id < $1.id }
    }

    public static func lowPassScaleRatio(
        previous: Double?,
        current: Double,
        elapsed: Double,
        responseTime: Double
    ) -> Double {
        guard current.isFinite, current > 0 else { return previous ?? 1 }
        guard let previous else { return current }
        guard elapsed > 0, responseTime > 0 else { return previous }
        let alpha = 1 - exp(-elapsed / responseTime)
        return previous + (current - previous) * alpha
    }

    public static func medianPairScaleRatio(
        baseline: [TrackpadTouchSample],
        current: [TrackpadTouchSample]
    ) -> Double? {
        var baselineByID: [Int32: TrackpadTouchSample] = [:]
        for touch in baseline { baselineByID[touch.id] = touch }
        let matched = current.compactMap { touch in baselineByID[touch.id].map { ($0, touch) } }
        guard matched.count == baseline.count, matched.count > 1 else { return nil }

        var logRatios: [Double] = []
        for first in matched.indices {
            for second in matched.indices where second > first {
                let baselineDX = matched[first].0.x - matched[second].0.x
                let baselineDY = matched[first].0.y - matched[second].0.y
                let currentDX = matched[first].1.x - matched[second].1.x
                let currentDY = matched[first].1.y - matched[second].1.y
                let baselineDistance = (baselineDX * baselineDX + baselineDY * baselineDY).squareRoot()
                let currentDistance = (currentDX * currentDX + currentDY * currentDY).squareRoot()
                guard baselineDistance > 0, currentDistance > 0 else { continue }
                logRatios.append(log(currentDistance / baselineDistance))
            }
        }
        guard !logRatios.isEmpty else { return nil }
        logRatios.sort()
        let middle = logRatios.count / 2
        let median = logRatios.count.isMultiple(of: 2)
            ? (logRatios[middle - 1] + logRatios[middle]) / 2
            : logRatios[middle]
        return exp(median)
    }
}

public enum TrackpadContactGateUpdate: Equatable, Sendable {
    case waiting
    case provisional([TrackpadTouchSample])
    case qualified([TrackpadTouchSample])
    case ended
    case rejected
}

/// Requires an exact stable set to begin. Contacts are locked only after the
/// caller confirms launcher ownership.
public struct TrackpadContactGate: Sendable {
    private var stableIDs: [Int32]?
    private var stableSince = 0.0
    private var stableFrames = 0
    private var wasProvisional = false
    private var isOwned = false
    private var ignoresUntilAllTouchesLift = false
    private var contactLossSince: Double?

    public init() {}

    public mutating func update(
        touches: [TrackpadTouchSample],
        requiredFingerCounts: [Int],
        timestamp: Double,
        provisionalStableFrames: Int = 2,
        provisionalStartDuration: Double = 0.008,
        minimumStableDuration: Double = 0.02,
        multipleCountStableDuration: Double = 0.06,
        contactLossGrace: Double = 0.02
    ) -> TrackpadContactGateUpdate {
        let activeTouches = touches.filter(\.isGestureContact)
        if activeTouches.isEmpty {
            let result: TrackpadContactGateUpdate = wasProvisional || isOwned ? .ended : .waiting
            self = TrackpadContactGate()
            return result
        }
        if ignoresUntilAllTouchesLift { return .waiting }
        if isOwned, let stableIDs {
            var activeByID: [Int32: TrackpadTouchSample] = [:]
            for touch in activeTouches { activeByID[touch.id] = touch }
            let selected = stableIDs.compactMap { activeByID[$0] }
            if selected.count == stableIDs.count {
                contactLossSince = nil
                return .qualified(selected)
            }
            if contactLossSince == nil { contactLossSince = timestamp }
            guard timestamp - (contactLossSince ?? timestamp) >= contactLossGrace else { return .waiting }
            self = TrackpadContactGate()
            return .ended
        }
        if requiredFingerCounts.count > 1 {
            let landingCount = touches.filter { $0.state < 4 }.count
            if landingCount > 0,
               requiredFingerCounts.contains(activeTouches.count + landingCount) {
                return .waiting
            }
        }
        guard let selected = requiredFingerCounts
            .sorted(by: >)
            .compactMap({ TrackpadContactQuality.qualifiedPinchTouches(activeTouches, requiredCount: $0) })
            .first else {
            self = TrackpadContactGate()
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
            let result: TrackpadContactGateUpdate = wasProvisional ? .rejected : .waiting
            self = TrackpadContactGate()
            guard result == .waiting else { return result }
            stableIDs = ids
            stableSince = timestamp
            stableFrames = 1
            return result
        }

        stableFrames += 1
        let elapsed = timestamp - stableSince
        let requiredStableDuration = requiredFingerCounts.count > 1
            ? multipleCountStableDuration
            : minimumStableDuration
        if elapsed >= requiredStableDuration {
            wasProvisional = true
            return .qualified(selected)
        }
        if requiredFingerCounts.count == 1,
           stableFrames >= provisionalStableFrames || elapsed >= provisionalStartDuration {
            wasProvisional = true
            return .provisional(selected)
        }
        return .waiting
    }

    public mutating func claim() {
        guard stableIDs != nil else { return }
        wasProvisional = true
        isOwned = true
    }

    public mutating func ignoreUntilAllTouchesLift() {
        wasProvisional = true
        ignoresUntilAllTouchesLift = true
    }
}

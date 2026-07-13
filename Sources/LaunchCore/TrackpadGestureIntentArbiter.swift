import Foundation

public enum TrackpadGestureOwnership: Equatable, Sendable {
    case undecided
    case launcherRadialIn
    case launcherRadialOut
    case ignoredUntilLift
}

public struct TrackpadGestureIntentArbiter: Sendable {
    private let baseline: [TrackpadTouchSample]
    private var pendingOwnership: TrackpadGestureOwnership = .undecided
    private var pendingEvidenceFrames = 0
    public private(set) var ownership: TrackpadGestureOwnership = .undecided

    public init(baseline: [TrackpadTouchSample], timestamp _: Double) {
        self.baseline = baseline.sorted { $0.id < $1.id }
    }

    public mutating func update(
        current: [TrackpadTouchSample],
        timestamp _: Double,
        minimumScaleChange: Double = 0.01,
        immediateScaleChange: Double = 0.04,
        requiredEvidenceFrames: Int = 2
    ) -> TrackpadGestureOwnership {
        guard ownership == .undecided else { return ownership }

        var currentByID: [Int32: TrackpadTouchSample] = [:]
        for touch in current { currentByID[touch.id] = touch }
        let matched = baseline.compactMap { base in currentByID[base.id].map { (base, $0) } }
        guard matched.count == baseline.count, matched.count > 1 else {
            pendingOwnership = .undecided
            pendingEvidenceFrames = 0
            return ownership
        }

        let dx = matched.map { $0.1.x - $0.0.x }
        let dy = matched.map { $0.1.y - $0.0.y }
        let translationX = dx.reduce(0, +) / Double(matched.count)
        let translationY = dy.reduce(0, +) / Double(matched.count)
        let translationMagnitude = hypot(translationX, translationY)
        let motion = zip(dx, dy).map(hypot)
        let totalMotion = Self.median(motion)

        let centerX = matched.map(\.0.x).reduce(0, +) / Double(matched.count)
        let centerY = matched.map(\.0.y).reduce(0, +) / Double(matched.count)
        let radialComponents = matched.map { baselineTouch, currentTouch in
            let radialX = baselineTouch.x - centerX
            let radialY = baselineTouch.y - centerY
            let radialLength = max(hypot(radialX, radialY), 0.000_001)
            let centeredDX = currentTouch.x - baselineTouch.x - translationX
            let centeredDY = currentTouch.y - baselineTouch.y - translationY
            return centeredDX * radialX / radialLength + centeredDY * radialY / radialLength
        }
        let signedRadialMotion = Self.median(radialComponents)
        let radialMagnitude = Self.median(radialComponents.map(abs))
        let matchingRadialCount = radialComponents.filter {
            abs($0) > 0.000_001 && ($0 < 0) == (signedRadialMotion < 0)
        }.count
        let radialCoherence = Double(matchingRadialCount) / Double(radialComponents.count)
        let scaleRatio = TrackpadContactQuality.medianPairScaleRatio(
            baseline: baseline,
            current: current
        ) ?? 1
        let logScale = log(scaleRatio)

        guard totalMotion > 0.004 || abs(logScale) > 0.004 else {
            pendingOwnership = .undecided
            pendingEvidenceFrames = 0
            return ownership
        }

        let combinedEnergy = translationMagnitude + radialMagnitude + 0.000_001
        let radialShare = radialMagnitude / combinedEnergy
        guard abs(logScale) > minimumScaleChange,
              radialShare > 0.45,
              radialCoherence > 0.58 else {
            pendingOwnership = .undecided
            pendingEvidenceFrames = 0
            return ownership
        }

        let candidate: TrackpadGestureOwnership = logScale < 0 ? .launcherRadialIn : .launcherRadialOut
        if pendingOwnership == candidate {
            pendingEvidenceFrames += 1
        } else {
            pendingOwnership = candidate
            pendingEvidenceFrames = 1
        }
        let evidenceFrames = abs(logScale) >= immediateScaleChange ? 1 : max(requiredEvidenceFrames, 1)
        guard pendingEvidenceFrames >= evidenceFrames else { return ownership }
        ownership = candidate
        return ownership
    }

    public mutating func ignoreUntilLift() {
        ownership = .ignoredUntilLift
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

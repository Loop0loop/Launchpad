public struct SystemTrackpadGestureSettings: Equatable, Sendable {
    public let fourFingerPinchEnabled: Bool
    public let fiveFingerPinchEnabled: Bool

    public init(fourFingerPinchEnabled: Bool, fiveFingerPinchEnabled: Bool) {
        self.fourFingerPinchEnabled = fourFingerPinchEnabled
        self.fiveFingerPinchEnabled = fiveFingerPinchEnabled
    }
}

public struct ResolvedTrackpadGesture: Equatable, Sendable {
    public let setting: String
    public let fingerCounts: [Int]
    public let conflicted: Bool
    public let shouldReserveNativePinch: Bool

    public var fingerCount: Int? { fingerCounts.first }

    public init(setting: String, fingerCount: Int?, conflicted: Bool = false, shouldReserveNativePinch: Bool = false) {
        self.init(
            setting: setting,
            fingerCounts: fingerCount.map { [$0] } ?? [],
            conflicted: conflicted,
            shouldReserveNativePinch: shouldReserveNativePinch
        )
    }

    public init(setting: String, fingerCounts: [Int], conflicted: Bool = false, shouldReserveNativePinch: Bool = false) {
        self.setting = setting
        self.fingerCounts = fingerCounts
        self.conflicted = conflicted
        self.shouldReserveNativePinch = shouldReserveNativePinch
    }
}

public enum TrackpadGestureResolver {
    public static let automatic = "Automatic"
    public static let pinch3 = "Pinch with 3 fingers"
    public static let pinch4 = "Pinch with 4 fingers"
    public static let pinch5 = "Pinch with 5 fingers"
    public static let legacyPinch = "Pinch with 4 or 5 fingers"
    public static let disabled = "Disabled"

    public static func resolve(preferred: String, system: SystemTrackpadGestureSettings) -> ResolvedTrackpadGesture {
        switch preferred {
        case disabled:
            return ResolvedTrackpadGesture(setting: disabled, fingerCount: nil)
        case pinch3:
            return ResolvedTrackpadGesture(setting: pinch3, fingerCount: 3)
        case pinch4:
            return ResolvedTrackpadGesture(
                setting: pinch4,
                fingerCount: 4,
                conflicted: system.fourFingerPinchEnabled || system.fiveFingerPinchEnabled,
                shouldReserveNativePinch: system.fourFingerPinchEnabled || system.fiveFingerPinchEnabled
            )
        case pinch5:
            return ResolvedTrackpadGesture(
                setting: pinch5,
                fingerCount: 5,
                conflicted: system.fiveFingerPinchEnabled,
                shouldReserveNativePinch: system.fiveFingerPinchEnabled
            )
        default:
            return automaticResolution(system: system)
        }
    }

    private static func automaticResolution(system: SystemTrackpadGestureSettings) -> ResolvedTrackpadGesture {
        ResolvedTrackpadGesture(
            setting: automatic,
            fingerCounts: [3, 4],
            conflicted: system.fourFingerPinchEnabled || system.fiveFingerPinchEnabled,
            shouldReserveNativePinch: system.fourFingerPinchEnabled || system.fiveFingerPinchEnabled
        )
    }
}

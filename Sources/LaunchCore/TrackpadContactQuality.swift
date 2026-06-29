public struct TrackpadTouchSample: Equatable, Sendable {
    public let id: Int32
    public let x: Double
    public let y: Double
    public let majorAxis: Double
    public let minorAxis: Double
    public let zTotal: Double

    public init(id: Int32, x: Double, y: Double, majorAxis: Double = 0, minorAxis: Double = 0, zTotal: Double = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.zTotal = zTotal
    }
}

public enum TrackpadContactQuality {
    public static func qualifiedPinchTouches(
        _ touches: [TrackpadTouchSample],
        requiredCount: Int = 4,
        maxContactCount: Int = 5
    ) -> [TrackpadTouchSample]? {
        guard touches.count >= requiredCount, touches.count <= maxContactCount else { return nil }
        return Array(touches.sorted { $0.id < $1.id }.prefix(requiredCount))
    }
}

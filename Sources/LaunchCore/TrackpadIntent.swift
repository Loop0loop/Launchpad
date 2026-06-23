public enum TrackpadIntent: Equatable {
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

    public static func isRecentFourFingerFrame(
        eventTime: Double,
        lastFourFingerTime: Double?,
        window: Double = 0.35
    ) -> Bool {
        guard let lastFourFingerTime else { return false }
        return eventTime >= lastFourFingerTime && eventTime - lastFourFingerTime <= window
    }
}

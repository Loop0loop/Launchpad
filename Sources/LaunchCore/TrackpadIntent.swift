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
}

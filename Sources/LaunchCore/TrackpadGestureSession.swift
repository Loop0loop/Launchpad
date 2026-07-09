public struct TrackpadGestureSession {
    private enum PinchState {
        case idle
        case tracking(
            initialRadius: Double,
            initialCenterX: Double?,
            initialCenterY: Double?,
            pendingIntent: TrackpadIntent?,
            lastIntent: TrackpadIntent?,
            lastProgressIntent: TrackpadIntent?,
            lastProgress: Double
        )
    }

    private var pinchState: PinchState = .idle
    private var scrollDeltaX = 0.0
    private var didFireScroll = false

    public init() {}

    /// Continuous pinch: emit progress while fingers move; commit/cancel only when `radius` becomes nil.
    public mutating func trackPinch(
        radius: Double?,
        centerX: Double? = nil,
        centerY: Double? = nil,
        timestamp _: Double,
        pinchInThreshold: Double = 0.9,
        pinchOutThreshold: Double = 1.1,
        immediatePinchInThreshold: Double = 0.82,
        immediatePinchOutThreshold: Double = 1.18,
        minimumPinchCenterTolerance: Double = 0.035,
        pinchCenterTravelRatio: Double = 1.0,
        commitProgress: Double = 0.45
    ) -> TrackpadPinchUpdate? {
        guard let radius, radius > 0 else {
            defer { pinchState = .idle }
            guard case .tracking(_, _, _, _, _, let lastProgressIntent, let lastProgress) = pinchState else {
                return nil
            }
            if let intent = lastProgressIntent, lastProgress >= commitProgress {
                return .commit(intent)
            }
            if lastProgressIntent != nil || lastProgress > 0 {
                return .cancel
            }
            return nil
        }

        switch pinchState {
        case .idle:
            pinchState = .tracking(
                initialRadius: radius,
                initialCenterX: centerX,
                initialCenterY: centerY,
                pendingIntent: nil,
                lastIntent: nil,
                lastProgressIntent: nil,
                lastProgress: 0
            )
            return nil
        case .tracking(
            let initialRadius,
            let initialCenterX,
            let initialCenterY,
            _,
            let lastIntent,
            let lastProgressIntent,
            let lastProgress
        ):
            guard initialRadius > 0 else {
                pinchState = .tracking(
                    initialRadius: radius,
                    initialCenterX: centerX,
                    initialCenterY: centerY,
                    pendingIntent: nil,
                    lastIntent: lastIntent,
                    lastProgressIntent: lastProgressIntent,
                    lastProgress: lastProgress
                )
                return nil
            }

            if let initialCenterX, let initialCenterY, let centerX, let centerY {
                let radiusDelta = abs(radius - initialRadius)
                let centerDeltaX = centerX - initialCenterX
                let centerDeltaY = centerY - initialCenterY
                let centerTravel = (centerDeltaX * centerDeltaX + centerDeltaY * centerDeltaY).squareRoot()
                guard centerTravel <= max(minimumPinchCenterTolerance, radiusDelta * pinchCenterTravelRatio) else {
                    return nil
                }
            }

            let ratio = radius / initialRadius
            let openProgress = TrackpadIntent.pinchOpenProgress(
                ratio: ratio,
                start: pinchInThreshold,
                full: immediatePinchInThreshold
            )
            let closeProgress = TrackpadIntent.pinchCloseProgress(
                ratio: ratio,
                start: pinchOutThreshold,
                full: immediatePinchOutThreshold
            )

            let intent: TrackpadIntent?
            let progress: Double
            if openProgress > 0 && openProgress >= closeProgress {
                intent = .open
                progress = openProgress
            } else if closeProgress > 0 {
                intent = .close
                progress = closeProgress
            } else {
                intent = nil
                progress = 0
            }

            pinchState = .tracking(
                initialRadius: initialRadius,
                initialCenterX: initialCenterX,
                initialCenterY: initialCenterY,
                pendingIntent: nil,
                lastIntent: lastIntent,
                lastProgressIntent: intent,
                lastProgress: progress
            )

            guard let intent else {
                if lastProgress > 0 {
                    return .tracking(intent: lastProgressIntent ?? .open, progress: 0)
                }
                return nil
            }
            return .tracking(intent: intent, progress: progress)
        }
    }

    public mutating func updatePinch(
        radius: Double?,
        centerX: Double? = nil,
        centerY: Double? = nil,
        timestamp _: Double,
        pinchInThreshold: Double = 0.9,
        pinchOutThreshold: Double = 1.1,
        immediatePinchInThreshold: Double = 0.82,
        immediatePinchOutThreshold: Double = 1.18,
        minimumPinchCenterTolerance: Double = 0.035,
        pinchCenterTravelRatio: Double = 1.0
    ) -> TrackpadIntent? {
        guard let radius, radius > 0 else {
            pinchState = .idle
            return nil
        }

        switch pinchState {
        case .idle:
            pinchState = .tracking(
                initialRadius: radius,
                initialCenterX: centerX,
                initialCenterY: centerY,
                pendingIntent: nil,
                lastIntent: nil,
                lastProgressIntent: nil,
                lastProgress: 0
            )
            return nil
        case .tracking(let initialRadius, let initialCenterX, let initialCenterY, let pendingIntent, let lastIntent, _, _):
            guard initialRadius > 0 else {
                pinchState = .tracking(
                    initialRadius: radius,
                    initialCenterX: centerX,
                    initialCenterY: centerY,
                    pendingIntent: nil,
                    lastIntent: lastIntent,
                    lastProgressIntent: nil,
                    lastProgress: 0
                )
                return nil
            }

            let ratio = radius / initialRadius
            guard let intent = TrackpadIntent.pinchRadius(
                    ratio: radius / initialRadius,
                    pinchInThreshold: pinchInThreshold,
                    pinchOutThreshold: pinchOutThreshold
                  ) else {
                pinchState = .tracking(
                    initialRadius: initialRadius,
                    initialCenterX: initialCenterX,
                    initialCenterY: initialCenterY,
                    pendingIntent: nil,
                    lastIntent: lastIntent,
                    lastProgressIntent: nil,
                    lastProgress: 0
                )
                return nil
            }

            guard intent != lastIntent else {
                pinchState = .tracking(
                    initialRadius: initialRadius,
                    initialCenterX: initialCenterX,
                    initialCenterY: initialCenterY,
                    pendingIntent: nil,
                    lastIntent: lastIntent,
                    lastProgressIntent: nil,
                    lastProgress: 0
                )
                return nil
            }

            if let initialCenterX, let initialCenterY, let centerX, let centerY {
                let radiusDelta = abs(radius - initialRadius)
                let centerDeltaX = centerX - initialCenterX
                let centerDeltaY = centerY - initialCenterY
                let centerTravel = (centerDeltaX * centerDeltaX + centerDeltaY * centerDeltaY).squareRoot()
                guard centerTravel <= max(minimumPinchCenterTolerance, radiusDelta * pinchCenterTravelRatio) else {
                    pinchState = .tracking(
                        initialRadius: initialRadius,
                        initialCenterX: initialCenterX,
                        initialCenterY: initialCenterY,
                        pendingIntent: nil,
                        lastIntent: lastIntent,
                        lastProgressIntent: nil,
                        lastProgress: 0
                    )
                    return nil
                }
            }

            func trackingState(pendingIntent: TrackpadIntent?, lastIntent: TrackpadIntent?) -> PinchState {
                .tracking(
                    initialRadius: initialRadius,
                    initialCenterX: initialCenterX,
                    initialCenterY: initialCenterY,
                    pendingIntent: pendingIntent,
                    lastIntent: lastIntent,
                    lastProgressIntent: nil,
                    lastProgress: 0
                )
            }

            let isImmediate = ratio <= immediatePinchInThreshold || ratio >= immediatePinchOutThreshold
            if isImmediate {
                pinchState = trackingState(pendingIntent: nil, lastIntent: intent)
                return intent
            }

            guard pendingIntent == intent else {
                pinchState = trackingState(pendingIntent: intent, lastIntent: lastIntent)
                return nil
            }

            pinchState = trackingState(pendingIntent: nil, lastIntent: intent)
            return intent
        }
    }

    public mutating func updateHorizontalScroll(
        deltaX: Double,
        deltaY: Double,
        ended: Bool = false,
        threshold: Double = 30,
        dominanceRatio: Double = 1.25
    ) -> TrackpadIntent? {
        if ended {
            scrollDeltaX = 0
            didFireScroll = false
            return nil
        }

        guard !didFireScroll else { return nil }
        guard abs(deltaX) > abs(deltaY) * dominanceRatio else { return nil }

        scrollDeltaX += deltaX
        guard abs(scrollDeltaX) >= threshold else { return nil }

        didFireScroll = true
        return scrollDeltaX < 0 ? .nextPage : .previousPage
    }
}

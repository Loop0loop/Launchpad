public struct TrackpadGestureSession {
    private enum PinchState {
        case idle
        case tracking(
            initialRadius: Double,
            initialCenterX: Double?,
            initialCenterY: Double?,
            pendingIntent: TrackpadIntent?,
            lastIntent: TrackpadIntent?
        )
    }

    private var pinchState: PinchState = .idle
    private var scrollDeltaX = 0.0
    private var didFireScroll = false

    public init() {}

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
                lastIntent: nil
            )
            return nil
        case .tracking(let initialRadius, let initialCenterX, let initialCenterY, let pendingIntent, let lastIntent):
            guard initialRadius > 0 else {
                pinchState = .tracking(
                    initialRadius: radius,
                    initialCenterX: centerX,
                    initialCenterY: centerY,
                    pendingIntent: nil,
                    lastIntent: lastIntent
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
                    lastIntent: lastIntent
                )
                return nil
            }

            guard intent != lastIntent else {
                pinchState = .tracking(
                    initialRadius: initialRadius,
                    initialCenterX: initialCenterX,
                    initialCenterY: initialCenterY,
                    pendingIntent: nil,
                    lastIntent: lastIntent
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
                        lastIntent: lastIntent
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
                    lastIntent: lastIntent
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

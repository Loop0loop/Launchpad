public struct TrackpadGesturePreferenceSnapshot: Equatable, Sendable {
    public let values: [String: Int?]

    public init(values: [String: Int?]) {
        self.values = values
    }

    public var reserveWrites: [String: Int] {
        Dictionary(uniqueKeysWithValues: values.keys.map { ($0, 0) })
    }

    public var restoreWrites: [String: Int?] {
        values
    }

    public var restoreNotificationNames: [String] {
        [
            "com.apple.AppleMultitouchTrackpadDomainDidChangeNotification",
            "com.apple.AppleMenuGesturesDidChangeNotification"
        ]
    }

    public var restoreLaunchAgentLabels: [String] {
        ["com.apple.Dock.agent"]
    }
}

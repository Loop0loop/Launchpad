public struct TrackpadGesturePreferenceSnapshot: Equatable, Sendable {
    public static let nativeAppsGestureKey = "showSpotlightGestureEnabled"
    public static let nativeShowDesktopGestureKey = "showDesktopGestureEnabled"
    public let values: [String: Int?]

    public init(values: [String: Int?]) {
        self.values = values
    }

    public var reserveWrites: [String: Int] {
        Dictionary(uniqueKeysWithValues: values.keys.map { key in
            (key, key == Self.nativeShowDesktopGestureKey ? 1 : 0)
        })
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

import Foundation
import LaunchpadCore

enum SystemTrackpadSettings {
    static func load() -> SystemTrackpadGestureSettings {
        SystemTrackpadGestureSettings(
            fourFingerPinchEnabled: bool("TrackpadFourFingerPinchGesture"),
            fiveFingerPinchEnabled: bool("TrackpadFiveFingerPinchGesture")
        )
    }

    static func reserveNativeLaunchpadPinch() {
        for domain in [
            "com.apple.AppleMultitouchTrackpad",
            "com.apple.driver.AppleBluetoothMultitouch.trackpad"
        ] {
            write(0, key: "TrackpadFourFingerPinchGesture", domain: domain)
            write(0, key: "TrackpadFiveFingerPinchGesture", domain: domain)
            CFPreferencesAppSynchronize(domain as CFString)
        }
    }

    private static func bool(_ key: String) -> Bool {
        int(key, domain: "com.apple.AppleMultitouchTrackpad") > 0
            || int(key, domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad") > 0
    }

    private static func int(_ key: String, domain: String) -> Int {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        return (value as? NSNumber)?.intValue ?? 0
    }

    private static func write(_ value: Int, key: String, domain: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFNumber, domain as CFString)
    }
}

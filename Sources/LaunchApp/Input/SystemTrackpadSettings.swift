import Foundation
import LaunchpadCore

enum SystemTrackpadSettings {
    private static let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad"
    ]

    private static let launchpadGestureKeys = [
        "TrackpadFourFingerPinchGesture",
        "TrackpadFiveFingerPinchGesture",
        "com.apple.trackpad.fourFingerPinchSwipeGesture",
        "com.apple.trackpad.fiveFingerPinchSwipeGesture"
    ]

    static func load() -> SystemTrackpadGestureSettings {
        SystemTrackpadGestureSettings(
            fourFingerPinchEnabled: bool("TrackpadFourFingerPinchGesture") || bool("com.apple.trackpad.fourFingerPinchSwipeGesture"),
            fiveFingerPinchEnabled: bool("TrackpadFiveFingerPinchGesture") || bool("com.apple.trackpad.fiveFingerPinchSwipeGesture")
        )
    }

    static func reserveNativeLaunchpadPinch() {
        for domain in domains {
            for key in launchpadGestureKeys {
                write(0, key: key, domain: domain)
            }
            CFPreferencesAppSynchronize(domain as CFString)
        }
        applySystemSettings()
    }

    private static func bool(_ key: String) -> Bool {
        domains.contains { int(key, domain: $0) > 0 }
    }

    private static func int(_ key: String, domain: String) -> Int {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        return (value as? NSNumber)?.intValue ?? 0
    }

    private static func write(_ value: Int, key: String, domain: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFNumber, domain as CFString)
    }

    private static func applySystemSettings() {
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-u"]
        try? process.run()
    }
}

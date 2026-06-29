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
    private static let currentHostLaunchpadGestureDefaults = [
        "com.apple.trackpad.fourFingerPinchSwipeGesture": 2,
        "com.apple.trackpad.fiveFingerPinchSwipeGesture": 2
    ]

    static func load() -> SystemTrackpadGestureSettings {
        SystemTrackpadGestureSettings(
            fourFingerPinchEnabled: bool("TrackpadFourFingerPinchGesture")
                || bool("com.apple.trackpad.fourFingerPinchSwipeGesture")
                || currentHostGlobalInt("com.apple.trackpad.fourFingerPinchSwipeGesture") > 0,
            fiveFingerPinchEnabled: bool("TrackpadFiveFingerPinchGesture")
                || bool("com.apple.trackpad.fiveFingerPinchSwipeGesture")
                || currentHostGlobalInt("com.apple.trackpad.fiveFingerPinchSwipeGesture") > 0
        )
    }

    static func reserveNativeLaunchpadPinch() {
        for domain in domains {
            for key in launchpadGestureKeys {
                write(0, key: key, domain: domain)
            }
            CFPreferencesAppSynchronize(domain as CFString)
        }
        for key in currentHostLaunchpadGestureDefaults.keys {
            writeCurrentHostGlobal(0, key: key)
        }
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        applySystemSettings()
    }

    static func restoreNativeLaunchpadPinch() {
        for domain in domains {
            for key in launchpadGestureKeys {
                write(1, key: key, domain: domain)
            }
            CFPreferencesAppSynchronize(domain as CFString)
        }
        for (key, value) in currentHostLaunchpadGestureDefaults {
            writeCurrentHostGlobal(value, key: key)
        }
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
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

    private static func currentHostGlobalInt(_ key: String) -> Int {
        let value = CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return (value as? NSNumber)?.intValue ?? 0
    }

    private static func writeCurrentHostGlobal(_ value: Int, key: String) {
        CFPreferencesSetValue(
            key as CFString,
            value as CFNumber,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private static func applySystemSettings() {
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-u"]
        try? process.run()
        process.waitUntilExit()
    }
}

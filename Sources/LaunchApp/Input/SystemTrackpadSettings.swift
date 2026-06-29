import Foundation
import LaunchpadCore

enum SystemTrackpadSettings {
    private static let snapshotDefaultsKey = "systemTrackpadSettings.nativeLaunchpadPinchSnapshot"
    private static let dockDomain = "com.apple.dock"
    private static let showDesktopGestureKey = "showDesktopGestureEnabled"
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
    private static let currentHostLaunchpadGestureKeys = [
        "com.apple.trackpad.fourFingerPinchSwipeGesture",
        "com.apple.trackpad.fiveFingerPinchSwipeGesture"
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
        saveSnapshot()
        for domain in domains {
            for (key, value) in TrackpadGesturePreferenceSnapshot(values: appValues(domain: domain)).reserveWrites {
                write(value, key: key, domain: domain)
            }
            CFPreferencesAppSynchronize(domain as CFString)
        }
        for (key, value) in TrackpadGesturePreferenceSnapshot(values: currentHostValues()).reserveWrites {
            writeCurrentHostGlobal(value, key: key)
        }
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        applySystemSettings()
    }

    static func restoreNativeLaunchpadPinch() {
        guard let snapshot = loadSnapshot() else {
            refreshNativeGestureRegistrations(showDesktopOriginalValue: optionalInt(showDesktopGestureKey, domain: dockDomain))
            return
        }
        var notificationNames: [String] = []
        var launchAgentLabels: [String] = []
        for domain in domains {
            let values = snapshot[appScope(domain)] ?? defaultAppRestoreValues()
            let restorePlan = TrackpadGesturePreferenceSnapshot(values: values)
            notificationNames = restorePlan.restoreNotificationNames
            launchAgentLabels = restorePlan.restoreLaunchAgentLabels
            for (key, value) in restorePlan.restoreWrites {
                write(value, key: key, domain: domain)
            }
            CFPreferencesAppSynchronize(domain as CFString)
        }
        let currentHost = snapshot[currentHostScope] ?? defaultCurrentHostRestoreValues()
        for (key, value) in TrackpadGesturePreferenceSnapshot(values: currentHost).restoreWrites {
            writeCurrentHostGlobal(value, key: key)
        }
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        UserDefaults.standard.removeObject(forKey: snapshotDefaultsKey)
        applySystemSettings()
        postNotifications(notificationNames)
        refreshNativeGestureRegistrations(
            showDesktopOriginalValue: snapshot[dockScope]?[showDesktopGestureKey] ?? nil,
            launchAgentLabels: launchAgentLabels
        )
    }

    private static func bool(_ key: String) -> Bool {
        domains.contains { int(key, domain: $0) > 0 }
    }

    private static func int(_ key: String, domain: String) -> Int {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        return (value as? NSNumber)?.intValue ?? 0
    }

    private static func appValues(domain: String) -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: launchpadGestureKeys.map { ($0, optionalInt($0, domain: domain)) })
    }

    private static func currentHostValues() -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: currentHostLaunchpadGestureKeys.map { ($0, optionalCurrentHostGlobalInt($0)) })
    }

    private static func defaultAppRestoreValues() -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: launchpadGestureKeys.map { ($0, 1) })
    }

    private static func defaultCurrentHostRestoreValues() -> [String: Int?] {
        [
            "com.apple.trackpad.fourFingerPinchSwipeGesture": 2,
            "com.apple.trackpad.fiveFingerPinchSwipeGesture": 2
        ]
    }

    private static func write(_ value: Int?, key: String, domain: String) {
        CFPreferencesSetAppValue(key as CFString, value.map { $0 as CFNumber }, domain as CFString)
    }

    private static func currentHostGlobalInt(_ key: String) -> Int {
        optionalCurrentHostGlobalInt(key) ?? 0
    }

    private static func optionalInt(_ key: String, domain: String) -> Int? {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        return (value as? NSNumber)?.intValue
    }

    private static func optionalCurrentHostGlobalInt(_ key: String) -> Int? {
        let value = CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return (value as? NSNumber)?.intValue
    }

    private static func writeCurrentHostGlobal(_ value: Int?, key: String) {
        CFPreferencesSetValue(
            key as CFString,
            value.map { $0 as CFNumber },
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private static var currentHostScope: String { "currentHost" }
    private static var dockScope: String { "dock" }

    private static func appScope(_ domain: String) -> String {
        "app:\(domain)"
    }

    private static func saveSnapshot() {
        guard loadSnapshot() == nil else { return }
        var snapshot: [String: [String: Int?]] = [
            currentHostScope: currentHostValues(),
            dockScope: [showDesktopGestureKey: optionalInt(showDesktopGestureKey, domain: dockDomain)]
        ]
        for domain in domains {
            snapshot[appScope(domain)] = appValues(domain: domain)
        }
        let data = try? JSONEncoder().encode(snapshot.mapValues { values in
            values.mapValues { $0.map(String.init) ?? "" }
        })
        UserDefaults.standard.set(data, forKey: snapshotDefaultsKey)
    }

    private static func loadSnapshot() -> [String: [String: Int?]]? {
        guard let data = UserDefaults.standard.data(forKey: snapshotDefaultsKey),
              let stored = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return nil }
        return stored.mapValues { values in
            values.mapValues { $0.isEmpty ? nil : Int($0) }
        }
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

    private static func postNotifications(_ notificationNames: [String]) {
        for notificationName in notificationNames {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/notifyutil")
            process.arguments = ["-p", notificationName]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static func pulseShowDesktopGesture(originalValue: Int?) {
        guard originalValue == 1 else { return }
        write(0, key: showDesktopGestureKey, domain: dockDomain)
        CFPreferencesAppSynchronize(dockDomain as CFString)
        write(originalValue, key: showDesktopGestureKey, domain: dockDomain)
        CFPreferencesAppSynchronize(dockDomain as CFString)
        postNotifications([
            "com.apple.AppleMenuGesturesDidChangeNotification",
            "com.apple.AppleMultitouchTrackpadDomainDidChangeNotification"
        ])
    }

    private static func refreshNativeGestureRegistrations(
        showDesktopOriginalValue: Int?,
        launchAgentLabels: [String] = ["com.apple.Dock.agent"]
    ) {
        postNotifications([
            "com.apple.AppleMultitouchTrackpadDomainDidChangeNotification",
            "com.apple.AppleMenuGesturesDidChangeNotification"
        ])
        pulseShowDesktopGesture(originalValue: showDesktopOriginalValue)
        kickstartLaunchAgents(labels: launchAgentLabels)
    }

    private static func kickstartLaunchAgents(labels: [String]) {
        let uid = getuid()
        for label in labels {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["kickstart", "-k", "gui/\(uid)/\(label)"]
            try? process.run()
            process.waitUntilExit()
        }
    }
}

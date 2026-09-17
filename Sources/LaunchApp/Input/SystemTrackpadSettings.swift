import Foundation
import LaunchpadCore

enum SystemTrackpadSettings {
    private static let snapshotDefaultsKey = "systemTrackpadSettings.nativeLaunchpadPinchSnapshot"
    private static let dockDomain = "com.apple.dock"
    private static let appsSnapshotKey = "systemTrackpadSettings.nativeAppsGestureSnapshot.v27"
    private static let legacyAppsSnapshotKey = "systemTrackpadSettings.nativeAppsGestureSnapshot"
    private static let legacyShowAppsGestureKey = "showLaunchpadGestureEnabled"
    private static let showAppsGestureKey = TrackpadGesturePreferenceSnapshot.nativeAppsGestureKey
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
    private static let missionControlGestureKeys = ["TrackpadFourFingerVertSwipeGesture"]
    private static let currentHostMissionControlGestureKeys = ["com.apple.trackpad.fourFingerVertSwipeGesture"]
    static func load() -> SystemTrackpadGestureSettings {
        let appsEnabled = userAppsGestureEnabled
        return SystemTrackpadGestureSettings(
            fourFingerPinchEnabled: appsEnabled && (effectiveBool("TrackpadFourFingerPinchGesture")
                || effectiveBool("com.apple.trackpad.fourFingerPinchSwipeGesture")
                || effectiveCurrentHostInt("com.apple.trackpad.fourFingerPinchSwipeGesture") > 0),
            fiveFingerPinchEnabled: appsEnabled && (effectiveBool("TrackpadFiveFingerPinchGesture")
                || effectiveBool("com.apple.trackpad.fiveFingerPinchSwipeGesture")
                || effectiveCurrentHostInt("com.apple.trackpad.fiveFingerPinchSwipeGesture") > 0)
        )
    }

    private static var userAppsGestureEnabled: Bool {
        if let original = UserDefaults.standard.string(forKey: appsSnapshotKey) {
            return original == "missing" || (Int(original) ?? 0) != 0
        }
        if let dockValues = loadSnapshot()?[dockScope],
           dockValues.keys.contains(showAppsGestureKey) {
            return (dockValues[showAppsGestureKey] ?? nil).map { $0 != 0 } ?? true
        }
        return (optionalInt(showAppsGestureKey, domain: dockDomain) ?? 1) != 0
    }

    static var isShowDesktopGestureEnabled: Bool {
        int(showDesktopGestureKey, domain: dockDomain) > 0
    }

    @discardableResult
    static func reserveNativeLaunchpadPinch() -> Bool {
        saveSnapshot()
        for domain in domains {
            let plan = TrackpadGesturePreferenceSnapshot(values: launchpadValues(domain: domain))
            for (key, value) in plan.reserveWrites { write(value, key: key, domain: domain) }
            CFPreferencesAppSynchronize(domain as CFString)
        }
        for (key, value) in TrackpadGesturePreferenceSnapshot(values: currentHostLaunchpadValues()).reserveWrites {
            writeCurrentHostGlobal(value, key: key)
        }
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        let dockPlan = TrackpadGesturePreferenceSnapshot(values: dockValues())
        for (key, value) in dockPlan.reserveWrites { write(value, key: key, domain: dockDomain) }
        CFPreferencesAppSynchronize(dockDomain as CFString)
        applySystemSettings()
        refreshNativeGestureRegistrations(showDesktopOriginalValue: 1)
        let reserved = optionalInt(showAppsGestureKey, domain: dockDomain) == 0
            && optionalInt(showDesktopGestureKey, domain: dockDomain) == 1
            && !physicalPinchIsEnabled
        LaunchLog.line("exclusive pinch reserved=\(reserved); Apps disabled; Dock Show Desktop action enabled")
        return reserved
    }

    static func suppressMissionControlGesture() {
        setMissionControlGestureSuppressed(true)
    }

    static func restoreMissionControlGesture() {
        setMissionControlGestureSuppressed(false)
    }

    static func restoreNativeLaunchpadPinch(refreshRegistrationsIfNeeded: Bool = false) {
        if let original = UserDefaults.standard.string(forKey: legacyAppsSnapshotKey) {
            write(Int(original), key: legacyShowAppsGestureKey, domain: dockDomain)
            CFPreferencesAppSynchronize(dockDomain as CFString)
            UserDefaults.standard.removeObject(forKey: legacyAppsSnapshotKey)
        }
        if let original = UserDefaults.standard.string(forKey: appsSnapshotKey) {
            write(Int(original), key: showAppsGestureKey, domain: dockDomain)
            CFPreferencesAppSynchronize(dockDomain as CFString)
            applySystemSettings()
            refreshNativeGestureRegistrations(showDesktopOriginalValue: nil)
            UserDefaults.standard.removeObject(forKey: appsSnapshotKey)
        }
        // Restore the exclusive reservation; older snapshots may omit the Dock Apps key.
        guard let snapshot = loadSnapshot() else {
            guard refreshRegistrationsIfNeeded else { return }
            let showDesktopValue = optionalInt(showDesktopGestureKey, domain: dockDomain)
            LaunchLog.line("refresh native trackpad registrations showDesktop=\(showDesktopValue ?? -1)")
            refreshNativeGestureRegistrations(showDesktopOriginalValue: showDesktopValue)
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
        let dock = snapshot[dockScope] ?? [:]
        for (key, value) in TrackpadGesturePreferenceSnapshot(values: dock).restoreWrites {
            write(value, key: key, domain: dockDomain)
        }
        CFPreferencesAppSynchronize(dockDomain as CFString)
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

    private static var physicalPinchIsEnabled: Bool {
        launchpadGestureKeys.contains { bool($0) }
            || currentHostLaunchpadGestureKeys.contains { currentHostGlobalInt($0) > 0 }
    }

    private static func effectiveBool(_ key: String) -> Bool {
        guard let snapshot = loadSnapshot() else { return bool(key) }
        return domains.contains { domain in
            let values = snapshot[appScope(domain)]
            return values?.keys.contains(key) == true
                ? (values?[key] ?? nil).map { $0 > 0 } ?? false
                : int(key, domain: domain) > 0
        }
    }

    private static func effectiveCurrentHostInt(_ key: String) -> Int {
        guard let values = loadSnapshot()?[currentHostScope],
              values.keys.contains(key),
              let stored = values[key] else { return currentHostGlobalInt(key) }
        return stored ?? 0
    }

    private static func int(_ key: String, domain: String) -> Int {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        return (value as? NSNumber)?.intValue ?? 0
    }

    private static func defaultAppRestoreValues() -> [String: Int?] {
        Dictionary(uniqueKeysWithValues:
            launchpadGestureKeys.map { ($0, 1) }
                + missionControlGestureKeys.map { ($0, 2) }
        )
    }

    private static func appValues(domain: String) -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: (launchpadGestureKeys + missionControlGestureKeys).map {
            ($0, optionalInt($0, domain: domain))
        })
    }

    private static func launchpadValues(domain: String) -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: launchpadGestureKeys.map {
            ($0, optionalInt($0, domain: domain))
        })
    }

    private static func currentHostValues() -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: (currentHostLaunchpadGestureKeys + currentHostMissionControlGestureKeys).map {
            ($0, optionalCurrentHostGlobalInt($0))
        })
    }

    private static func currentHostLaunchpadValues() -> [String: Int?] {
        Dictionary(uniqueKeysWithValues: currentHostLaunchpadGestureKeys.map {
            ($0, optionalCurrentHostGlobalInt($0))
        })
    }

    private static func dockValues() -> [String: Int?] {
        [
            showAppsGestureKey: optionalInt(showAppsGestureKey, domain: dockDomain),
            showDesktopGestureKey: optionalInt(showDesktopGestureKey, domain: dockDomain)
        ]
    }

    private static func defaultCurrentHostRestoreValues() -> [String: Int?] {
        [
            "com.apple.trackpad.fourFingerPinchSwipeGesture": 2,
            "com.apple.trackpad.fiveFingerPinchSwipeGesture": 2,
            "com.apple.trackpad.fourFingerVertSwipeGesture": 2
        ]
    }

    private static func setMissionControlGestureSuppressed(_ suppressed: Bool) {
        guard let snapshot = loadSnapshot() else { return }
        var changed = false
        for domain in domains {
            let original = snapshot[appScope(domain)] ?? defaultAppRestoreValues()
            for key in missionControlGestureKeys {
                let target = suppressed ? 0 : original[key] ?? nil
                guard optionalInt(key, domain: domain) != target else { continue }
                write(target, key: key, domain: domain)
                changed = true
            }
            CFPreferencesAppSynchronize(domain as CFString)
        }
        let original = snapshot[currentHostScope] ?? defaultCurrentHostRestoreValues()
        for key in currentHostMissionControlGestureKeys {
            let target = suppressed ? 0 : original[key] ?? nil
            guard optionalCurrentHostGlobalInt(key) != target else { continue }
            writeCurrentHostGlobal(target, key: key)
            changed = true
        }
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        guard changed else { return }
        applySystemSettings()
        postNotifications([
            "com.apple.AppleMultitouchTrackpadDomainDidChangeNotification",
            "com.apple.AppleMenuGesturesDidChangeNotification"
        ])
        LaunchLog.line("Mission Control gesture suppressed=\(suppressed)")
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

    private static func loadSnapshot() -> [String: [String: Int?]]? {
        guard let data = UserDefaults.standard.data(forKey: snapshotDefaultsKey),
              let stored = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return nil }
        return stored.mapValues { values in
            values.mapValues { $0.isEmpty ? nil : Int($0) }
        }
    }

    private static func saveSnapshot() {
        guard loadSnapshot() == nil else { return }
        var snapshot: [String: [String: Int?]] = [
            currentHostScope: currentHostValues(),
            dockScope: dockValues()
        ]
        for domain in domains { snapshot[appScope(domain)] = appValues(domain: domain) }
        let data = try? JSONEncoder().encode(snapshot.mapValues { values in
            values.mapValues { $0.map(String.init) ?? "" }
        })
        UserDefaults.standard.set(data, forKey: snapshotDefaultsKey)
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

import LaunchpadCore

extension AppState {
    func refreshLoginItemStatus() {
        launchAtLogin = LoginItemAdapter.isEnabled
        if launchAtLogin {
            loginItemError = nil
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil

        do {
            try LoginItemAdapter.setEnabled(enabled)
        } catch {
            loginItemError = error.localizedDescription
        }

        refreshLoginItemStatus()
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityAdapter.isTrusted
        accessibilityState = accessibilityTrusted ? .allowed : .required
    }

    func requestAccessibilityPermission() {
        guard !AccessibilityAdapter.isTrusted else {
            refreshAccessibilityStatus()
            return
        }
        accessibilityTrusted = AccessibilityAdapter.requestPermission()
        accessibilityState = accessibilityTrusted ? .allowed : .needsApproval
    }

    func setTrackpadGateActive(_ isActive: Bool, conflicted: Bool = false) {
        trackpadGateState = isActive && !conflicted ? .exactPinch : .fallbackPinch
    }

    func applyResolvedTrackpadGesture(_ resolved: ResolvedTrackpadGesture) {
        trackpadGateState = resolved.conflicted ? .fallbackPinch : trackpadGateState
    }

    func setGlobalHotKeyActive(_ isActive: Bool) {
        globalHotKeyState = isActive ? .allowed : .required
    }

    func setF4KeyActive(_ isActive: Bool) {
        f4KeyState = isActive ? .allowed : .required
    }
}

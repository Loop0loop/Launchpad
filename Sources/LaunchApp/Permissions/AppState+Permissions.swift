extension AppState {
    func refreshLoginItemStatus() {
        launchAtLogin = LoginItemAdapter.isEnabled
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
        accessibilityTrusted = AccessibilityAdapter.requestPermission()
        accessibilityState = accessibilityTrusted ? .allowed : .needsApproval
    }

    func setTrackpadGateActive(_ isActive: Bool) {
        trackpadGateState = isActive ? .exactPinch : .fallbackPinch
    }

    func setGlobalHotKeyActive(_ isActive: Bool) {
        globalHotKeyState = isActive ? .allowed : .required
    }

    func setF4KeyActive(_ isActive: Bool) {
        f4KeyState = isActive ? .allowed : .required
    }
}

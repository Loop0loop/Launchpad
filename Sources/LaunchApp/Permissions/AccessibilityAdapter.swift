import ApplicationServices

enum AccessibilityAdapter {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

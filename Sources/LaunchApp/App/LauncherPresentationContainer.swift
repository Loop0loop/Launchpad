import AppKit

/// Nonactivating panel: takes keyboard focus (search / type-ahead) and receives drags
/// without activating the app or stealing focus from the frontmost app. This is the
/// proper overlay window type for a Launchpad-style launcher (cf. macos-launchy).
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosts SwiftUI content without breaking hit testing inside `NSHostingView`.
final class LauncherPresentationContainer: NSView {
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        for subview in subviews {
            subview.frame = bounds
        }
    }
}

import AppKit

/// Hosts SwiftUI content and receives open/close scale animation without breaking hit testing inside `NSHostingView`.
final class LauncherPresentationContainer: NSView {
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        for subview in subviews {
            subview.frame = bounds
        }
        updateLayerPosition()
    }

    func updateLayerPosition() {
        guard wantsLayer, let layer else { return }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

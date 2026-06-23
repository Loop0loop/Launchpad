import AppKit

@MainActor
final class HotCornerMonitor {
    private var timer: Timer?
    private var lastTrigger = Date.distantPast

    func start(action: @escaping @MainActor () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: LaunchConstants.HotCorner.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPointerInTopLeftCorner(), self.canTrigger else { return }
                self.lastTrigger = Date()
                action()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var canTrigger: Bool {
        Date().timeIntervalSince(lastTrigger) >= LaunchConstants.HotCorner.cooldown
    }

    private func isPointerInTopLeftCorner() -> Bool {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            let frame = screen.frame
            return location.x >= frame.minX
                && location.x <= frame.minX + LaunchConstants.HotCorner.activationSize
                && location.y <= frame.maxY
                && location.y >= frame.maxY - LaunchConstants.HotCorner.activationSize
        }
    }
}

import AppKit
import LaunchCore

@MainActor
final class LauncherLifecycle {
    private let state: AppState
    private let window: NSWindow
    private var previousApp: NSRunningApplication?
    private var dismissToken = 0

    init(state: AppState, window: NSWindow) {
        self.state = state
        self.window = window
    }

    var isVisible: Bool {
        window.isVisible
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        dismissToken += 1
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = frontmost
        }

        state.query = ""
        window.setFrame(NSScreen.main?.frame ?? window.frame, display: true)
        window.alphaValue = 0
        state.launcherVisible = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.launcherVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        animatedDismiss {
            if #available(macOS 14.0, *) {
                self.previousApp?.activate()
            } else {
                self.previousApp?.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    func animatedDismiss(completion: (@MainActor @Sendable () -> Void)? = nil) {
        dismissToken += 1
        let token = dismissToken
        state.launcherVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                guard token == self.dismissToken else { return }
                self.dismiss()
                self.window.alphaValue = 1
                completion?()
            }
        }
    }

    func dismiss() {
        state.launcherVisible = false
        window.orderOut(nil)
    }

    func launch(_ app: LaunchApp) {
        AppSystemAdapter.launch(app)
        animatedDismiss()
    }
}

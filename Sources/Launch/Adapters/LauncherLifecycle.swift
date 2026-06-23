import AppKit
import LaunchCore

@MainActor
final class LauncherLifecycle {
    private let state: AppState
    private let window: NSWindow
    private var previousApp: NSRunningApplication?
    private var isAnimating = false

    init(state: AppState, window: NSWindow) {
        self.state = state
        self.window = window
    }

    var isVisible: Bool {
        window.isVisible && window.alphaValue > 0.01
    }

    func toggle() {
        guard !isAnimating else { return }
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard !isAnimating else { return }
        if isVisible { return }

        rememberPreviousApp()
        state.query = ""
        state.openFolder = nil
        state.clearSelection()

        window.setFrame(NSScreen.main?.frame ?? window.frame, display: true)
        window.alphaValue = 0
        window.contentView?.alphaValue = 0
        state.launcherVisible = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        animateWindow(to: 1)
    }

    func hide() {
        guard !isAnimating, window.isVisible else { return }
        animateWindow(to: 0, restorePreviousApp: true)
    }

    func dismiss() {
        state.launcherVisible = false
        window.orderOut(nil)
        resetWindowAlpha()
    }

    func launch(_ app: LaunchApp) {
        guard !isAnimating else {
            AppSystemAdapter.launch(app)
            dismiss()
            return
        }
        AppSystemAdapter.launch(app)
        animateWindow(to: 0, restorePreviousApp: false)
    }

    func revealInFinder(_ app: LaunchApp) {
        dismiss()
        AppSystemAdapter.showInFinder(app)
    }

    private func animateWindow(to targetAlpha: CGFloat, restorePreviousApp: Bool = false) {
        isAnimating = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = LaunchConstants.Lifecycle.windowDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = targetAlpha
            window.contentView?.animator().alphaValue = targetAlpha
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.window.alphaValue = targetAlpha
                self.window.contentView?.alphaValue = targetAlpha
                self.isAnimating = false

                if targetAlpha <= 0.01 {
                    self.state.launcherVisible = false
                    self.window.orderOut(nil)
                    self.resetWindowAlpha()
                    if restorePreviousApp {
                        self.activatePreviousApp()
                    }
                }
            }
        }
    }

    private func resetWindowAlpha() {
        window.alphaValue = 1
        window.contentView?.alphaValue = 1
    }

    private func rememberPreviousApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = frontmost
        }
    }

    private func activatePreviousApp() {
        if #available(macOS 14.0, *) {
            previousApp?.activate()
        } else {
            previousApp?.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

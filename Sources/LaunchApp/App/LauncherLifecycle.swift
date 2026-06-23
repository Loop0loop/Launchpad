import AppKit
import LaunchCore

@MainActor
final class LauncherLifecycle {
    private let state: AppState
    private let window: NSWindow
    private var previousApp: NSRunningApplication?
    private var isAnimating = false
    private var menuBarHidden = false

    init(state: AppState, window: NSWindow) {
        self.state = state
        self.window = window
    }

    var isVisible: Bool {
        window.isVisible && (state.launcherVisible || isAnimating)
    }

    func toggle() {
        LaunchLog.line("lifecycle toggle visible=\(isVisible) animating=\(isAnimating)")
        guard !isAnimating else {
            LaunchLog.line("lifecycle toggle ignored: animating")
            return
        }
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        LaunchLog.line("lifecycle show requested visible=\(isVisible) animating=\(isAnimating)")
        guard !isAnimating else {
            LaunchLog.line("lifecycle show ignored: animating")
            return
        }
        if isVisible {
            LaunchLog.line("lifecycle show ignored: already visible")
            return
        }

        rememberPreviousApp()
        state.query = ""
        state.openFolder = nil
        state.clearSelection()

        applyWindowBrowsingMode()
        resetWindowAlpha()
        state.launcherVisible = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        LaunchLog.line("window ordered front frame=\(window.frame) screen=\(String(describing: NSScreen.main?.frame))")

        isAnimating = true
        DispatchQueue.main.async {
            self.state.launcherVisible = true
            self.finishPresentation(after: LaunchConstants.Lifecycle.windowDuration) {
                self.isAnimating = false
            }
        }
    }

    func hide() {
        LaunchLog.line("lifecycle hide requested visible=\(window.isVisible) animating=\(isAnimating)")
        guard !isAnimating, window.isVisible else {
            LaunchLog.line("lifecycle hide ignored")
            return
        }
        animatePresentation(visible: false, restorePreviousApp: true)
    }

    func dismiss() {
        setMenuBarHidden(false)
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
        animatePresentation(visible: false, restorePreviousApp: false)
    }

    func revealInFinder(_ app: LaunchApp) {
        dismiss()
        AppSystemAdapter.showInFinder(app)
    }

    func applyWindowBrowsingMode() {
        let screenFrame = NSScreen.main?.frame ?? window.frame
        window.setFrame(state.windowBrowsingMode ? windowedFrame(in: screenFrame) : screenFrame, display: true)
        updateWindowChrome()
        LaunchLog.line("apply window mode windowed=\(state.windowBrowsingMode) frame=\(window.frame)")
        guard state.launcherVisible || window.isVisible else {
            window.level = state.windowBrowsingMode ? .normal : .mainMenu
            return
        }
        setMenuBarHidden(!state.windowBrowsingMode)
    }

    private func animatePresentation(visible: Bool, restorePreviousApp: Bool) {
        LaunchLog.line("animate presentation visible=\(visible) restore=\(restorePreviousApp)")
        isAnimating = true
        state.launcherVisible = false
        finishPresentation(after: LaunchConstants.Lifecycle.windowDuration) {
            if !visible {
                self.setMenuBarHidden(false)
                self.window.orderOut(nil)
                self.resetWindowAlpha()
                if restorePreviousApp {
                    self.activatePreviousApp()
                }
            }
            self.isAnimating = false
        }
    }

    private func finishPresentation(after delay: TimeInterval, completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion()
        }
    }

    private func resetWindowAlpha() {
        window.alphaValue = 1
        window.contentView?.alphaValue = 1
    }

    private func updateWindowChrome() {
        let windowed = state.windowBrowsingMode
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = windowed ? LaunchConstants.WindowBrowsing.cornerRadius : 0
        window.contentView?.layer?.masksToBounds = windowed
        window.hasShadow = windowed
    }

    private func windowedFrame(in screenFrame: NSRect) -> NSRect {
        let width = min(LaunchConstants.WindowBrowsing.width, screenFrame.width)
        let height = min(LaunchConstants.WindowBrowsing.height, screenFrame.height)
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )
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

    private func setMenuBarHidden(_ hidden: Bool) {
        if hidden != menuBarHidden {
            menuBarHidden = hidden
            NSApp.presentationOptions = hidden ? [.hideMenuBar, .hideDock] : []
        }
        window.level = hidden ? .screenSaver : (state.windowBrowsingMode ? .normal : .mainMenu)
    }
}

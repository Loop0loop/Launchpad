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
        state.launcherVisible = true

        applyWindowBrowsingMode()
        window.alphaValue = 0
        window.contentView?.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        animateWindow(to: 1)
    }

    func hide() {
        guard !isAnimating, window.isVisible else { return }
        animateWindow(to: 0, restorePreviousApp: true)
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
        animateWindow(to: 0, restorePreviousApp: false)
    }

    func revealInFinder(_ app: LaunchApp) {
        dismiss()
        AppSystemAdapter.showInFinder(app)
    }

    func applyWindowBrowsingMode() {
        let screenFrame = NSScreen.main?.frame ?? window.frame
        window.setFrame(state.windowBrowsingMode ? windowedFrame(in: screenFrame) : screenFrame, display: true)
        guard state.launcherVisible || window.isVisible else {
            window.level = state.windowBrowsingMode ? .normal : .mainMenu
            return
        }
        setMenuBarHidden(!state.windowBrowsingMode)
    }

    private func animateWindow(to targetAlpha: CGFloat, restorePreviousApp: Bool = false) {
        isAnimating = true
        window.alphaValue = targetAlpha
        window.contentView?.alphaValue = targetAlpha
        isAnimating = false

        if targetAlpha <= 0.01 {
            setMenuBarHidden(false)
            state.launcherVisible = false
            window.orderOut(nil)
            resetWindowAlpha()
            if restorePreviousApp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.activatePreviousApp()
                }
            }
        }
    }

    private func resetWindowAlpha() {
        window.alphaValue = 1
        window.contentView?.alphaValue = 1
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
            NSApp.presentationOptions = hidden ? [.hideMenuBar, .autoHideDock] : []
        }
        window.level = hidden ? .screenSaver : (state.windowBrowsingMode ? .normal : .mainMenu)
    }
}

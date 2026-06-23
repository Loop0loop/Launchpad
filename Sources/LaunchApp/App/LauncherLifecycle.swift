import AppKit
import LaunchCore

@MainActor
final class LauncherLifecycle {
    private let state: AppState
    private let window: NSWindow
    private weak var mouseMonitor: LauncherMouseMonitor?
    private var previousApp: NSRunningApplication?
    private var menuBarHidden = false
    private var hideToken = UUID()

    init(state: AppState, window: NSWindow, mouseMonitor: LauncherMouseMonitor? = nil) {
        self.state = state
        self.window = window
        self.mouseMonitor = mouseMonitor
    }

    var isVisible: Bool {
        window.isVisible && state.launcherVisible
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard !isVisible else { return }

        hideToken = UUID()
        rememberPreviousApp()
        state.query = ""
        state.openFolder = nil
        state.clearSelection()

        applyWindowBrowsingMode()
        state.launcherVisible = true
        state.pageDragOffset = 0

        preparePresentationLayer()
        setPresentationScale(LaunchConstants.Lifecycle.hiddenScale)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mouseMonitor?.setEnabled(true)

        runPresentationAnimation(toVisible: true) { [weak self] in
            DispatchQueue.main.async {
                self?.state.focusSearchField()
            }
        }
        LaunchLog.line("lifecycle show requested visible=\(state.launcherVisible)")
    }

    func hide() {
        guard window.isVisible, state.launcherVisible else { return }
        LaunchLog.line("lifecycle hide requested visible=\(state.launcherVisible)")
        mouseMonitor?.setEnabled(false)

        let token = UUID()
        hideToken = token

        runPresentationAnimation(toVisible: false) { [weak self] in
            guard let self, self.hideToken == token else { return }
            self.state.launcherVisible = false
            self.setMenuBarHidden(false)
            self.window.orderOut(nil)
            self.resetPresentation()
            self.activatePreviousApp()
        }
    }

    func dismiss() {
        mouseMonitor?.setEnabled(false)
        setMenuBarHidden(false)
        state.launcherVisible = false
        window.orderOut(nil)
        resetPresentation()
    }

    func launch(_ app: LaunchApp) {
        AppSystemAdapter.launch(app)
        if window.isVisible {
            mouseMonitor?.setEnabled(false)
            runPresentationAnimation(toVisible: false) { [weak self] in
                guard let self else { return }
                self.state.launcherVisible = false
                self.setMenuBarHidden(false)
                self.window.orderOut(nil)
                self.resetPresentation()
            }
        } else {
            dismiss()
        }
    }

    func revealInFinder(_ app: LaunchApp) {
        dismiss()
        AppSystemAdapter.showInFinder(app)
    }

    func applyWindowBrowsingMode() {
        let screenFrame = NSScreen.main?.frame ?? window.frame
        window.setFrame(state.windowBrowsingMode ? windowedFrame(in: screenFrame) : screenFrame, display: true)
        updateWindowChrome()
        preparePresentationLayer()
        guard state.launcherVisible || window.isVisible else {
            window.level = state.windowBrowsingMode ? .normal : .mainMenu
            return
        }
        setMenuBarHidden(!state.windowBrowsingMode)
    }

    /// Apple AppKit pattern: `NSAnimationContext.runAnimationGroup` + `animator()` proxies.
    /// https://developer.apple.com/documentation/appkit/nsanimationcontext
    private func runPresentationAnimation(toVisible: Bool, completion: @escaping @MainActor () -> Void) {
        preparePresentationLayer()
        let endScale = toVisible ? CGFloat(1) : LaunchConstants.Lifecycle.hiddenScale
        let endAlpha = toVisible ? CGFloat(1) : CGFloat(0)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = LaunchConstants.Lifecycle.windowDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = endAlpha
            setPresentationScale(endScale)
        } completionHandler: {
            Task { @MainActor in
                completion()
            }
        }
    }

    private func preparePresentationLayer() {
        guard let container = window.contentView as? LauncherPresentationContainer else { return }
        container.wantsLayer = true
        container.updateLayerPosition()
    }

    private func setPresentationScale(_ scale: CGFloat) {
        guard let container = window.contentView as? LauncherPresentationContainer else { return }
        container.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
    }

    private func resetPresentation() {
        window.alphaValue = 1
        window.contentView?.alphaValue = 1
        setPresentationScale(1)
    }

    private func updateWindowChrome() {
        let windowed = state.windowBrowsingMode
        guard let container = window.contentView as? LauncherPresentationContainer else { return }
        container.wantsLayer = true
        container.layer?.cornerRadius = windowed ? LaunchConstants.WindowBrowsing.cornerRadius : 0
        container.layer?.masksToBounds = windowed
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

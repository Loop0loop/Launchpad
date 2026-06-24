import AppKit
import LaunchCore

@MainActor
final class LauncherLifecycle {
    private let state: AppState
    private let window: NSWindow
    private weak var mouseMonitor: LauncherMouseMonitor?
    private var previousApp: NSRunningApplication?
    private var phase: Phase = .hidden
    private var transitionToken = UUID()

    private enum Phase {
        case hidden
        case showing
        case shown
        case hiding
    }

    init(state: AppState, window: NSWindow, mouseMonitor: LauncherMouseMonitor? = nil) {
        self.state = state
        self.window = window
        self.mouseMonitor = mouseMonitor
    }

    var isVisible: Bool {
        phase == .showing || phase == .shown || (window.isVisible && state.launcherVisible)
    }

    var canHandleUserDismissal: Bool {
        phase == .showing || phase == .shown
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard phase != .showing, phase != .shown else { return }

        let token = UUID()
        transitionToken = token
        phase = .showing
        rememberPreviousApp()
        state.query = ""
        state.openFolder = nil
        state.clearSelection()
        state.cancelDrag()

        state.launcherVisible = true
        state.pageDragOffset = 0
        state.backgroundDismissLockedUntil = Date().addingTimeInterval(0.35)
        // Focus (and the active search chrome) only when the user clicks the field.
        state.searchFocus.shouldFocusOnShow = false
        applyWindowBrowsingMode()

        preparePresentationLayer()
        setPresentationScale(LaunchConstants.Lifecycle.hiddenScale)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
        mouseMonitor?.setEnabled(true)

        runPresentationAnimation(toVisible: true) { [weak self] in
            guard let self, self.transitionToken == token else { return }
            self.phase = .shown
        }
        LaunchLog.line("lifecycle show requested visible=\(state.launcherVisible)")
    }

    func hide() {
        guard phase != .hidden, phase != .hiding, window.isVisible else { return }
        LaunchLog.line("lifecycle hide requested visible=\(state.launcherVisible)")
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.settingsWindow?.orderOut(nil)
        }
        mouseMonitor?.setEnabled(false)
        state.cancelDrag()

        let token = UUID()
        transitionToken = token
        phase = .hiding

        runPresentationAnimation(toVisible: false) { [weak self] in
            guard let self, self.transitionToken == token else { return }
            self.phase = .hidden
            self.state.launcherVisible = false
            self.restoreSystemVisibility()
            self.window.orderOut(nil)
            self.resetPresentation()
            self.activatePreviousApp()
        }
    }

    func dismiss() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.settingsWindow?.orderOut(nil)
        }
        transitionToken = UUID()
        phase = .hidden
        mouseMonitor?.setEnabled(false)
        state.cancelDrag()
        restoreSystemVisibility()
        state.launcherVisible = false
        window.orderOut(nil)
        resetPresentation()
    }

    func launch(_ app: LaunchApp) {
        AppSystemAdapter.launch(app)
        if window.isVisible {
            mouseMonitor?.setEnabled(false)
            state.cancelDrag()
            let token = UUID()
            transitionToken = token
            phase = .hiding
            runPresentationAnimation(toVisible: false) { [weak self] in
                guard let self, self.transitionToken == token else { return }
                self.phase = .hidden
                self.state.launcherVisible = false
                self.restoreSystemVisibility()
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
        if state.launcherVisible || window.isVisible {
            applySystemVisibility()
        }
        let screen = NSScreen.main
        let screenFrame = screen?.frame ?? window.frame
        window.setFrame(state.windowBrowsingMode ? windowedFrame(in: screenFrame) : launcherFrame(in: screen), display: true)
        updateWindowChrome()
        preparePresentationLayer()
        guard state.launcherVisible || window.isVisible else {
            window.level = state.windowBrowsingMode ? .normal : .mainMenu
            return
        }
    }

    /// Apple AppKit pattern: `NSAnimationContext.runAnimationGroup` + `animator()` proxies.
    /// https://developer.apple.com/documentation/appkit/nsanimationcontext
    private func runPresentationAnimation(toVisible: Bool, completion: @escaping @MainActor () -> Void) {
        preparePresentationLayer()
        let endScale = toVisible ? CGFloat(1) : LaunchConstants.Lifecycle.hiddenScale
        let endAlpha = toVisible ? CGFloat(1) : CGFloat(0)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = toVisible ? LaunchConstants.Lifecycle.windowShowDuration : LaunchConstants.Lifecycle.windowHideDuration
            context.timingFunction = CAMediaTimingFunction(name: toVisible ? .easeOut : .easeIn)
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

    private func launcherFrame(in screen: NSScreen?) -> NSRect {
        guard let screen else { return window.frame }
        var frame = screen.frame
        let visible = screen.visibleFrame

        if state.showMenuBarInLauncher {
            frame.size.height -= max(0, frame.maxY - visible.maxY)
        }

        if state.showDockInLauncher {
            let leftInset = max(0, visible.minX - frame.minX)
            let rightInset = max(0, frame.maxX - visible.maxX)
            let bottomInset = max(0, visible.minY - frame.minY)

            frame.origin.x += leftInset
            frame.size.width -= leftInset + rightInset
            frame.origin.y += bottomInset
            frame.size.height -= bottomInset
        }

        return frame
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

    private func applySystemVisibility() {
        guard !state.windowBrowsingMode else {
            restoreSystemVisibility()
            return
        }
        setSystemHidden(hideMenuBar: !state.showMenuBarInLauncher, hideDock: !state.showDockInLauncher)
    }

    private func setSystemHidden(hideMenuBar: Bool, hideDock: Bool) {
        var options: NSApplication.PresentationOptions = [.disableProcessSwitching, .disableHideApplication]
        if hideMenuBar { options.insert(.hideMenuBar) }
        if hideDock { options.insert(.hideDock) }
        if NSApp.presentationOptions != options {
            NSApp.presentationOptions = options
        }
        window.level = hideMenuBar ? .screenSaver : (state.windowBrowsingMode ? .normal : .mainMenu)
    }

    private func restoreSystemVisibility() {
        if !NSApp.presentationOptions.isEmpty {
            NSApp.presentationOptions = []
        }
        window.level = state.windowBrowsingMode ? .normal : .mainMenu
    }
}

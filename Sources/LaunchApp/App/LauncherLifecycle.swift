import AppKit
import LaunchpadCore

@MainActor
final class LauncherLifecycle {
    let state: AppState
    let window: NSWindow
    weak var mouseMonitor: LauncherMouseMonitor?
    private var previousApp: NSRunningApplication?
    var phase: Phase = .hidden
    var transitionToken = UUID()
    var pinchTracking: PinchTracking?
    var interactionProgress: CGFloat = 0
    var interactionVelocity: CGFloat = 0
    var presentationProgress: CGFloat = 0
    var presentationVelocity: CGFloat = 0
    var pinchPreviousProgress: CGFloat = 0
    var pinchPreviousTimestamp: TimeInterval = 0
    var latestInteractionDelta: CGFloat = 0
    var previousInteractionDelta: CGFloat = 0
    var lastSignificantChangeTimestamp: TimeInterval = 0
    var hasPendingInteractionSample = false
    var jumpTarget: CGFloat?
    var jumpFramesRemaining = 0
    var presentationDisplayLink: CADisplayLink?
    var presentationTarget: CGFloat = 0
    var presentationLastTimestamp: TimeInterval = 0
    var springStartTimestamp: TimeInterval = 0
    var springStartProgress: CGFloat = 0
    var springStartVelocity: CGFloat = 0
    var presentationCompletion: (@MainActor () -> Void)?

    enum Phase {
        case hidden
        case showing
        case shown
        case hiding
    }

    struct PinchTracking {
        let intent: TrackpadIntent
        let startProgress: CGFloat
    }

    var isPinchTracking: Bool { pinchTracking != nil }

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
        if pinchTracking != nil {
            presentationProgress >= 0.5 ? hide() : show()
            return
        }
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard phase != .shown else { return }
        if pinchTracking != nil {
            pinchTracking = nil
            stopPresentationAnimation()
        } else {
            guard phase != .showing else { return }
        }

        let token = UUID()
        transitionToken = token
        phase = .showing
        prepareShowPresentation()

        runPresentationAnimation(toVisible: true) { [weak self] in
            guard let self, self.transitionToken == token else { return }
            self.phase = .shown
        }
        LaunchLog.line("lifecycle show requested visible=\(state.launcherVisible)")
    }

    func hide() {
        if pinchTracking != nil {
            pinchTracking = nil
            stopPresentationAnimation()
        }
        guard phase != .hidden, phase != .hiding, window.isVisible else { return }
        LaunchLog.line("lifecycle hide requested visible=\(state.launcherVisible)")
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.settingsWindow?.orderOut(nil)
        }
        mouseMonitor?.setEnabled(false)
        state.clearFolderTransientAnimations()
        state.stopEditingLayout()
        state.cancelDrag()

        let token = UUID()
        transitionToken = token
        phase = .hiding

        runPresentationAnimation(toVisible: false) { [weak self] in
            guard let self, self.transitionToken == token else { return }
            self.completeHide(activatePrevious: true)
        }
    }

    func dismiss() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.settingsWindow?.orderOut(nil)
        }
        pinchTracking = nil
        transitionToken = UUID()
        phase = .hidden
        mouseMonitor?.setEnabled(false)
        state.clearFolderTransientAnimations()
        state.stopEditingLayout()
        state.cancelDrag()
        completeHide(activatePrevious: false)
    }

    func launch(_ app: LaunchApp) {
        AppSystemAdapter.launch(app)
        if window.isVisible {
            mouseMonitor?.setEnabled(false)
            state.clearFolderTransientAnimations()
            state.stopEditingLayout()
            state.cancelDrag()
            let token = UUID()
            transitionToken = token
            phase = .hiding
            runPresentationAnimation(toVisible: false) { [weak self] in
                guard let self, self.transitionToken == token else { return }
                self.completeHide(activatePrevious: false)
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

    func runPresentationAnimation(toVisible: Bool, completion: @escaping @MainActor () -> Void) {
        settlePresentation(to: toVisible ? 1 : 0, initialVelocity: presentationVelocity, completion: completion)
    }

    func applyPresentationProgress(_ progress: CGFloat) {
        presentationProgress = min(max(progress, 0), 1)
        window.alphaValue = pinchTracking == nil
            ? presentationProgress * presentationProgress * (3 - 2 * presentationProgress)
            : presentationProgress

        if let container = window.contentView as? LauncherPresentationContainer {
            let scale = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? 1
                : 1 + (1 - presentationProgress) * (LaunchConstants.Lifecycle.interactiveStartScale - 1)
            container.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    func settlePresentation(
        to target: CGFloat,
        initialVelocity: CGFloat,
        completion: @escaping @MainActor () -> Void
    ) {
        stopPresentationAnimation()
        preparePresentationLayer()
        interactionProgress = target
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            applyPresentationProgress(target)
            completion()
            return
        }

        presentationTarget = target
        springStartProgress = presentationProgress
        springStartVelocity = min(
            max(initialVelocity, -LaunchConstants.Lifecycle.maximumSpringVelocity),
            LaunchConstants.Lifecycle.maximumSpringVelocity
        )
        presentationVelocity = springStartVelocity
        springStartTimestamp = CACurrentMediaTime()
        presentationLastTimestamp = 0
        presentationCompletion = completion
        startPresentationDisplayLink()
    }

    func startPresentationFollower() {
        stopPresentationAnimation()
        presentationLastTimestamp = 0
        startPresentationDisplayLink()
    }

    private func startPresentationDisplayLink() {
        let displayLink = window.displayLink(target: self, selector: #selector(stepPresentation(_:)))
        presentationDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    func stopPresentationAnimation() {
        presentationDisplayLink?.invalidate()
        presentationDisplayLink = nil
        presentationCompletion = nil
        presentationLastTimestamp = 0
        springStartTimestamp = 0
    }

    @objc private func stepPresentation(_ displayLink: CADisplayLink) {
        let dt = presentationLastTimestamp == 0
            ? min(displayLink.duration, 1.0 / 60.0)
            : min(displayLink.timestamp - presentationLastTimestamp, 1.0 / 30.0)
        presentationLastTimestamp = displayLink.timestamp

        if pinchTracking != nil {
            if hasPendingInteractionSample {
                hasPendingInteractionSample = false
                let shouldInterpolate = TrackpadIntent.shouldInterpolatePresentationJump(
                    delta: Double(latestInteractionDelta),
                    previousDelta: Double(previousInteractionDelta),
                    velocity: Double(interactionVelocity),
                    largeJumpThreshold: Double(LaunchConstants.Lifecycle.largeJumpThreshold),
                    fastVelocityThreshold: Double(LaunchConstants.Lifecycle.fastInputVelocityThreshold),
                    stationaryVelocityThreshold: Double(LaunchConstants.Lifecycle.stationaryVelocityThreshold),
                    stationaryDeltaThreshold: Double(LaunchConstants.Lifecycle.stationaryDeltaThreshold)
                )

                let previous = presentationProgress
                if !shouldInterpolate {
                    jumpTarget = nil
                    jumpFramesRemaining = 0
                    applyPresentationProgress(interactionProgress)
                } else {
                    applyPresentationProgress(
                        presentationProgress
                            + (interactionProgress - presentationProgress) * LaunchConstants.Lifecycle.largeJumpFirstFrameRatio
                    )
                    jumpTarget = interactionProgress
                    jumpFramesRemaining = 1
                }
                presentationVelocity = dt > 0 ? (presentationProgress - previous) / CGFloat(dt) : 0
                return
            }

            if jumpFramesRemaining > 0, let jumpTarget {
                let previous = presentationProgress
                applyPresentationProgress(jumpTarget)
                jumpFramesRemaining = 0
                self.jumpTarget = nil
                presentationVelocity = dt > 0 ? (presentationProgress - previous) / CGFloat(dt) : 0
                return
            }

            if displayLink.timestamp - lastSignificantChangeTimestamp
                >= LaunchConstants.Lifecycle.stationaryTimeout,
               presentationProgress != interactionProgress {
                applyPresentationProgress(interactionProgress)
                presentationVelocity = 0
            }
            return
        }

        let response = presentationTarget == 0
            ? LaunchConstants.Lifecycle.closeSpringResponse
            : LaunchConstants.Lifecycle.openSpringResponse
        let angularFrequency = 2 * Double.pi / response
        let elapsed = max(displayLink.timestamp - springStartTimestamp, 0)
        let displacement = Double(springStartProgress - presentationTarget)
        let coefficient = Double(springStartVelocity) + angularFrequency * displacement
        let decay = exp(-angularFrequency * elapsed)
        let offset = (displacement + coefficient * elapsed) * decay
        let velocity = (coefficient - angularFrequency * (displacement + coefficient * elapsed)) * decay
        presentationVelocity = CGFloat(velocity)
        applyPresentationProgress(presentationTarget + CGFloat(offset))

        guard abs(presentationProgress - presentationTarget) < 0.001,
              abs(presentationVelocity) < 0.01 else { return }
        let completion = presentationCompletion
        stopPresentationAnimation()
        interactionProgress = presentationTarget
        interactionVelocity = 0
        presentationVelocity = 0
        applyPresentationProgress(presentationTarget)
        completion?()
    }

    func preparePresentationLayer() {
        guard let container = window.contentView as? LauncherPresentationContainer else { return }
        container.wantsLayer = true
        container.layoutSubtreeIfNeeded()
    }

    private func resetPresentation() {
        stopPresentationAnimation()
        interactionProgress = 1
        interactionVelocity = 0
        hasPendingInteractionSample = false
        jumpTarget = nil
        jumpFramesRemaining = 0
        presentationVelocity = 0
        applyPresentationProgress(1)
        window.contentView?.alphaValue = 1
    }

    func completeHide(activatePrevious: Bool) {
        pinchTracking = nil
        phase = .hidden
        state.launcherVisible = false
        (NSApp.delegate as? AppDelegate)?.trackpadMonitor.setLauncherVisible(false)
        // ponytail: keep the hidden launcher warm; revisit eviction only if measured idle memory is excessive.
        restoreSystemVisibility()
        window.orderOut(nil)
        resetPresentation()
        if activatePrevious { activatePreviousApp() }
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

    func rememberPreviousApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier {
            previousApp = frontmost
        }
    }

    private func activatePreviousApp() {
        previousApp?.activate()
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
        window.level = hideMenuBar ? .statusBar : (state.windowBrowsingMode ? .normal : .mainMenu)
    }

    private func restoreSystemVisibility() {
        if !NSApp.presentationOptions.isEmpty {
            NSApp.presentationOptions = []
        }
        window.level = state.windowBrowsingMode ? .normal : .mainMenu
    }
}

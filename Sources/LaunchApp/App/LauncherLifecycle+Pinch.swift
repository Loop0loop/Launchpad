import AppKit
import LaunchpadCore

extension LauncherLifecycle {
    func handlePinchUpdate(_ update: TrackpadPinchUpdate) {
        switch update {
        case .tracking(let intent, let progress, let timestamp):
            trackPinch(intent: intent, progress: progress, timestamp: timestamp)
        case .commit(let intent):
            commitPinch(intent)
        case .cancel:
            cancelPinch()
        }
    }

    func dismissForSystemGesture() {
        pinchTracking = nil
        stopPresentationAnimation()
        interactionVelocity = 0
        presentationVelocity = 0
        guard window.isVisible || state.launcherVisible else { return }
        dismiss()
    }

    func trackPinch(intent: TrackpadIntent, progress: Double, timestamp: TimeInterval) {
        let clamped = min(max(progress, 0), 1)
        let sampleTimestamp = timestamp.isFinite ? timestamp : 0
        switch intent {
        case .open:
            guard state.openFolder == nil else { return }
            if phase == .shown, pinchTracking == nil { return }
            if pinchTracking == nil {
                guard phase == .hidden || !window.isVisible || presentationDisplayLink != nil else { return }
                transitionToken = UUID()
                let needsPreparation = phase == .hidden || !window.isVisible
                phase = .showing
                if needsPreparation {
                    prepareShowPresentation()
                } else {
                    stopPresentationAnimation()
                }
                beginPinch(intent: .open, timestamp: sampleTimestamp)
            }
            guard pinchTracking?.intent == .open else { return }
            applyPinchPresentation(progress: clamped, timestamp: sampleTimestamp)
        case .close:
            guard state.openFolder == nil else { return }
            guard phase != .hidden || pinchTracking?.intent == .close else { return }
            if pinchTracking == nil {
                transitionToken = UUID()
                stopPresentationAnimation()
                phase = .hiding
                mouseMonitor?.setEnabled(false)
                state.clearFolderTransientAnimations()
                state.stopEditingLayout()
                state.cancelDrag()
                preparePresentationLayer()
                beginPinch(intent: .close, timestamp: sampleTimestamp)
            }
            guard pinchTracking?.intent == .close else { return }
            applyPinchPresentation(progress: clamped, timestamp: sampleTimestamp)
        case .previousPage, .nextPage:
            break
        }
    }

    func commitPinch(_ intent: TrackpadIntent) {
        if pinchTracking != nil {
            finishPinch(committed: true)
            return
        }
        switch intent {
        case .open:
            if phase != .shown { show() }
        case .close:
            if state.openFolder != nil {
                state.closeFolder()
                return
            }
            if isVisible { hide() }
        case .previousPage, .nextPage:
            pinchTracking = nil
        }
    }

    func cancelPinch() {
        guard pinchTracking != nil else { return }
        finishPinch(committed: false)
    }

    private func beginPinch(intent: TrackpadIntent, timestamp: TimeInterval) {
        pinchTracking = PinchTracking(intent: intent, startProgress: presentationProgress)
        interactionProgress = presentationProgress
        interactionVelocity = 0
        presentationVelocity = 0
        pinchPreviousProgress = interactionProgress
        pinchPreviousTimestamp = timestamp
        latestInteractionDelta = 0
        previousInteractionDelta = 0
        lastSignificantChangeTimestamp = CACurrentMediaTime()
        hasPendingInteractionSample = false
        jumpTarget = nil
        jumpFramesRemaining = 0
        startPresentationFollower()
    }

    private func finishPinch(committed: Bool) {
        guard let tracking = pinchTracking else { return }
        pinchTracking = nil
        let token = UUID()
        transitionToken = token
        let decisionVelocity = min(
            max(interactionVelocity, -LaunchConstants.Lifecycle.maximumDecisionVelocity),
            LaunchConstants.Lifecycle.maximumDecisionVelocity
        )
        let target = CGFloat(TrackpadIntent.projectedTransitionTarget(
            progress: Double(interactionProgress),
            velocity: Double(decisionVelocity),
            projectionTime: LaunchConstants.Lifecycle.decisionProjectionTime
        ))
        (NSApp.delegate as? AppDelegate)?.trackpadMonitor.setLauncherVisible(target == 1)
        LaunchLog.line(
            "trackpad settle intent=\(tracking.intent) committed=\(committed) progress=\(interactionProgress) velocity=\(interactionVelocity) target=\(target)"
        )
        let springVelocity = min(
            max(presentationVelocity, -LaunchConstants.Lifecycle.maximumSpringVelocity),
            LaunchConstants.Lifecycle.maximumSpringVelocity
        )
        if target == 0 {
            phase = .hiding
            mouseMonitor?.setEnabled(false)
            settlePresentation(to: 0, initialVelocity: springVelocity) { [weak self] in
                guard let self, self.transitionToken == token else { return }
                self.completeHide(activatePrevious: tracking.intent == .close)
            }
        } else {
            phase = .showing
            mouseMonitor?.setEnabled(true)
            settlePresentation(to: 1, initialVelocity: springVelocity) { [weak self] in
                guard let self, self.transitionToken == token else { return }
                self.phase = .shown
            }
        }
    }

    func prepareShowPresentation() {
        let wasVisible = window.isVisible
        rememberPreviousApp()
        state.query = ""
        state.clearFolderTransientAnimations()
        state.openFolder = nil
        state.clearSelection()
        state.stopEditingLayout()
        state.cancelDrag()
        state.actions.restoreLauncherRoot()

        state.launcherVisible = true
        (NSApp.delegate as? AppDelegate)?.trackpadMonitor.setLauncherVisible(true)
        state.pageDragOffset = 0
        state.backgroundDismissLockedUntil = Date().addingTimeInterval(0.35)
        // Focus (and the active search chrome) only when the user clicks the field.
        state.searchFocus.shouldFocusOnShow = false
        applyWindowBrowsingMode()
        state.refreshAppsAsyncIfStale()

        preparePresentationLayer()
        if !wasVisible { applyPresentationProgress(0) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(nil)
        mouseMonitor?.setEnabled(true)
    }

    func applyPinchPresentation(progress: Double, timestamp: TimeInterval) {
        guard let tracking = pinchTracking else { return }
        let clampedProgress = CGFloat(TrackpadIntent.additiveTransitionProgress(
            start: Double(tracking.startProgress),
            gestureProgress: progress,
            intent: tracking.intent
        ))
        let dt = timestamp - pinchPreviousTimestamp
        let inputDelta = clampedProgress - interactionProgress
        if dt >= 1.0 / 240.0, dt <= 0.25 {
            let rawVelocity = (clampedProgress - pinchPreviousProgress) / dt
            interactionVelocity = interactionVelocity * 0.55 + rawVelocity * 0.45
        }
        previousInteractionDelta = latestInteractionDelta
        latestInteractionDelta = inputDelta
        interactionProgress = clampedProgress
        if abs(inputDelta) >= LaunchConstants.Lifecycle.stationaryDeltaThreshold {
            lastSignificantChangeTimestamp = CACurrentMediaTime()
        }
        hasPendingInteractionSample = true
        pinchPreviousProgress = clampedProgress
        if timestamp > pinchPreviousTimestamp {
            pinchPreviousTimestamp = timestamp
        }
    }
}

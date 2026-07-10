import AppKit
import LaunchpadCore

extension LauncherLifecycle {
    func handlePinchUpdate(_ update: TrackpadPinchUpdate) {
        switch update {
        case .tracking(let intent, let progress):
            trackPinch(intent: intent, progress: progress)
        case .commit(let intent):
            commitPinch(intent)
        case .cancel:
            cancelPinch()
        }
    }

    func trackPinch(intent: TrackpadIntent, progress: Double) {
        let clamped = min(max(progress, 0), 1)
        switch intent {
        case .open:
            guard state.openFolder == nil else { return }
            if phase == .shown || phase == .showing, pinchTracking == nil { return }
            if pinchTracking == nil {
                guard phase == .hidden || !window.isVisible else { return }
                pinchTracking = .opening
                transitionToken = UUID()
                phase = .showing
                prepareShowPresentation()
            }
            guard pinchTracking == .opening else { return }
            applyPinchPresentation(progress: clamped, opening: true)
        case .close:
            guard state.openFolder == nil else { return }
            guard phase == .shown || phase == .showing || pinchTracking == .closing else { return }
            if pinchTracking == nil {
                pinchTracking = .closing
                transitionToken = UUID()
                phase = .hiding
                mouseMonitor?.setEnabled(false)
                state.clearFolderTransientAnimations()
                state.stopEditingLayout()
                state.cancelDrag()
                preparePresentationLayer()
            }
            guard pinchTracking == .closing else { return }
            applyPinchPresentation(progress: clamped, opening: false)
        case .previousPage, .nextPage:
            break
        }
    }

    func commitPinch(_ intent: TrackpadIntent) {
        switch intent {
        case .open:
            guard pinchTracking == .opening else {
                if phase != .shown { show() }
                return
            }
            pinchTracking = nil
            let token = UUID()
            transitionToken = token
            runPresentationAnimation(toVisible: true) { [weak self] in
                guard let self, self.transitionToken == token else { return }
                self.phase = .shown
            }
        case .close:
            if state.openFolder != nil {
                pinchTracking = nil
                state.closeFolder()
                return
            }
            guard pinchTracking == .closing else {
                if isVisible { hide() }
                return
            }
            pinchTracking = nil
            let token = UUID()
            transitionToken = token
            phase = .hiding
            runPresentationAnimation(toVisible: false) { [weak self] in
                guard let self, self.transitionToken == token else { return }
                self.completeHide(activatePrevious: true)
            }
        case .previousPage, .nextPage:
            pinchTracking = nil
        }
    }

    func cancelPinch() {
        guard let tracking = pinchTracking else { return }
        pinchTracking = nil
        let token = UUID()
        transitionToken = token
        switch tracking {
        case .opening:
            phase = .hiding
            mouseMonitor?.setEnabled(false)
            runPresentationAnimation(toVisible: false) { [weak self] in
                guard let self, self.transitionToken == token else { return }
                self.completeHide(activatePrevious: false)
            }
        case .closing:
            phase = .showing
            mouseMonitor?.setEnabled(true)
            runPresentationAnimation(toVisible: true) { [weak self] in
                guard let self, self.transitionToken == token else { return }
                self.phase = .shown
            }
        }
    }

    func prepareShowPresentation() {
        rememberPreviousApp()
        state.query = ""
        state.clearFolderTransientAnimations()
        state.openFolder = nil
        state.clearSelection()
        state.stopEditingLayout()
        state.cancelDrag()
        state.actions.restoreLauncherRoot()

        state.launcherVisible = true
        state.pageDragOffset = 0
        state.backgroundDismissLockedUntil = Date().addingTimeInterval(0.35)
        // Focus (and the active search chrome) only when the user clicks the field.
        state.searchFocus.shouldFocusOnShow = false
        applyWindowBrowsingMode()
        state.refreshAppsAsyncIfStale()

        preparePresentationLayer()
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
        mouseMonitor?.setEnabled(true)
    }

    func applyPinchPresentation(progress: Double, opening: Bool) {
        let t = opening ? progress : (1 - progress)
        window.alphaValue = CGFloat(t)
    }
}

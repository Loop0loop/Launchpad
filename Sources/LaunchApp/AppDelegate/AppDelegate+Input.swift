import AppKit
import LaunchpadCore
import SwiftUI

extension AppDelegate {
    func prepareExclusiveTrackpadGestures() {
        // Recover a snapshot left by a previous abnormal exit before taking ownership again.
        SystemTrackpadSettings.restoreMissionControlGesture()
        SystemTrackpadSettings.restoreNativeLaunchpadPinch()
        showDesktopController.start { [weak self] visibility in
            guard let self else { return }
            let systemTookOver = trackpadMonitor.systemDesktopTransitionReceived(visibility: visibility)
            if systemTookOver,
               visibility == .desktopVisible || launcherLifecycle?.isPinchTracking == true {
                launcherLifecycle?.dismissForSystemGesture()
            }
        }
        trackpadMonitor.setSystemDesktopVisibility(showDesktopController.visibility)
        LaunchLog.line("native Show Desktop observation started")
    }

    func startTrackpadMonitor() {
        LaunchLog.line("start trackpad monitor")
        let resolvedGesture = TrackpadGestureResolver.resolve(
            preferred: state.trackpadSetting,
            system: SystemTrackpadSettings.load()
        )
        LaunchLog.line(
            "trackpad resolved setting=\(resolvedGesture.setting) fingers=\(resolvedGesture.fingerCounts.map(String.init).joined(separator: ",")) conflicted=\(resolvedGesture.conflicted)"
        )
        state.applyResolvedTrackpadGesture(resolvedGesture)
        guard !resolvedGesture.fingerCounts.isEmpty else {
            trackpadMonitor.stop()
            SystemTrackpadSettings.restoreNativeLaunchpadPinch()
            ownsNativePinchGestures = false
            state.setTrackpadGateActive(false)
            return
        }
        guard showDesktopController.isSupported,
              SystemTrackpadSettings.reserveNativeLaunchpadPinch() else {
            trackpadMonitor.stop()
            SystemTrackpadSettings.restoreNativeLaunchpadPinch()
            ownsNativePinchGestures = false
            state.setTrackpadGateActive(false, conflicted: true)
            LaunchLog.line("exclusive trackpad ownership unavailable")
            return
        }
        ownsNativePinchGestures = true
        let preservesSystemShowDesktop = false
        let controlsSystemShowDesktop = true
        LaunchLog.line(
            "trackpad Show Desktop mode=\(showDesktopController.supportsContinuousGesture ? "continuous" : "direct")"
        )
        trackpadMonitor.setSystemDesktopVisibility(showDesktopController.visibility)
        trackpadMonitor.start(
            requiredFingerCounts: resolvedGesture.fingerCounts,
            preservesSystemShowDesktop: preservesSystemShowDesktop,
            controlsSystemShowDesktop: controlsSystemShowDesktop
        ) { [weak self] isActive in
            guard let self else { return }
            LaunchLog.line("trackpad gate active=\(isActive)")
            if !isActive {
                SystemTrackpadSettings.restoreNativeLaunchpadPinch()
                ownsNativePinchGestures = false
            }
            state.applyResolvedTrackpadGesture(TrackpadGestureResolver.resolve(
                preferred: state.trackpadSetting, system: SystemTrackpadSettings.load()
            ))
            state.setTrackpadGateActive(isActive && ownsNativePinchGestures, conflicted: !isActive)
        } onIntent: { [weak self] intent in
            guard let self else { return }
            if intent == .open || intent == .close {
                guard ownsNativePinchGestures else { return }
            }
            guard TrackpadGestureResolver.resolve(
                preferred: state.trackpadSetting,
                system: SystemTrackpadSettings.load()
            ).fingerCounts.isEmpty == false else { return }
            // Settings floats above the launcher, so trackpad gestures still open it.
            let now = Date()
            guard now >= trackpadIntentLockedUntil else {
                LaunchLog.line("trackpad intent blocked cooldown")
                return
            }
            guard !state.isHandlingLauncherDrag else {
                LaunchLog.line("trackpad intent=\(intent) ignored during drag")
                return
            }
            guard launcherLifecycle?.isPinchTracking != true else {
                LaunchLog.line("trackpad intent=\(intent) ignored during pinch tracking")
                return
            }
            switch intent {
            case .open:
                guard launcherLifecycle?.isVisible != true else { return }
                trackpadIntentLockedUntil = now.addingTimeInterval(LaunchConstants.Multitouch.lifecycleBounceCooldown)
                LaunchLog.line("trackpad intent=\(intent)")
                launcherLifecycle?.show()
            case .close:
                if state.openFolder != nil {
                    trackpadIntentLockedUntil = now.addingTimeInterval(LaunchConstants.Multitouch.lifecycleBounceCooldown)
                    LaunchLog.line("trackpad intent=\(intent)")
                    state.closeFolder()
                } else if launcherLifecycle?.isVisible == true {
                    trackpadIntentLockedUntil = now.addingTimeInterval(LaunchConstants.Multitouch.lifecycleBounceCooldown)
                    LaunchLog.line("trackpad intent=\(intent)")
                    launcherLifecycle?.hide()
                }
            case .previousPage:
                changePageFromTrackpad(-1, intent: intent, ignoredLog: "trackpad previousPage ignored during drag")
            case .nextPage:
                changePageFromTrackpad(1, intent: intent, ignoredLog: "trackpad nextPage ignored during drag")
            }
        } onPinchUpdate: { [weak self] update in
            guard let self, ownsNativePinchGestures else { return }
            guard TrackpadGestureResolver.resolve(
                preferred: state.trackpadSetting,
                system: SystemTrackpadSettings.load()
            ).fingerCounts.isEmpty == false else { return }
            guard !state.isHandlingLauncherDrag else { return }
            if preservesSystemShowDesktop,
               showDesktopController.isActive,
               launcherLifecycle?.isVisible != true {
                trackpadMonitor.yieldCurrentGestureToSystem()
                return
            }
            if case .tracking(let intent, _, _) = update {
                if intent == .close, launcherLifecycle?.isVisible != true {
                    trackpadMonitor.yieldCurrentGestureToSystem()
                    return
                }
                if intent == .open,
                   launcherLifecycle?.phase == .shown,
                   launcherLifecycle?.isPinchTracking != true {
                    trackpadMonitor.yieldCurrentGestureToSystem()
                    return
                }
            }
            if case .commit(let intent) = update {
                if intent == .close, state.openFolder != nil {
                    state.closeFolder()
                    return
                }
            }
            launcherLifecycle?.handlePinchUpdate(update)
        } onSystemShowDesktop: { [weak self] update in
            guard let self, ownsNativePinchGestures, controlsSystemShowDesktop else { return }
            if case .began(let progress) = update {
                LaunchLog.line("trackpad control system show desktop progress=\(progress)")
                if progress > 0, launcherLifecycle?.isVisible == true {
                    launcherLifecycle?.hide()
                } else {
                    launcherLifecycle?.dismissForSystemGesture()
                }
            }
            _ = showDesktopController.handleGesture(update)
        }
    }

    func startTrackpadMonitorDeferred() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            startTrackpadMonitor()
        }
    }

    private func changePageFromTrackpad(_ delta: Int, intent: TrackpadIntent, ignoredLog: String) {
        if launcherLifecycle?.isVisible == true,
           state.openFolder == nil,
           state.query.isEmpty,
           state.displayMode == .paged,
           !state.isHandlingLauncherDrag {
            let oldPage = state.currentPage
            withAnimation(LaunchConstants.Animation.pageSnap) {
                state.changePage(delta)
            }
            if state.currentPage != oldPage {
                LaunchLog.line("trackpad intent=\(intent)")
            }
        } else if state.isHandlingLauncherDrag {
            LaunchLog.line(ignoredLog)
        }
    }

    func startGlobalHotKey() {
        LaunchLog.line("start global hotkey shortcut=\(state.globalHotKeyShortcut.displayName)")
        let status = globalHotKey.start(
            shortcut: state.globalHotKeyShortcut,
            f4Enabled: state.systemF4KeyEnabled
        ) {
            [weak self] in
            LaunchLog.line("global hotkey toggle")
            self?.launcherLifecycle?.toggle()
        } f4Action: {
            [weak self] in
            LaunchLog.line("f4 hotkey toggle")
            self?.launcherLifecycle?.toggle()
        }
        let f4TapActive = f4KeyTap.start(enabled: state.systemF4KeyEnabled) { [weak self] in
            LaunchLog.line("f4 tap toggle")
            self?.launcherLifecycle?.toggle()
        }
        LaunchLog.line("global hotkey status toggle=\(status.toggle) f4=\(status.f4) f4Tap=\(f4TapActive)")
        state.setGlobalHotKeyActive(status.toggle)
        state.setF4KeyActive(status.f4 || f4TapActive)
    }

    func startHotCornerMonitor() {
        LaunchLog.line("start hot corner monitor corner=\(state.hotCornerSetting)")
        hotCornerMonitor.start(corner: state.hotCornerSetting) { [weak self] in
            LaunchLog.line("hot corner show")
            self?.launcherLifecycle?.show()
        }
    }

    func applyInputSettings() {
        startGlobalHotKey()
        startHotCornerMonitor()
        startTrackpadMonitor()
    }

    func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, launcherLifecycle?.isVisible == true else { return event }
            return handleLauncherKey(event)
        }
        modifierKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, launcherLifecycle?.isVisible == true else { return event }
            if event.modifierFlags.contains(.option) {
                state.startEditingLayout()
            }
            return event
        }
    }

    /// True while any text field other than the search bar is being edited (the folder title).
    /// The field editor becomes the panel's first responder during editing.
    private var isTextFieldEditing: Bool {
        guard let responder = window?.firstResponder else { return false }
        if let textView = responder as? NSTextView, textView.isFieldEditor { return true }
        return responder is NSTextField
    }

    func handleLauncherKey(_ event: NSEvent) -> NSEvent? {
        if state.isSearchFieldFocused() {
            switch event.keyCode {
            case 36, 76:
                state.launchSelected()
                return nil
            case 53:
                state.handleEscape()
                return nil
            default:
                return event
            }
        }

        // Editing another text field (e.g. the folder title) — let the field handle every
        // key (arrows move the cursor) instead of driving the launcher grid behind it.
        if isTextFieldEditing {
            return event
        }

        switch event.keyCode {
        case 36, 76:
            state.launchSelected()
            return nil
        case 53:
            state.handleEscape()
            return nil
        case 51:
            state.deleteSearchBackward()
            return nil
        case 123:
            state.moveSelection(by: -1)
            return nil
        case 124:
            state.moveSelection(by: 1)
            return nil
        case 125:
            state.moveSelection(by: state.gridColumns)
            return nil
        case 126:
            state.moveSelection(by: -state.gridColumns)
            return nil
        default:
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let text = event.characters,
                  text.rangeOfCharacter(from: .controlCharacters) == nil else { return event }
            state.appendSearchText(text)
            return nil
        }
    }

    func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let quit = appMenu.addItem(
            withTitle: LaunchConstants.Menu.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: LaunchConstants.Menu.quitKey
        )
        quit.target = NSApp
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

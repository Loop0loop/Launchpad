import AppKit
import LaunchpadCore
import SwiftUI

extension AppDelegate {
    func startTrackpadMonitor() {
        LaunchLog.line("start trackpad monitor")
        let resolvedGesture = TrackpadGestureResolver.resolve(
            preferred: state.trackpadSetting,
            system: SystemTrackpadSettings.load()
        )
        LaunchLog.line(
            "trackpad resolved setting=\(resolvedGesture.setting) fingers=\(resolvedGesture.fingerCounts.map(String.init).joined(separator: ",")) conflicted=\(resolvedGesture.conflicted) reserveNativePinch=\(resolvedGesture.shouldReserveNativePinch)"
        )
        if resolvedGesture.shouldReserveNativePinch {
            SystemTrackpadSettings.reserveNativeLaunchpadPinch()
            LaunchLog.line("trackpad reserved native Launchpad pinch")
        }
        state.applyResolvedTrackpadGesture(resolvedGesture)
        guard !resolvedGesture.fingerCounts.isEmpty else {
            trackpadMonitor.stop()
            state.setTrackpadGateActive(false)
            return
        }
        trackpadMonitor.start(requiredFingerCounts: resolvedGesture.fingerCounts) { [weak self] isActive in
            LaunchLog.line("trackpad gate active=\(isActive)")
            self?.state.setTrackpadGateActive(isActive, conflicted: resolvedGesture.conflicted)
        } onIntent: { [weak self] intent in
            guard let self else { return }
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
        }
    }

    func startTrackpadMonitorDeferred() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            startTrackpadMonitor()
        }
    }

    private func changePageFromTrackpad(_ delta: Int, intent: TrackpadIntent, ignoredLog: String) {
        if launcherLifecycle?.isVisible == true, !state.isDraggingLauncherItem {
            let oldPage = state.currentPage
            withAnimation(LaunchConstants.Animation.pageSnap) {
                state.changePage(delta)
            }
            if state.currentPage != oldPage {
                LaunchLog.line("trackpad intent=\(intent)")
            }
        } else if state.isDraggingLauncherItem {
            LaunchLog.line(ignoredLog)
        }
    }

    func startGlobalHotKey() {
        LaunchLog.line("start global hotkey")
        let status = globalHotKey.start(f4Enabled: state.systemF4KeyEnabled) {
            [weak self] in
            LaunchLog.line("global hotkey toggle")
            self?.launcherLifecycle?.toggle()
        } f4Action: {
            [weak self] in
            LaunchLog.line("f4 hotkey toggle")
            self?.launcherLifecycle?.toggle()
        }
        LaunchLog.line("global hotkey status toggle=\(status.toggle) f4=\(status.f4)")
        state.setGlobalHotKeyActive(status.toggle)
        state.setF4KeyActive(status.f4)
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

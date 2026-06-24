import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    let iconCache = IconCache()
    let trackpadMonitor = TrackpadGestureMonitor()
    let globalHotKey = GlobalHotKeyAdapter()
    let hotCornerMonitor = HotCornerMonitor()
    let launcherMouseMonitor = LauncherMouseMonitor()
    var window: NSWindow?
    var launcherLifecycle: LauncherLifecycle?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    var keyMonitor: Any?
    var statusRightClickMonitor: Any?
    var trackpadIntentLockedUntil = Date.distantPast
    lazy var statusMenu: NSMenu = makeStatusMenu()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchLog.app.info("applicationDidFinishLaunching")
        LaunchLog.line("app did finish launching")
        NSApp.setActivationPolicy(.accessory)
        makeWindow()
        state.refreshAppsAsync()
        applyAppIcon()
        applyMenuBarVisibility()
        state.requestAccessibilityPermission()
        startGlobalHotKey()
        startHotCornerMonitor()
        startTrackpadMonitor()
        startKeyMonitor()
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        state.refreshAccessibilityStatus()
        state.refreshLoginItemStatus()
    }

    func makeWindow() {
        LaunchLog.app.info("makeWindow")
        let frame = NSScreen.main?.frame ?? LaunchConstants.App.fallbackWindowFrame
        let window = LauncherPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.hidesOnDeactivate = false
        window.isFloatingPanel = false
        let presentationContainer = LauncherPresentationContainer()
        presentationContainer.wantsLayer = true

        let rootView = LauncherView(state: state).environment(\.iconCache, iconCache)
        let hosting = NSHostingView(rootView: rootView)
        hosting.safeAreaRegions = []
        hosting.autoresizingMask = [.width, .height]
        presentationContainer.addSubview(hosting)
        hosting.frame = presentationContainer.bounds

        window.contentView = presentationContainer
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .mainMenu
        self.window = window
        launcherMouseMonitor.configure(window: window, state: state)
        launcherLifecycle = LauncherLifecycle(state: state, window: window, mouseMonitor: launcherMouseMonitor)
        LaunchLog.line("window created frame=\(window.frame)")
        state.actions = LauncherActions(
            close: { [weak self] in self?.launcherLifecycle?.hide() },
            dismiss: { [weak self] in self?.launcherLifecycle?.dismiss() },
            canHandleUserDismissal: { [weak self] in self?.launcherLifecycle?.canHandleUserDismissal == true },
            launch: { [weak self] app in self?.launcherLifecycle?.launch(app) },
            showInFinder: { [weak self] app in self?.launcherLifecycle?.revealInFinder(app) },
            moveToTrash: { [weak self] app in self?.confirmMoveToTrash(app) },
            addToDock: { app in AppSystemAdapter.addToDock(app) },
            chooseAppSource: { [weak self] in self?.chooseAppSource() },
            applyWindowBrowsingMode: { [weak self] in self?.launcherLifecycle?.applyWindowBrowsingMode() },
            applyMenuBarVisibility: { [weak self] in self?.applyMenuBarVisibility() },
            applyAppIcon: { [weak self] in self?.applyAppIcon() },
            applyInputSettings: { [weak self] in self?.applyInputSettings() }
        )
    }
}

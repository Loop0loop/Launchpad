import AppKit
import Darwin
import LaunchpadCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    let iconCache = IconCache()
    let appCatalogMonitor = AppCatalogMonitor()
    let trackpadMonitor = TrackpadGestureMonitor()
    let showDesktopController = SystemShowDesktopController()
    let globalHotKey = GlobalHotKeyAdapter()
    let f4KeyTap = F4KeyTapMonitor()
    let hotCornerMonitor = HotCornerMonitor()
    let launcherMouseMonitor = LauncherMouseMonitor()
    let updater = AppUpdater()
    var window: NSWindow?
    var launcherLifecycle: LauncherLifecycle?
    var launcherContainer: LauncherPresentationContainer?
    var launcherHostingView: NSHostingView<AnyView>?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    var keyMonitor: Any?
    var modifierKeyMonitor: Any?
    var statusRightClickMonitor: Any?
    var trackpadIntentLockedUntil = Date.distantPast
    var ownsNativePinchGestures = false
    var terminationSignalSources: [DispatchSourceSignal] = []
    lazy var statusMenu: NSMenu = makeStatusMenu()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchLog.app.info("applicationDidFinishLaunching")
        LaunchLog.line("app did finish launching")
        #if DEBUG
        let fallbackBuildVariant = "development"
        #else
        let fallbackBuildVariant = "production"
        #endif
        let buildVariant = Bundle.main.object(forInfoDictionaryKey: "LaunchBuildVariant") as? String
            ?? fallbackBuildVariant
        LaunchLog.line("build variant=\(buildVariant) bundle=\(Bundle.main.bundleIdentifier ?? "command-line")")
        NSApp.setActivationPolicy(.accessory)
        installTerminationSignalHandlers()
        installMainMenu()
        makeWindow()
        state.refreshAppsAsync(
            priority: state.apps.isEmpty ? .userInitiated : .utility,
            delay: state.apps.isEmpty ? 0.15 : 1.5
        )
        startAppCatalogMonitor()
        applyAppIcon()
        applyMenuBarVisibility()
        prepareExclusiveTrackpadGestures()
        startGlobalHotKey()
        startHotCornerMonitor()
        startTrackpadMonitorDeferred()
        startKeyMonitor()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        state.refreshLoginItemStatus()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        terminationSignalSources.forEach { $0.cancel() }
        terminationSignalSources.removeAll()
        showDesktopController.stop()
        SystemTrackpadSettings.restoreNativeLaunchpadPinch()
        ownsNativePinchGestures = false
        return .terminateNow
    }

    private func installTerminationSignalHandlers() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            terminationSignalSources.append(source)
        }
    }

    @objc nonisolated private func activeSpaceDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.launcherLifecycle?.dismissForSystemGesture()
        }
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
        window.contentView = makeLauncherContainer()
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
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
            appSourcesChanged: { [weak self] in self?.startAppCatalogMonitor() },
            applyWindowBrowsingMode: { [weak self] in self?.launcherLifecycle?.applyWindowBrowsingMode() },
            applyMenuBarVisibility: { [weak self] in self?.applyMenuBarVisibility() },
            applyAppIcon: { [weak self] in self?.applyAppIcon() },
            applyInputSettings: { [weak self] in self?.applyInputSettings() },
            clearIconCache: { [weak self] in self?.iconCache.clear() },
            restoreLauncherRoot: { [weak self] in self?.setLauncherRoot(active: true) },
            releaseLauncherRoot: { [weak self] in self?.setLauncherRoot(active: false) }
        )
    }

    private func startAppCatalogMonitor() {
        let paths = AppCatalog.defaultRoots().map(\.path) + state.appSourcePaths
        appCatalogMonitor.start(paths: paths) { [weak self] in
            self?.state.refreshAppsAsync(priority: .utility, delay: 0.2)
        }
    }

    private func setLauncherRoot(active: Bool) {
        if active {
            let launcherContainer = ensureLauncherContainer()
            guard launcherHostingView == nil else { return }
            let root = LauncherView(state: state)
                .environmentObject(iconCache)
                .environmentObject(state.drag)
            let hosting = NSHostingView(rootView: AnyView(root))
            hosting.safeAreaRegions = []
            hosting.autoresizingMask = [.width, .height]
            launcherHostingView = hosting
            launcherContainer.addSubview(hosting)
            hosting.frame = launcherContainer.bounds
        } else {
            launcherHostingView?.rootView = AnyView(EmptyView())
            launcherHostingView?.removeFromSuperview()
            launcherHostingView = nil
            launcherContainer = nil
            window?.contentView = nil
        }
    }

    private func makeLauncherContainer() -> LauncherPresentationContainer {
        let presentationContainer = LauncherPresentationContainer()
        presentationContainer.wantsLayer = true
        launcherContainer = presentationContainer
        return presentationContainer
    }

    private func ensureLauncherContainer() -> LauncherPresentationContainer {
        if let launcherContainer { return launcherContainer }
        let presentationContainer = makeLauncherContainer()
        window?.contentView = presentationContainer
        return presentationContainer
    }
}

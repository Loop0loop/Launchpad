import AppKit
import LaunchCore
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
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
    private lazy var statusMenu: NSMenu = makeStatusMenu()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchLog.app.info("applicationDidFinishLaunching")
        LaunchLog.line("app did finish launching")
        NSApp.setActivationPolicy(.accessory)
        makeWindow()
        makeStatusItem()
        state.requestAccessibilityPermission()
        startGlobalHotKey()
        startHotCornerMonitor()
        startTrackpadMonitor()
        startKeyMonitor()
    }

    func makeWindow() {
        LaunchLog.app.info("makeWindow")
        let frame = NSScreen.main?.frame ?? LaunchConstants.App.fallbackWindowFrame
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
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
        state.closeLauncher = { [weak self] in self?.launcherLifecycle?.hide() }
        state.dismissLauncher = { [weak self] in self?.launcherLifecycle?.dismiss() }
        state.launchApp = { [weak self] app in self?.launcherLifecycle?.launch(app) }
        state.showAppInFinder = { [weak self] app in self?.launcherLifecycle?.revealInFinder(app) }
        state.moveAppToTrash = { [weak self] app in self?.confirmMoveToTrash(app) }
        state.addAppToDock = { app in AppSystemAdapter.addToDock(app) }
        state.chooseAppSource = { [weak self] in self?.chooseAppSource() }
        state.applyWindowBrowsingMode = { [weak self] in self?.launcherLifecycle?.applyWindowBrowsingMode() }
    }

    func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else {
            LaunchLog.line("status item button missing")
            return
        }
        if let icon = Self.menuBarImage() {
            button.image = icon
            button.title = ""
        } else {
            button.title = LaunchConstants.App.menuBarTitle
        }
        button.target = self
        button.action = #selector(statusBarClicked(_:))
        button.sendAction(on: [.leftMouseUp])
        startStatusRightClickMonitor(for: button)
        LaunchLog.line("status item ready")
    }

    /// Menu bar glyph as a template image so macOS tints it (white on a dark menu bar).
    private static func menuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        addStatusMenuItem(menu, title: LaunchConstants.Menu.toggle, action: #selector(toggleLauncher), key: LaunchConstants.Menu.toggleKey)
        addStatusMenuItem(menu, title: LaunchConstants.Menu.settings, action: #selector(showSettings), key: LaunchConstants.Menu.settingsKey)
        addStatusMenuItem(menu, title: LaunchConstants.Menu.refreshApps, action: #selector(refreshApps), key: LaunchConstants.Menu.refreshKey)
        addStatusMenuItem(menu, title: LaunchConstants.Menu.sortByName, action: #selector(sortAppsByName), key: LaunchConstants.Menu.sortByNameKey)
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: LaunchConstants.Menu.quit, action: #selector(NSApp.terminate), keyEquivalent: LaunchConstants.Menu.quitKey)
        quit.target = NSApp
        return menu
    }

    private func addStatusMenuItem(_ menu: NSMenu, title: String, action: Selector, key: String) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
    }

    @objc nonisolated func statusBarClicked(_ sender: NSStatusBarButton) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                LaunchLog.line("status bar action dropped self")
                return
            }
            LaunchLog.line("status bar left click")
            handleToggleLauncher()
        }
    }

    func startStatusRightClickMonitor(for button: NSStatusBarButton) {
        statusRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { [weak self, weak button] event in
            guard let self, let button, event.window === button.window else { return event }
            let point = button.convert(event.locationInWindow, from: nil)
            guard button.bounds.contains(point) else { return event }
            if event.type == .rightMouseUp {
                LaunchLog.line("status bar right click")
                statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            }
            return nil
        }
    }

    @objc nonisolated func toggleLauncher() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            handleToggleLauncher()
        }
    }

    private func handleToggleLauncher() {
        LaunchLog.line("toggle launcher requested")
        launcherLifecycle?.toggle()
    }

    @objc nonisolated func refreshApps() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            handleRefreshApps()
        }
    }

    private func handleRefreshApps() {
        state.refreshApps()
        iconCache.clear()
    }

    @objc nonisolated func sortAppsByName() {
        DispatchQueue.main.async { [weak self] in
            self?.handleSortAppsByName()
        }
    }

    private func handleSortAppsByName() {
        state.applyNameSort()
    }

    func confirmMoveToTrash(_ app: LaunchApp) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = LaunchConstants.Alerts.moveToTrashTitle(appName: app.name)
        alert.informativeText = app.path
        alert.addButton(withTitle: LaunchConstants.Menu.moveToTrash)
        alert.addButton(withTitle: LaunchConstants.Alerts.cancel)

        guard let window else {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            moveToTrash(app)
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.moveToTrash(app)
        }
    }

    private func moveToTrash(_ app: LaunchApp) {
        do {
            try AppSystemAdapter.moveToTrash(app)
            handleRefreshApps()
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.messageText = LaunchConstants.Alerts.moveToTrashFailed
            errorAlert.runModal()
        }
    }

    @objc nonisolated func showSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            handleShowSettings()
        }
    }

    private func handleShowSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .init(
                    x: 0,
                    y: 0,
                    width: LaunchConstants.Settings.width,
                    height: LaunchConstants.Settings.height
                ),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = LaunchConstants.App.settingsTitle
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.hasShadow = true
            let hosting = NSHostingView(rootView: SettingsView(state: state))
            hosting.safeAreaRegions = []
            window.contentView = hosting
            settingsWindow = window
        }

        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func chooseAppSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = LaunchConstants.Settings.addAppSource

        if panel.runModal() == .OK, let url = panel.url {
            state.addAppSource(url.path)
        }
    }

    func startTrackpadMonitor() {
        LaunchLog.line("start trackpad monitor")
        trackpadMonitor.start { [weak self] isActive in
            LaunchLog.line("trackpad gate active=\(isActive)")
            self?.state.setTrackpadGateActive(isActive)
        } onIntent: { [weak self] intent in
            guard let self else { return }
            LaunchLog.line("trackpad intent=\(intent)")
            switch intent {
            case .open:
                self.launcherLifecycle?.show()
            case .close:
                if self.launcherLifecycle?.isVisible == true {
                    self.launcherLifecycle?.hide()
                }
            case .previousPage:
                if self.launcherLifecycle?.isVisible == true {
                    withAnimation(LaunchConstants.Animation.spring) {
                        self.state.changePage(-1)
                    }
                }
            case .nextPage:
                if self.launcherLifecycle?.isVisible == true {
                    withAnimation(LaunchConstants.Animation.spring) {
                        self.state.changePage(1)
                    }
                }
            }
        }
    }

    func startGlobalHotKey() {
        LaunchLog.line("start global hotkey")
        let status = globalHotKey.start {
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
        hotCornerMonitor.start { [weak self] in
            self?.launcherLifecycle?.show()
        }
    }

    func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.launcherLifecycle?.isVisible == true else { return event }
            return self.handleLauncherKey(event)
        }
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
}

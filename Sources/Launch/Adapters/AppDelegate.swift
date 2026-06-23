import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    let iconCache = IconCache()
    let trackpadMonitor = TrackpadGestureMonitor()
    let globalHotKey = GlobalHotKeyAdapter()
    var window: NSWindow?
    var launcherLifecycle: LauncherLifecycle?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?
    var keyMonitor: Any?
    private lazy var statusMenu: NSMenu = makeStatusMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeWindow()
        makeStatusItem()
        state.requestAccessibilityPermission()
        startGlobalHotKey()
        startTrackpadMonitor()
        startKeyMonitor()
    }

    func makeWindow() {
        let frame = NSScreen.main?.frame ?? LaunchConstants.App.fallbackWindowFrame
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let rootView = LauncherView(state: state).environment(\.iconCache, iconCache)
        let hosting = NSHostingView(rootView: rootView)
        hosting.safeAreaRegions = []
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .mainMenu
        self.window = window
        launcherLifecycle = LauncherLifecycle(state: state, window: window)
        state.closeLauncher = { [weak self] in self?.launcherLifecycle?.hide() }
        state.dismissLauncher = { [weak self] in self?.launcherLifecycle?.dismiss() }
        state.launchApp = { [weak self] app in self?.launcherLifecycle?.launch(app) }
        state.showAppInFinder = { [weak self] app in self?.launcherLifecycle?.revealInFinder(app) }
        state.chooseAppSource = { [weak self] in self?.chooseAppSource() }
    }

    func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.title = LaunchConstants.App.menuBarTitle
        button.target = self
        button.action = #selector(statusBarClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: LaunchConstants.Menu.toggle, action: #selector(toggleLauncher), keyEquivalent: LaunchConstants.Menu.toggleKey)
        menu.addItem(withTitle: LaunchConstants.Menu.settings, action: #selector(showSettings), keyEquivalent: LaunchConstants.Menu.settingsKey)
        menu.addItem(withTitle: LaunchConstants.Menu.refreshApps, action: #selector(refreshApps), keyEquivalent: LaunchConstants.Menu.refreshKey)
        menu.addItem(withTitle: LaunchConstants.Menu.sortByName, action: #selector(sortAppsByName), keyEquivalent: LaunchConstants.Menu.sortByNameKey)
        menu.addItem(.separator())
        menu.addItem(withTitle: LaunchConstants.Menu.quit, action: #selector(NSApp.terminate), keyEquivalent: LaunchConstants.Menu.quitKey)
        return menu
    }

    @objc func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleLauncher()
            return
        }

        if event.type == .rightMouseUp {
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 4),
                in: sender
            )
            return
        }

        toggleLauncher()
    }

    @objc func toggleLauncher() {
        launcherLifecycle?.toggle()
    }

    @objc func refreshApps() {
        state.refreshApps()
        iconCache.clear()
    }

    @objc func sortAppsByName() {
        state.applyNameSort()
    }

    @objc func showSettings() {
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
        trackpadMonitor.start { [weak self] isActive in
            self?.state.setTrackpadGateActive(isActive)
        } onIntent: { [weak self] intent in
            guard let self else { return }
            switch intent {
            case .open:
                self.launcherLifecycle?.show()
            case .close:
                if self.launcherLifecycle?.isVisible == true {
                    self.launcherLifecycle?.hide()
                }
            case .previousPage:
                if self.launcherLifecycle?.isVisible == true {
                    self.state.changePage(-1)
                }
            case .nextPage:
                if self.launcherLifecycle?.isVisible == true {
                    self.state.changePage(1)
                }
            }
        }
    }

    func startGlobalHotKey() {
        let status = globalHotKey.start {
            [weak self] in
            self?.launcherLifecycle?.toggle()
        } f4Action: {
            [weak self] in
            self?.launcherLifecycle?.toggle()
        }
        state.setGlobalHotKeyActive(status.toggle)
        state.setF4KeyActive(status.f4)
    }

    func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.launcherLifecycle?.isVisible == true else { return event }
            return self.handleLauncherKey(event)
        }
    }

    func handleLauncherKey(_ event: NSEvent) -> NSEvent? {
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
            state.moveSelection(by: LaunchConstants.Launcher.columns)
            return nil
        case 126:
            state.moveSelection(by: -LaunchConstants.Launcher.columns)
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

import AppKit

extension AppDelegate {
    func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else {
            LaunchLog.line("status item button missing")
            return
        }
        if let icon = menuBarImage() {
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

    func applyMenuBarVisibility() {
        if state.showMenuBarIcon {
            if statusItem == nil { makeStatusItem() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func applyAppIcon() {
        if let image = state.appIcon.image() {
            NSApp.applicationIconImage = image
        }
        if let image = menuBarImage(), let button = statusItem?.button {
            button.image = image
            button.title = ""
        }
    }

    private func menuBarImage() -> NSImage? {
        let source = state.appIcon.image() ?? bundledMenuBarImage()
        guard let source else { return nil }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        defer { image.unlockFocus() }
        source.draw(
            in: NSRect(x: 1, y: 1, width: 16, height: 16),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private func bundledMenuBarImage() -> NSImage? {
        guard let url = AppIconOption.resourceURL(named: "MenuBarIcon", extension: "png") else { return nil }
        return NSImage(contentsOf: url)
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

    func handleToggleLauncher() {
        LaunchLog.line("toggle launcher requested")
        launcherLifecycle?.toggle()
    }

    @objc nonisolated func refreshApps() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            handleRefreshApps()
        }
    }

    func handleRefreshApps() {
        state.refreshApps()
        iconCache.clear()
    }

    @objc nonisolated func sortAppsByName() {
        DispatchQueue.main.async { [weak self] in
            self?.handleSortAppsByName()
        }
    }

    private func handleSortAppsByName() {
        state.sortMode = .name
        state.applyNameSort()
    }
}

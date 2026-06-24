import AppKit
import SwiftUI

extension AppDelegate {
    @objc nonisolated func showSettings() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            handleShowSettings()
        }
    }

    private func handleShowSettings() {
        if settingsWindow == nil {
            let window = NSPanel(
                contentRect: .init(
                    x: 0,
                    y: 0,
                    width: LaunchConstants.Settings.width,
                    height: LaunchConstants.Settings.height
                ),
                styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.title = LaunchConstants.App.settingsTitle
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.hasShadow = true
            window.isFloatingPanel = true
            window.level = .statusBar
            let hosting = NSHostingView(rootView: SettingsView(state: state))
            hosting.safeAreaRegions = []
            window.contentView = hosting
            settingsWindow = window
        }

        settingsWindow?.center()

        if let launcherWindow = self.window, let settings = settingsWindow {
            if settings.parent == nil {
                launcherWindow.addChildWindow(settings, ordered: .above)
            }
        }

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
}


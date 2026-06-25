import AppKit
import LaunchpadCore

extension AppDelegate {
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
}


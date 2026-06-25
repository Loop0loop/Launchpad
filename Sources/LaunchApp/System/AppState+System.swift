import Foundation
import LaunchpadCore

extension AppState {
    func launch(_ app: LaunchApp) {
        actions.launch(app)
    }

    func revealInFinder(_ app: LaunchApp) {
        actions.showInFinder(app)
    }

    func moveToTrash(_ app: LaunchApp) {
        actions.moveToTrash(app)
    }

    func addToDock(_ app: LaunchApp) {
        actions.addToDock(app)
    }

    func hide(_ app: LaunchApp) {
        hiddenAppIDs.insert(app.id)
        persistHiddenApps()
        ensureSelection()
    }

    func unhide(_ id: String) {
        hiddenAppIDs.remove(id)
        persistHiddenApps()
        ensureSelection()
    }

    fileprivate func persistHiddenApps() {
        UserDefaults.standard.set(Array(hiddenAppIDs), forKey: LaunchConstants.Storage.hiddenAppsKey)
    }
}

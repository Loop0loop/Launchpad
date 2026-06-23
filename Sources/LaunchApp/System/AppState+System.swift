import LaunchCore

extension AppState {
    func launch(_ app: LaunchApp) {
        launchApp?(app)
    }

    func revealInFinder(_ app: LaunchApp) {
        showAppInFinder?(app)
    }

    func moveToTrash(_ app: LaunchApp) {
        moveAppToTrash?(app)
    }

    func addToDock(_ app: LaunchApp) {
        addAppToDock?(app)
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
        LayoutPersistenceAdapter.set(Array(hiddenAppIDs), forKey: LaunchConstants.Storage.hiddenAppsKey)
    }
}

import Foundation
import LaunchCore

@MainActor
final class AppState: ObservableObject {
    @Published var apps: [LaunchApp] = []
    @Published var folders: [LaunchFolder] = []
    @Published var query = "" {
        didSet {
            handleQueryChange(oldValue: oldValue)
        }
    }
    @Published var currentPage = 0
    @Published var selectedItemID: String?
    @Published private(set) var keyboardSelectionActive = false
    @Published var draggedAppID: String?
    @Published var openFolder: LaunchFolder?
    @Published var launchAtLogin = false
    @Published var loginItemError: String?
    @Published var accessibilityTrusted = false
    @Published var accessibilityState: PermissionState = .unknown
    @Published var globalHotKeyState: PermissionState = .unknown
    @Published var f4KeyState: PermissionState = .unknown
    @Published var trackpadGateState: TrackpadGateState = .unknown
    @Published var launcherVisible = false
    @Published var appSourcePaths = AppSourceStore.load()
    @Published var hiddenAppIDs = Set(LayoutPersistenceAdapter.stringArray(forKey: LaunchConstants.Storage.hiddenAppsKey))
    @Published var gridLayout = GridLayoutStore.load() {
        didSet {
            guard oldValue != gridLayout else { return }
            GridLayoutStore.save(gridLayout)
            currentPage = min(currentPage, pageCount - 1)
            ensureSelection()
        }
    }
    @Published var displayMode = LauncherDisplayModeStore.load() {
        didSet {
            guard oldValue != displayMode else { return }
            LauncherDisplayModeStore.save(displayMode)
            currentPage = 0
        }
    }
    @Published var windowBrowsingMode = UserDefaults.standard.bool(forKey: LaunchConstants.Storage.windowBrowsingModeKey) {
        didSet {
            guard oldValue != windowBrowsingMode else { return }
            UserDefaults.standard.set(windowBrowsingMode, forKey: LaunchConstants.Storage.windowBrowsingModeKey)
            applyWindowBrowsingMode?()
        }
    }
    @Published var appearance = AppearanceStore.load() {
        didSet {
            guard oldValue != appearance else { return }
            AppearanceStore.save(appearance)
        }
    }
    @Published private var order: [String] = []

    private let layoutStore = LayoutStore()
    private var pageBeforeSearch = 0
    private var selectionBeforeSearch: String?
    var closeLauncher: (() -> Void)?
    var dismissLauncher: (() -> Void)?
    var launchApp: ((LaunchApp) -> Void)?
    var showAppInFinder: ((LaunchApp) -> Void)?
    var moveAppToTrash: ((LaunchApp) -> Void)?
    var addAppToDock: ((LaunchApp) -> Void)?
    var chooseAppSource: (() -> Void)?
    var applyWindowBrowsingMode: (() -> Void)?

    init() {
        folders = layoutStore.loadFolders()
        order = layoutStore.loadOrder()
        refreshLoginItemStatus()
        refreshAccessibilityStatus()
        refreshApps()
    }

    var visibleApps: [LaunchApp] {
        let shown = apps.filter { !hiddenAppIDs.contains($0.id) }
        guard !query.isEmpty else { return shown }
        return AppSearch.rankedApps(shown, matching: query)
    }

    var visibleItems: [LauncherItem] {
        if !query.isEmpty {
            return visibleApps.map(LauncherItem.app)
        }

        let folderedIDs = Set(folders.flatMap(\.appIDs))
        let rootApps = apps.filter { !folderedIDs.contains($0.id) && !hiddenAppIDs.contains($0.id) }
        let appItems = rootApps.map { LauncherItem.app($0) }
        let folderItems = folders.map { folder in
            LauncherItem.folder(folder, folder.appIDs.compactMap(appByID).filter { !hiddenAppIDs.contains($0.id) })
        }
        let allItems = appItems + folderItems
        let byID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        let orderedIDs = Set(ordered.map(\.id))
        return ordered + allItems.filter { !orderedIDs.contains($0.id) }
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(visibleItems.count) / Double(pageSize))))
    }

    var gridColumns: Int {
        gridLayout.columns
    }

    private var pageSize: Int {
        gridLayout.pageSize
    }

    var pageItems: [LauncherItem] {
        items(forPage: currentPage)
    }

    func items(forPage page: Int) -> [LauncherItem] {
        Array(visibleItems.dropFirst(page * pageSize).prefix(pageSize))
    }

    func refreshApps() {
        apps = CatalogStore.scanApps(extraRoots: appSourcePaths)
        let cleanup = layoutStore.cleanup(folders: folders, order: order, validAppIDs: Set(apps.map(\.id)))
        folders = cleanup.folders
        openFolder = openFolder.flatMap { open in folders.first { $0.id == open.id } }
        order = cleanup.order
        layoutStore.saveFolders(folders)
        saveOrder()
        ensureSelection()
    }

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

    private func persistHiddenApps() {
        LayoutPersistenceAdapter.set(Array(hiddenAppIDs), forKey: LaunchConstants.Storage.hiddenAppsKey)
    }

    func requestAppSource() {
        chooseAppSource?()
    }

    func addAppSource(_ path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !appSourcePaths.contains(standardized) else { return }
        appSourcePaths.append(standardized)
        AppSourceStore.save(appSourcePaths)
        refreshApps()
    }

    func removeAppSource(_ path: String) {
        appSourcePaths.removeAll { $0 == path }
        AppSourceStore.save(appSourcePaths)
        refreshApps()
    }

    func launchSelected() {
        guard let item = selectedItem() ?? visibleItems.first else { return }

        switch item {
        case .app(let app):
            launch(app)
        case .folder(let folder, _):
            openFolder = folder
        }
    }

    func appendSearchText(_ text: String) {
        guard !text.isEmpty else { return }
        closeFolder()
        query += text
    }

    func deleteSearchBackward() {
        guard !query.isEmpty else { return }
        query.removeLast()
    }

    func handleEscape() {
        if openFolder != nil {
            closeFolder()
        } else if !query.isEmpty {
            clearSearch()
        } else {
            closeLauncher?()
        }
    }

    func dismissFromBackground() {
        handleEscape()
    }

    func moveSelection(by delta: Int) {
        keyboardSelectionActive = true
        let items = visibleItems
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        let currentIndex = selectedItemID.flatMap { id in items.firstIndex { $0.id == id } } ?? currentPage * pageSize
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        let nextPage = nextIndex / pageSize
        if nextPage != currentPage {
            currentPage = nextPage
        }
        selectedItemID = items[nextIndex].id
    }

    func ensureSelection() {
        let ids = Set(visibleItems.map(\.id))
        if keyboardSelectionActive, let selectedItemID, ids.contains(selectedItemID) { return }
        if keyboardSelectionActive {
            selectedItemID = visibleItems.first?.id
        }
    }

    func clearSelection() {
        keyboardSelectionActive = false
        selectedItemID = nil
    }

    func showsKeyboardSelection(for id: String) -> Bool {
        keyboardSelectionActive && selectedItemID == id
    }

    func move(_ id: String, before targetID: String) {
        guard query.isEmpty else { return }
        let nextOrder = LayoutOrder.move(id, before: targetID, in: visibleItems.map(\.id))
        saveOrder(nextOrder)
    }

    func createFolder(draggedID: String, targetID: String) {
        guard folders.allSatisfy({ !$0.appIDs.contains(draggedID) && !$0.appIDs.contains(targetID) }) else {
            return
        }

        let result = FolderLayout.createFolder(
            id: "folder-\(UUID().uuidString)",
            draggedID: draggedID,
            targetID: targetID,
            folders: folders,
            order: visibleItems.map(\.id)
        )
        folders = result.folders
        layoutStore.saveFolders(folders)
        saveOrder(result.order)
        openFolder = folders.last
    }

    func appByID(_ id: String) -> LaunchApp? {
        apps.first { $0.id == id }
    }

    func closeFolder() {
        openFolder = nil
    }

    func apps(in folder: LaunchFolder) -> [LaunchApp] {
        folder.appIDs.compactMap(appByID)
    }

    func itemName(_ id: String) -> String {
        appByID(id)?.name ?? id
    }

    func saveOrder(_ order: [String]? = nil) {
        self.order = order ?? visibleItems.map(\.id)
        layoutStore.saveOrder(self.order)
    }

    func applyNameSort() {
        guard query.isEmpty else { return }
        let sortedRootIDs = visibleItems.map(\.id).sorted { lhs, rhs in
            itemName(lhs).localizedStandardCompare(itemName(rhs)) == .orderedAscending
        }
        saveOrder(sortedRootIDs)
    }

    func importNativeLaunchpadLayout() {
        guard query.isEmpty else { return }
        let rootIDs = visibleItems.map(\.id)
        let rootIDSet = Set(rootIDs)
        let imported = NativeLaunchpadLayoutImporter.importOrder(apps: apps).filter(rootIDSet.contains)
        guard !imported.isEmpty else { return }
        saveOrder(imported + rootIDs.filter { !imported.contains($0) })
    }

    func refreshLoginItemStatus() {
        launchAtLogin = LoginItemAdapter.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil

        do {
            try LoginItemAdapter.setEnabled(enabled)
        } catch {
            loginItemError = error.localizedDescription
        }

        refreshLoginItemStatus()
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityAdapter.isTrusted
        accessibilityState = accessibilityTrusted ? .allowed : .required
    }

    func requestAccessibilityPermission() {
        accessibilityTrusted = AccessibilityAdapter.requestPermission()
        accessibilityState = accessibilityTrusted ? .allowed : .needsApproval
    }

    func setTrackpadGateActive(_ isActive: Bool) {
        trackpadGateState = isActive ? .exactPinch : .fallbackPinch
    }

    func setGlobalHotKeyActive(_ isActive: Bool) {
        globalHotKeyState = isActive ? .allowed : .required
    }

    func setF4KeyActive(_ isActive: Bool) {
        f4KeyState = isActive ? .allowed : .required
    }

    private var pageChangeLockedUntil = Date.distantPast

    func goToPage(_ page: Int) {
        guard Date() >= pageChangeLockedUntil else { return }
        let nextPage = min(max(page, 0), pageCount - 1)
        guard nextPage != currentPage else { return }
        currentPage = nextPage
        if keyboardSelectionActive {
            selectedItemID = items(forPage: nextPage).first?.id
        }
        pageChangeLockedUntil = Date().addingTimeInterval(LaunchConstants.Launcher.pageChangeCooldown)
    }

    func changePage(_ delta: Int) {
        guard delta != 0 else { return }
        guard Date() >= pageChangeLockedUntil else { return }
        let nextPage = min(max(currentPage + delta, 0), pageCount - 1)
        guard nextPage != currentPage else { return }
        currentPage = nextPage
        if keyboardSelectionActive {
            selectedItemID = items(forPage: nextPage).first?.id
        }
        pageChangeLockedUntil = Date().addingTimeInterval(LaunchConstants.Launcher.pageChangeCooldown)
    }

    func dropApp(_ draggedID: String, on targetID: String) {
        guard query.isEmpty else { return }
        if draggedID == targetID { return }

        if appByID(targetID) != nil, appByID(draggedID) != nil {
            createFolder(draggedID: draggedID, targetID: targetID)
        } else {
            move(draggedID, before: targetID)
        }
    }

}

private extension AppState {
    func selectedItem() -> LauncherItem? {
        guard let selectedItemID else { return nil }
        return visibleItems.first { $0.id == selectedItemID }
    }

    func handleQueryChange(oldValue: String) {
        if oldValue.isEmpty, !query.isEmpty {
            pageBeforeSearch = currentPage
            selectionBeforeSearch = selectedItemID
            currentPage = 0
            keyboardSelectionActive = true
            selectedItemID = visibleItems.first?.id
        } else if !oldValue.isEmpty, query.isEmpty {
            currentPage = min(pageBeforeSearch, pageCount - 1)
            selectedItemID = selectionBeforeSearch
            ensureSelection()
        } else if !query.isEmpty {
            currentPage = 0
            selectedItemID = visibleItems.first?.id
        }
    }

    func clearSearch() {
        query = ""
    }
}

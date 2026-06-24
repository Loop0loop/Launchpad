import CoreGraphics
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
    @Published var keyboardSelectionActive = false
    @Published var draggingItemID: String?
    @Published var dragHoverTargetID: String?
    @Published var dragTranslation: CGSize = .zero
    @Published var openFolder: LaunchFolder?
    /// True while an app is being dragged past the pull-out threshold inside an open folder:
    /// the folder surface dissolves so only the dragged app stays in hand.
    @Published var folderDragPullingOut = false
    @Published var launchAtLogin = false
    @Published var hotkeyDisplay = UserDefaults.standard.string(forKey: "settings.hotkeyDisplay") ?? "⌘2" {
        didSet { UserDefaults.standard.set(hotkeyDisplay, forKey: "settings.hotkeyDisplay") }
    }
    @Published var systemF4KeyEnabled = (UserDefaults.standard.object(forKey: "settings.systemF4KeyEnabled") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(systemF4KeyEnabled, forKey: "settings.systemF4KeyEnabled")
            actions.applyInputSettings()
        }
    }
    @Published var trackpadSetting = UserDefaults.standard.string(forKey: "settings.trackpadSetting") ?? "Pinch with 4 or 5 fingers" {
        didSet {
            UserDefaults.standard.set(trackpadSetting, forKey: "settings.trackpadSetting")
            actions.applyInputSettings()
        }
    }
    @Published var hotCornerSetting = UserDefaults.standard.string(forKey: "settings.hotCornerSetting") ?? "Top Left" {
        didSet {
            UserDefaults.standard.set(hotCornerSetting, forKey: "settings.hotCornerSetting")
            actions.applyInputSettings()
        }
    }
    @Published var loginItemError: String?
    @Published var accessibilityTrusted = false
    @Published var accessibilityState: PermissionState = .unknown
    @Published var globalHotKeyState: PermissionState = .unknown
    @Published var f4KeyState: PermissionState = .unknown
    @Published var trackpadGateState: TrackpadGateState = .unknown
    @Published var launcherVisible = false
    @Published var pageDragOffset: CGFloat = 0
    let searchFocus = SearchFocusController()
    @Published var appSourcePaths = AppSourceStore.load()
    @Published var hiddenAppIDs = Set(UserDefaults.standard.stringArray(forKey: LaunchConstants.Storage.hiddenAppsKey) ?? [])
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
            actions.applyWindowBrowsingMode()
        }
    }
    @Published var appearance = AppearanceStore.load() {
        didSet {
            guard oldValue != appearance else { return }
            AppearanceStore.save(appearance)
        }
    }
    @Published var showMenuBarIcon = (UserDefaults.standard.object(forKey: LaunchConstants.Storage.showMenuBarIconKey) as? Bool) ?? true {
        didSet {
            guard oldValue != showMenuBarIcon else { return }
            UserDefaults.standard.set(showMenuBarIcon, forKey: LaunchConstants.Storage.showMenuBarIconKey)
            actions.applyMenuBarVisibility()
        }
    }
    @Published var showMenuBarInLauncher = (UserDefaults.standard.object(forKey: LaunchConstants.Storage.showMenuBarInLauncherKey) as? Bool) ?? false {
        didSet {
            guard oldValue != showMenuBarInLauncher else { return }
            UserDefaults.standard.set(showMenuBarInLauncher, forKey: LaunchConstants.Storage.showMenuBarInLauncherKey)
            actions.applyWindowBrowsingMode()
        }
    }
    @Published var showDockInLauncher = (UserDefaults.standard.object(forKey: LaunchConstants.Storage.showDockInLauncherKey) as? Bool) ?? false {
        didSet {
            guard oldValue != showDockInLauncher else { return }
            UserDefaults.standard.set(showDockInLauncher, forKey: LaunchConstants.Storage.showDockInLauncherKey)
            actions.applyWindowBrowsingMode()
        }
    }
    @Published var appIcon = AppIconOption.load() {
        didSet {
            guard oldValue != appIcon else { return }
            appIcon.save()
            actions.applyAppIcon()
        }
    }
    @Published var sortMode = SortMode.load() {
        didSet {
            guard oldValue != sortMode else { return }
            sortMode.save()
            if sortMode == .name { applyNameSort() }
        }
    }
    @Published var appLanguage = AppLanguage.load() {
        didSet {
            guard oldValue != appLanguage else { return }
            appLanguage.save()
            Localized.language = appLanguage
            refreshAppsAsync()
        }
    }
    @Published var order: [String] = []

    var pageBeforeSearch = 0
    var selectionBeforeSearch: String?
    var pageChangeLockedUntil = Date.distantPast
    var folderReopenLockedUntil = Date.distantPast
    var backgroundDismissLockedUntil = Date.distantPast
    var catalogRefreshTask: Task<Void, Never>?
    var actions = LauncherActions()

    init() {
        Localized.language = appLanguage
        folders = LayoutStore.loadFolders()
        order = LayoutStore.loadOrder()
        apps = CatalogStore.loadCachedApps()
        refreshLoginItemStatus()
        refreshAccessibilityStatus()
    }

    deinit {
        catalogRefreshTask?.cancel()
    }

}

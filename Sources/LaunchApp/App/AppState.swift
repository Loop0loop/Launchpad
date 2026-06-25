import CoreGraphics
import Foundation
import LaunchpadCore

@MainActor
final class AppState: ObservableObject {
    @Published var apps: [LaunchApp] = [] {
        didSet { invalidateVisibleItems() }
    }
    @Published var folders: [LaunchFolder] = [] {
        didSet { invalidateVisibleItems() }
    }
    @Published var query = "" {
        didSet {
            // 3B: 검색 랭킹은 80ms debounce. 빈 문자열(검색 종료)은 즉시 반영.
            if query.isEmpty {
                searchDebounceTask?.cancel()
                searchDebounceTask = nil
                let prevEmpty = searchQuery.isEmpty
                searchQuery = ""
                invalidateVisibleItems()
                handleQueryChange(prevSearchEmpty: prevEmpty)
            } else {
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard let self, !Task.isCancelled else { return }
                    let prevEmpty = self.searchQuery.isEmpty
                    self.searchQuery = self.query
                    self.invalidateVisibleItems()
                    self.handleQueryChange(prevSearchEmpty: prevEmpty)
                }
            }
        }
    }
    /// debounce 적용된 검색어. visibleApps/visibleItems는 이쪽을 본다(query 자체는 입력창용 즉시값).
    @Published var searchQuery = ""
    @Published var currentPage = 0
    @Published var selectedItemID: String?
    @Published var keyboardSelectionActive = false
    @Published var draggingItemID: String?
    /// 매 프레임 갱신되는 드래그 위치/머지 대상은 DragModel로 격리(그리드 전체 리렌더 방지).
    /// 로직 코드는 기존 이름 그대로 쓰도록 forwarder를 둔다. begin/end에만 바뀌는
    /// draggingItemID는 renderedPages가 의존하므로 AppState에 남겨 그리드를 갱신한다.
    let drag = DragModel()
    var dragHoverTargetID: String? {
        get { drag.hoverTargetID }
        set { drag.hoverTargetID = newValue }
    }
    var dragTranslation: CGSize {
        get { drag.translation }
        set { drag.translation = newValue }
    }
    /// Live-reflow target slot while dragging a grid icon. Changes only when the pointer
    /// crosses into a new slot, so the grid rebuilds on slot crossings, not every frame.
    @Published var dragInsertionIndex: Int?
    @Published var openFolder: LaunchFolder?
    /// 드래그 좌표 변환용. 둘 다 `.global` 좌표. launcherGrid = 그리드 컨테이너, folderGrid = 열린 폴더 그리드.
    @Published var launcherGridFrame: CGRect = .zero
    @Published var folderGridFrame: CGRect = .zero
    @Published var folderDragPullingOut = false
    /// 폴더 내부 재배열 라이브 프리뷰. 드래그 중인 앱과 목표 슬롯. 슬롯을 가로지를 때만 바뀌어
    /// 다른 아이콘이 실시간으로 비켜난다(메인 그리드 dragInsertionIndex와 동일 패턴).
    @Published var folderReorderingID: String?
    @Published var folderDragInsertionIndex: Int?
    var dragIntent = DragIntent.placing
    var dragMergeConfirmTask: Task<Void, Never>?
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
    @Published var hotCornerSetting = UserDefaults.standard.string(forKey: "settings.hotCornerSetting") ?? "Disabled" {
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
    var pageDragOffset: CGFloat {
        get { drag.pageOffset }
        set { drag.pageOffset = newValue }
    }
    let searchFocus = SearchFocusController()
    @Published var appSourcePaths = AppSourceStore.load()
    @Published var hiddenAppIDs = Set(UserDefaults.standard.stringArray(forKey: LaunchConstants.Storage.hiddenAppsKey) ?? []) {
        didSet { invalidateVisibleItems() }
    }
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
    @Published var order: [String] = [] {
        didSet { invalidateVisibleItems() }
    }

    var pageBeforeSearch = 0
    var selectionBeforeSearch: String?
    var pageChangeLockedUntil = Date.distantPast
    var folderReopenLockedUntil = Date.distantPast
    var backgroundDismissLockedUntil = Date.distantPast
    var catalogRefreshTask: Task<Void, Never>?
    var searchDebounceTask: Task<Void, Never>?
    /// 드래그 중 폴더 위에 머물 때 0.45s 후 폴더를 자동으로 여는 hover 타이머.
    var folderHoverTargetID: String?
    var folderHoverOpenTask: Task<Void, Never>?
    var visibleItemsCache: [LauncherItem]?
    var actions = LauncherActions()

    init() {
        Localized.language = appLanguage
        folders = LayoutStore.loadFolders()
        order = LayoutStore.loadOrder()
        apps = CatalogStore.loadCachedApps()
        refreshLoginItemStatus()
    }

    deinit {
        catalogRefreshTask?.cancel()
        dragMergeConfirmTask?.cancel()
        folderHoverOpenTask?.cancel()
    }

    func invalidateVisibleItems() {
        visibleItemsCache = nil
    }

}

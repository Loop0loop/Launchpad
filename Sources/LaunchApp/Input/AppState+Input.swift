import Foundation
import LaunchpadCore

extension AppState {
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
        LaunchLog.line("handleEscape openFolder=\(openFolder?.id ?? "nil") query=\(query.isEmpty ? "empty" : query)")
        guard launcherVisible else {
            LaunchLog.line("handleEscape ignored launcher not visible")
            return
        }
        if isDraggingLauncherItem {
            cancelDrag()
        } else if openFolder != nil {
            closeFolder()
        } else if !query.isEmpty {
            clearSearch()
        } else {
            actions.close()
        }
    }

    func dismissFromBackground() {
        guard actions.canHandleUserDismissal() else {
            LaunchLog.line("background dismiss ignored during transition")
            return
        }
        guard launcherVisible else {
            LaunchLog.line("background dismiss ignored launcher not visible")
            return
        }
        guard !isDraggingLauncherItem else {
            LaunchLog.line("background dismiss ignored during drag")
            return
        }
        guard Date() >= backgroundDismissLockedUntil else {
            LaunchLog.line("background dismiss ignored after show")
            return
        }
        guard Date() >= folderReopenLockedUntil else {
            LaunchLog.line("background dismiss ignored during folder close cooldown")
            return
        }
        handleEscape()
    }

    func registerSearchBar(_ bar: LauncherSearchBarView) {
        searchFocus.register(bar)
    }

    func focusSearchField() {
        searchFocus.focus()
    }

    func isSearchFieldFocused() -> Bool {
        searchFocus.isFocused()
    }

    func moveSelection(by delta: Int) {
        keyboardSelectionActive = true
        let items = visibleItems
        guard !items.isEmpty else {
            selectedItemID = nil
            return
        }

        let currentIndex = selectedItemID.flatMap { id in items.firstIndex { $0.id == id } } ?? currentPage * gridLayout.pageSize
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        let nextPage = nextIndex / gridLayout.pageSize
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
        query.isEmpty && keyboardSelectionActive && selectedItemID == id
    }

    func closeFolder() {
        LaunchLog.line("closeFolder called wasOpen=\(openFolder != nil)")
        if openFolder != nil {
            folderReopenLockedUntil = Date().addingTimeInterval(0.25)
        }
        openFolder = nil
        endFolderReorder()
    }

    func openFolderFromTap(_ folder: LaunchFolder) {
        guard Date() >= folderReopenLockedUntil else {
            LaunchLog.line("folder icon tap ignored during close cooldown id=\(folder.id)")
            return
        }
        guard openFolder == nil else {
            LaunchLog.line("folder icon tap ignored, folder already open id=\(folder.id)")
            return
        }
        LaunchLog.line("folder icon tap open id=\(folder.id)")
        openFolder = folder
    }

    func selectPage(_ page: Int) {
        let nextPage = min(max(page, 0), pageCount - 1)
        guard nextPage != currentPage else { return }
        LaunchLog.line("select page \(currentPage) -> \(nextPage) pageCount=\(pageCount)")
        currentPage = nextPage
        if keyboardSelectionActive {
            selectedItemID = items(forPage: nextPage).first?.id
        }
    }

    func changePage(_ delta: Int) {
        guard delta != 0 else { return }
        guard !isDraggingLauncherItem else {
            LaunchLog.line("change page blocked drag")
            return
        }
        guard query.isEmpty else {
            LaunchLog.line("change page blocked query=\(query)")
            return
        }
        guard openFolder == nil else {
            LaunchLog.line("change page blocked openFolder")
            return
        }
        guard displayMode == .paged else {
            LaunchLog.line("change page blocked displayMode=\(displayMode.rawValue)")
            return
        }
        guard Date() >= pageChangeLockedUntil else {
            LaunchLog.line("change page blocked cooldown")
            return
        }
        let oldPage = currentPage
        selectPage(currentPage + delta)
        if currentPage != oldPage {
            pageChangeLockedUntil = Date().addingTimeInterval(LaunchConstants.Launcher.pageChangeCooldown)
        }
    }

    fileprivate func selectedItem() -> LauncherItem? {
        guard let selectedItemID else { return nil }
        return visibleItems.first { $0.id == selectedItemID }
    }

    func handleQueryChange(prevSearchEmpty: Bool) {
        if prevSearchEmpty, !searchQuery.isEmpty {
            pageBeforeSearch = currentPage
            selectionBeforeSearch = selectedItemID
            currentPage = 0
            keyboardSelectionActive = false
            selectedItemID = nil
        } else if !prevSearchEmpty, searchQuery.isEmpty {
            currentPage = min(pageBeforeSearch, pageCount - 1)
            selectedItemID = selectionBeforeSearch
            ensureSelection()
        } else if !searchQuery.isEmpty {
            currentPage = 0
            keyboardSelectionActive = false
            selectedItemID = nil
        }
    }

    func clearSearch() {
        query = ""
    }
}

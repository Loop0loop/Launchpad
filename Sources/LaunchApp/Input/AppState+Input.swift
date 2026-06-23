import Foundation

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

    func focusSearchField() {
        guard let searchField else {
            LaunchLog.line("search focus skipped field=nil")
            return
        }
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.isEnabled = true
        searchField.window?.makeKey()
        let accepted = searchField.window?.makeFirstResponder(searchField) ?? false
        let responder = String(describing: type(of: searchField.window?.firstResponder as Any))
        LaunchLog.line("search focus ok=\(accepted) responder=\(responder)")
    }

    func isSearchFieldFocused() -> Bool {
        guard let searchField, let firstResponder = searchField.window?.firstResponder else { return false }
        if firstResponder === searchField { return true }
        if firstResponder === searchField.currentEditor() { return true }
        return false
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
        keyboardSelectionActive && selectedItemID == id
    }

    func closeFolder() {
        openFolder = nil
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

    func goToPage(_ page: Int) {
        guard Date() >= pageChangeLockedUntil else { return }
        let oldPage = currentPage
        selectPage(page)
        if currentPage != oldPage {
            pageChangeLockedUntil = Date().addingTimeInterval(LaunchConstants.Launcher.pageChangeCooldown)
        }
    }

    func changePage(_ delta: Int) {
        guard delta != 0 else { return }
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

import AppKit
import LaunchCore

@MainActor
final class LauncherMouseMonitor {
    private weak var window: NSWindow?
    private weak var state: AppState?
    private var monitor: Any?
    private var isEnabled = false

    private var dragOffset: CGFloat = 0
    private var dragStartPage = 0
    private var pageLockedUntil = Date.distantPast
    private var mouseDownStartedOnItem = false

    func configure(window: NSWindow, state: AppState) {
        self.window = window
        self.state = state
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            dragOffset = 0
            state?.pageDragOffset = 0
        }
    }

    func stop() {
        setEnabled(false)
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isEnabled, let window, let state else { return event }
        guard state.launcherVisible, window.isVisible else { return event }
        guard event.window === window else { return event }

        switch event.type {
        case .leftMouseDown:
            return handleMouseDown(event, state: state)
        case .leftMouseDragged:
            return handleMouseDragged(event, state: state)
        case .leftMouseUp:
            return handleMouseUp(event, state: state)
        default:
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent, state: AppState) -> NSEvent? {
        if hitsSearchBar(event) {
            LaunchLog.line("mouse search click down")
            state.focusSearchField()
            return event
        }

        mouseDownStartedOnItem = hitsLauncherItem(event)
        if mouseDownStartedOnItem {
            return event
        }

        guard state.openFolder == nil, state.query.isEmpty else { return event }
        guard Date() >= pageLockedUntil else { return event }

        dragOffset = 0
        dragStartPage = state.currentPage
        state.pageDragOffset = 0
        return event
    }

    private func handleMouseDragged(_ event: NSEvent, state: AppState) -> NSEvent? {
        // Item presses are .onDrag — accumulating pageDragOffset here re-renders the grid mid-drag and cancels folder drops.
        if mouseDownStartedOnItem { return event }

        guard state.openFolder == nil, state.query.isEmpty, state.displayMode == .paged else { return event }
        guard Date() >= pageLockedUntil else { return event }

        dragOffset += event.deltaX
        let pageWidth = window?.frame.width ?? 0
        guard pageWidth > 0 else { return event }

        let maxRubber = pageWidth * LaunchConstants.Launcher.pageRubberBandRatio
        if dragStartPage == 0, dragOffset > 0 {
            dragOffset = min(dragOffset, maxRubber)
        }
        if dragStartPage == state.pageCount - 1, dragOffset < 0 {
            dragOffset = max(dragOffset, -maxRubber)
        }

        state.pageDragOffset = dragOffset
        return event
    }

    private func handleMouseUp(_ event: NSEvent, state: AppState) -> NSEvent? {
        defer {
            dragOffset = 0
            state.pageDragOffset = 0
            mouseDownStartedOnItem = false
        }

        if hitsSearchBar(event) {
            LaunchLog.line("mouse search click up")
            state.focusSearchField()
            return event
        }

        if mouseDownStartedOnItem {
            return event
        }

        let pageWidth = window?.frame.width ?? 0
        let dragged = abs(dragOffset) >= LaunchConstants.Launcher.dragMinimumDistance

        if dragged, state.openFolder == nil, state.query.isEmpty, state.displayMode == .paged, pageWidth > 0 {
            let threshold = max(pageWidth * LaunchConstants.Launcher.pageSwipeThresholdRatio, LaunchConstants.Launcher.pageDragThreshold)
            var target = dragStartPage

            if dragOffset < -threshold {
                target = min(dragStartPage + 1, state.pageCount - 1)
            } else if dragOffset > threshold {
                target = max(dragStartPage - 1, 0)
            }

            if target != dragStartPage {
                state.selectPage(target)
                pageLockedUntil = Date().addingTimeInterval(LaunchConstants.Launcher.pageChangeCooldown)
            }
            return event
        }

        // Dismissal (empty space / folder close) is owned by SwiftUI tap layers; the
        // monitor only handles search focus and page dragging.
        return event
    }

    private func hitsSearchBar(_ event: NSEvent) -> Bool {
        guard let window, let contentView = window.contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)

        if let bar = state?.searchFocus.barView {
            let local = bar.convert(point, from: contentView)
            if bar.bounds.contains(local) {
                return true
            }
        }

        return searchBarLayoutRect(in: contentView)?.contains(point) == true
    }

    private func searchBarLayoutRect(in contentView: NSView) -> NSRect? {
        guard let state else { return nil }
        let size = contentView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let layout = LaunchpadLayoutMetrics(
            size: size,
            columns: state.gridLayout.columns,
            rows: state.gridLayout.rows
        )
        let width = LaunchConstants.Launcher.searchWidth + 24
        let height = layout.searchBarHeight + 16
        let x = (size.width - width) / 2
        let y = layout.safeTopInset - 8
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func hitsLauncherItem(_ event: NSEvent) -> Bool {
        guard let window, let contentView = window.contentView, let state else { return false }
        guard state.openFolder == nil, state.query.isEmpty else { return false }

        let point = contentView.convert(event.locationInWindow, from: nil)
        let size = contentView.bounds.size
        guard size.width > 0, size.height > 0 else { return false }

        let layout = LaunchpadLayoutMetrics(
            size: size,
            columns: state.gridLayout.columns,
            rows: state.gridLayout.rows
        )
        let showsPageControl = state.pageCount > 1
        let gridHeight = layout.gridHeight(showsPageControl: showsPageControl)
        // contentView (LauncherPresentationContainer) is flipped, so point.y is already
        // measured from the top — matching the top-down layout metrics below.
        let yFromTop = point.y
        let gridTop = layout.topChromeHeight
        guard yFromTop >= gridTop, yFromTop <= gridTop + gridHeight else { return false }

        let xInGrid = point.x - layout.horizontalPadding
        guard xInGrid >= 0, xInGrid <= layout.gridWidth else { return false }

        let columnSlotWidth = layout.columnWidth + layout.gridColumnSpacing
        let column = Int(xInGrid / max(columnSlotWidth, 1))
        let columnStart = CGFloat(column) * columnSlotWidth
        guard xInGrid >= columnStart, xInGrid <= columnStart + layout.columnWidth else { return false }

        let row = Int(((yFromTop - gridTop) / max(gridHeight, 1)) * CGFloat(layout.rows))
        guard column >= 0, column < layout.columns, row >= 0, row < layout.rows else { return false }

        let index = row * layout.columns + column
        let hit = index < state.items(forPage: state.currentPage).count
        if hit {
            LaunchLog.line("mouse item click page=\(state.currentPage) index=\(index)")
        }
        return hit
    }
}

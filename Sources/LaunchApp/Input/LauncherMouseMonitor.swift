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
        if isSearchClick(event) {
            LaunchLog.line("mouse search click down")
            state.focusSearchField()
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
        }

        if isSearchClick(event) {
            LaunchLog.line("mouse search click up")
            state.focusSearchField()
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

        if isBackgroundClick(event) {
            LaunchLog.line("mouse background click")
            state.dismissFromBackground()
        }

        return event
    }

    private func isSearchClick(_ event: NSEvent) -> Bool {
        guard let window, let contentView = window.contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        let size = contentView.bounds.size
        let layout = LaunchpadLayoutMetrics(
            size: size,
            columns: state?.gridLayout.columns ?? LaunchConstants.Launcher.columns,
            rows: state?.gridLayout.rows ?? LaunchConstants.Launcher.rows
        )
        let searchX = (size.width - LaunchConstants.Launcher.searchWidth) / 2
        let searchY = size.height - layout.safeTopInset - layout.searchBarHeight
        let searchRect = NSRect(
            x: searchX - 40,
            y: searchY - 12,
            width: LaunchConstants.Launcher.searchWidth + 80,
            height: layout.searchBarHeight + 24
        )
        return searchRect.contains(point)
    }

    private func isBackgroundClick(_ event: NSEvent) -> Bool {
        if isSearchClick(event) { return false }
        guard let window, let contentView = window.contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hit = contentView.hitTest(point) else { return true }
        return !isInteractiveView(hit)
    }

    private func isInteractiveView(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let view = current {
            if view is NSControl { return true }
            if view is NSTextView { return true }
            if view is NSScrollView { return true }
            if String(describing: type(of: view)).contains("TextField") { return true }
            current = view.superview
        }
        return false
    }
}

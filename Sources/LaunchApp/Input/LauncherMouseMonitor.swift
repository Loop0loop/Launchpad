import AppKit
import SwiftUI
import LaunchpadCore

/// Empty-space page swiping. Icon dragging and edge paging are owned by
/// `LauncherNativeDragController` so page reconstruction cannot end the drag session.
@MainActor
final class LauncherMouseMonitor {
    private weak var window: NSWindow?
    private weak var state: AppState?
    private var monitor: Any?
    private var isEnabled = false

    private var tracking = false
    private var dragOffset: CGFloat = 0
    private var dragVelocityX: CGFloat = 0
    private var lastDragTime = Date.distantPast
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
        if !enabled { reset() }
    }

    func stop() {
        setEnabled(false)
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func reset() {
        tracking = false
        dragOffset = 0
        dragVelocityX = 0
        state?.pageDragOffset = 0
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isEnabled, let window, let state else { return event }
        guard state.launcherVisible, window.isVisible, event.window === window else { return event }
        switch event.type {
        case .leftMouseDown: return down(event, state)
        case .leftMouseDragged: return dragged(event, state)
        case .leftMouseUp: return up(event, state)
        default: return event
        }
    }

    private func down(_ event: NSEvent, _ state: AppState) -> NSEvent? {
        if state.isHandlingLauncherDrag {
            LaunchLog.line("LauncherMouseMonitor down: cancelling active/stale drag")
            state.cancelDrag(reason: "new-mouse-down")
        }

        // Outside-click-to-close is handled by the SwiftUI FolderDimLayer. A hand-rolled
        // panel rect here underestimated the real panel and swallowed clicks on its edges
        // (title field, edge icons) — breaking folder rename/reorder. Let the guard
        // below simply not start page-swipe tracking while a folder is open.
        guard state.openFolder == nil, state.query.isEmpty, state.displayMode == .paged, Date() >= pageLockedUntil else {
            tracking = false
            return event
        }
        tracking = true
        dragOffset = 0
        dragVelocityX = 0
        lastDragTime = Date()
        dragStartPage = state.currentPage
        state.pageDragOffset = 0
        return event
    }

    private func dragged(_ event: NSEvent, _ state: AppState) -> NSEvent? {
        if state.isDraggingLauncherItem {
            // An item drag took over a press that began as page-swipe tracking. Drop the
            // page swipe so releasing the icon doesn't also fire a page change.
            if tracking {
                tracking = false
                dragOffset = 0
                state.pageDragOffset = 0
            }
            return event
        }

        guard tracking else { return event }
        let now = Date()
        let dt = now.timeIntervalSince(lastDragTime)
        if dt > 0 {
            dragVelocityX = event.deltaX / dt
        }
        lastDragTime = now
        dragOffset += event.deltaX
        let pageWidth = window?.frame.width ?? 0
        guard pageWidth > 0 else { return event }

        let maxRubber = pageWidth * LaunchConstants.Launcher.pageRubberBandRatio
        if dragStartPage == 0, dragOffset > 0 { dragOffset = min(dragOffset, maxRubber) }
        if dragStartPage == state.pageCount - 1, dragOffset < 0 { dragOffset = max(dragOffset, -maxRubber) }
        guard abs(dragOffset - state.pageDragOffset) >= LaunchConstants.Launcher.pageDragUpdateStep else { return event }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            state.pageDragOffset = dragOffset
        }
        return event
    }

    private func up(_ event: NSEvent, _ state: AppState) -> NSEvent? {
        if state.dragAwaitingMouseUp {
            state.finishCommittedMergeDrag()
            reset()
            return event
        }
        guard tracking, !state.isDraggingLauncherItem else {
            reset()
            return event
        }
        let pageWidth = window?.frame.width ?? 0
        guard pageWidth > 0 else {
            reset()
            return event
        }

        let target = targetPage(pageWidth: pageWidth, state: state)
        tracking = false
        dragOffset = 0
        dragVelocityX = 0
        withAnimation(LaunchConstants.Animation.pageSnap) {
            if let target {
                state.selectPage(target)
            }
            state.pageDragOffset = 0
        }

        if target != nil {
            pageLockedUntil = Date().addingTimeInterval(LaunchConstants.Launcher.pageChangeCooldown)
        }
        return event
    }

    private func targetPage(pageWidth: CGFloat, state: AppState) -> Int? {
        guard abs(dragOffset) >= LaunchConstants.Launcher.dragMinimumDistance else { return nil }
        switch TrackpadIntent.pageSwipe(
            offset: Double(dragOffset),
            velocity: Double(dragVelocityX),
            pageWidth: Double(pageWidth),
            distanceThreshold: Double(LaunchConstants.Launcher.pageDragThreshold),
            distanceRatio: Double(LaunchConstants.Launcher.pageSwipeThresholdRatio)
        ) {
        case .nextPage:
            let target = min(dragStartPage + 1, state.pageCount - 1)
            return target == dragStartPage ? nil : target
        case .previousPage:
            let target = max(dragStartPage - 1, 0)
            return target == dragStartPage ? nil : target
        default:
            return nil
        }
    }
}
